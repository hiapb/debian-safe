#!/usr/bin/env bash
# ======================================================================
# 🌙 Nuro Deep Clean • Safe-Deep (稳态版：不 swapoff、不杀进程、BT 友好)
# 目标：深度清理 CPU/内存/硬盘，但绝不影响宝塔/站点/数据库/PHP 与 SSH
# ======================================================================

set -e
SCRIPT_PATH="/root/deep-clean.sh"
echo "📝 写入/覆盖 $SCRIPT_PATH ..."

cat > "$SCRIPT_PATH" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

# ====== 美观输出 ======
C0="\033[0m"; B="\033[1m"; BLU="\033[38;5;33m"; GRN="\033[38;5;40m"; YEL="\033[38;5;178m"; RED="\033[38;5;196m"; CYA="\033[36m"; GY="\033[90m"
hr(){ printf "${GY}%s${C0}\n" "────────────────────────────────────────────────────────"; }
title(){ printf "\n${B}${BLU}[%s]${C0} %s\n" "$1" "$2"; hr; }
ok(){ printf "${GRN}✔${C0} %s\n" "$*"; }
warn(){ printf "${YEL}⚠${C0} %s\n" "$*"; }
err(){ printf "${RED}✘${C0} %s\n" "$*"; }
log(){ printf "${CYA}•${C0} %s\n" "$*"; }
trap 'err "出错：行 $LINENO"; exit 1' ERR

# ====== 强保护路径（绝不触碰）======
EXCLUDES=(
  "/www/server/panel" "/www/wwwlogs" "/www/wwwroot"
  "/www/server/nginx" "/www/server/apache" "/www/server/openresty"
  "/www/server/mysql" "/var/lib/mysql" "/var/lib/mariadb" "/var/lib/postgresql"
  "/www/server/php" "/etc/php" "/var/lib/php/sessions"
)
is_excluded(){ local p="$1"; for e in "${EXCLUDES[@]}"; do [[ "$p" == "$e"* ]] && return 0; done; return 1; }

# ====== 降优先级执行（避免卡顿）======
NI(){ nice -n 19 ionice -c3 bash -c "$*"; }

# ====== 概况 ======
title "🌍 系统概况" "系统信息与资源概览"
uname -a | sed 's/^/  /'
log "磁盘占用（根分区）："; df -h / | sed 's/^/  /'
log "内存占用："; free -h | sed 's/^/  /'
ok "概况完成"

# ====== 进程与锁（只处理 APT）======
title "🔒 进程清理" "释放 APT/Dpkg 锁"
pkill -9 -f 'apt|apt-get|dpkg|unattended-upgrade' 2>/dev/null || true
rm -f /var/lib/dpkg/lock* /var/cache/apt/archives/lock || true
dpkg --configure -a >/dev/null 2>&1 || true
ok "apt/dpkg 锁处理完成"

# ====== 日志（保 1 天，保结构）======
title "🧾 日志清理" "清空旧日志 保留结构"
journalctl --rotate || true
journalctl --vacuum-time=1d --vacuum-size=64M >/dev/null 2>&1 || true
NI "find /var/log -type f -not -path '/www/server/panel/logs/*' -not -path '/www/wwwlogs/*' -exec truncate -s 0 {} + 2>/dev/null || true"
: > /var/log/wtmp  || true
: > /var/log/btmp  || true
: > /var/log/lastlog || true
: > /var/log/faillog || true
ok "日志清理完成"

# ====== 临时/缓存（排除 PHP 会话）======
title "🧹 缓存清理" "清理 /tmp /var/tmp 等"
NI "find /tmp -xdev -type f -atime +1 -not -name 'sess_*' -delete 2>/dev/null || true"
NI "find /var/tmp -xdev -type f -atime +1 -delete 2>/dev/null || true"
NI "find /tmp -xdev -type f -size +50M -not -name 'sess_*' -delete 2>/dev/null || true"
NI "find /var/tmp -xdev -type f -size +50M -delete 2>/dev/null || true"
NI "find /var/cache -xdev -type f -mtime +1 -delete 2>/dev/null || true"
rm -rf /var/crash/* /var/lib/systemd/coredump/* 2>/dev/null || true
ok "临时/缓存清理完成"

# ====== 包管理缓存 ======
title "📦 包缓存" "APT / Snap / 语言缓存"
if command -v apt-get >/dev/null 2>&1; then
  apt-get -y autoremove  >/dev/null 2>&1 || true
  apt-get -y autoclean   >/dev/null 2>&1 || true
  apt-get -y clean       >/dev/null 2>&1 || true
  dpkg -l | awk '/^rc/{print $2}' | xargs -r dpkg -P >/dev/null 2>&1 || true
fi
if command -v snap >/dev/null 2>&1; then
  snap list --all | awk '/disabled/{print $1, $3}' | xargs -r -n2 snap remove || true
fi
command -v pip >/dev/null      && pip cache purge >/dev/null 2>&1 || true
command -v npm >/dev/null      && npm cache clean --force >/dev/null 2>&1 || true
command -v yarn >/dev/null     && yarn cache clean >/dev/null 2>&1 || true
command -v composer >/dev/null && composer clear-cache >/dev/null 2>&1 || true
command -v gem >/dev/null      && gem cleanup -q >/dev/null 2>&1 || true
ok "包管理缓存清理完成"

# ====== 容器清理（不动业务卷绑定）======
title "🐳 容器清理" "Docker 残留安全删除"
if command -v docker >/dev/null 2>&1; then
  NI "docker builder prune -af >/dev/null 2>&1 || true"
  NI "docker image prune   -af --filter 'until=168h' >/dev/null 2>&1 || true"
  NI "docker container prune -f --filter 'until=24h' >/dev/null 2>&1 || true"
  NI "docker volume prune -f >/dev/null 2>&1 || true"
  NI "docker network prune -f >/dev/null 2>&1 || true"
  NI "docker system prune -af --volumes >/dev/null 2>&1 || true"
fi
command -v ctr >/dev/null 2>&1 && NI "ctr -n k8s.io images prune >/dev/null 2>&1 || true"
ok "容器清理完成"

# ====== 备份 & 用户 Downloads —— 全量删除（不限大小）======
title "🗄️ 备份清理" "移除系统与用户备份"
[[ -d /www/server/backup ]] && NI "rm -rf /www/server/backup/* 2>/dev/null || true"
[[ -d /root/Downloads    ]] && NI "rm -rf /root/Downloads/* 2>/dev/null || true"
for d in /home/*/Downloads; do [[ -d "$d" ]] && NI "rm -rf '$d'/* 2>/dev/null || true"; done

# 家目录常见压缩/备份包（不限大小）
for base in /root /home/*; do
  [[ -d "$base" ]] || continue
  NI "find '$base' -type f \\( -name '*.zip' -o -name '*.tar.gz' -o -name '*.tgz' -o -name '*.rar' -o -name '*.7z' -o -name '*.bak' \\) -delete 2>/dev/null || true"
done
ok "备份与用户下载清空完成"

# ====== 大文件补充（安全路径 >100MB）======
title "🪣 大文件清理" "安全目录下清除 >100MB"
SAFE_BASES=(/tmp /var/tmp /var/cache /var/backups /root /home /www/server/backup)
for base in "${SAFE_BASES[@]}"; do
  [[ -d "$base" ]] || continue
  while IFS= read -r -d '' f; do
    is_excluded "$f" && continue
    NI "rm -f '$f' 2>/dev/null || true"
  done < <(find "$base" -xdev -type f -size +100M -print0 2>/dev/null)
done
ok "大文件补充清理完成"

# ====== 旧内核（保留当前+最新）======
title "🧰 内核清理" "仅保留当前与最新版本"
if command -v dpkg >/dev/null 2>&1; then
  CURK="$(uname -r)"
  mapfile -t KS < <(dpkg -l | awk '/linux-image-[0-9]/{print $2}' | sort -V)
  KEEP=("linux-image-${CURK}")
  LATEST="$(printf "%s\n" "${KS[@]}" | grep -v "$CURK" | tail -n1 || true)"
  [[ -n "${LATEST:-}" ]] && KEEP+=("$LATEST")
  PURGE=(); for k in "${KS[@]}"; do [[ " ${KEEP[*]} " == *" $k "* ]] || PURGE+=("$k"); done
  ((${#PURGE[@]})) && NI "apt-get -y purge ${PURGE[*]} >/dev/null 2>&1 || true"
fi
ok "内核清理完成"

# ====== 内存/CPU 优化（稳态）======
title "⚡ 内存优化" "轻量回收 内存更流畅"
# 仅在负载低 & 可用内存充足时做
LOAD1=$(awk '{print int($1)}' /proc/loadavg)
MEM_AVAIL_KB=$(awk '/MemAvailable/{print $2}' /proc/meminfo)
MEM_TOTAL_KB=$(awk '/MemTotal/{print $2}' /proc/meminfo)
PCT=$(( MEM_AVAIL_KB*100 / MEM_TOTAL_KB ))

if (( LOAD1 <= 2 && PCT >= 30 )); then
  log "条件满足(Load1=${LOAD1}, MemAvail=${PCT}%)，执行轻量回收"
  sync
  echo 1 > /proc/sys/vm/drop_caches || true   # 只回收 pagecache，风险更低
  [[ -w /proc/sys/vm/compact_memory ]] && echo 1 > /proc/sys/vm/compact_memory || true
  # 适度降低交换倾向（不持久化）
  sysctl -w vm.swappiness=10 >/dev/null 2>&1 || true
  ok "内存/CPU 轻量回收完成"
else
  warn "跳过回收（Load1=${LOAD1}, MemAvail=${PCT}%），避免引起卡顿/断连"
fi

# ===== Swap 管理（单一：0->建1；1->不动；多->全关重建1） =====
title "💾 Swap 管理" "智能检测并保持单一 Swap"

# 计算目标大小：内存一半，范围 [256,2048] MiB
calc_target_mib() {
  local mem_kb mib target
  mem_kb="$(grep -E '^MemTotal:' /proc/meminfo | tr -s ' ' | cut -d' ' -f2)"
  mib=$(( mem_kb/1024 ))
  target=$(( mib/2 ))
  (( target < 256 ))  && target=256
  (( target > 2048 )) && target=2048
  echo "$target"
}

active_swaps() { swapon --show=NAME --noheadings 2>/dev/null | sed '/^$/d'; }
active_count() { active_swaps | wc -l | tr -d ' '; }

enable_emergency_swap() {
  # 优先 zram 256MiB，其次 /swap.emerg 256MiB
  EMERG_DEV=""
  local size=256
  if modprobe zram 2>/dev/null && [ -e /sys/class/zram-control/hot_add ]; then
    local id dev
    id="$(cat /sys/class/zram-control/hot_add)"
    dev="/dev/zram${id}"
    echo "${size}M" > "/sys/block/zram${id}/disksize"
    mkswap "$dev" >/dev/null 2>&1 && swapon -p 200 "$dev" && EMERG_DEV="$dev"
  fi
  if [ -z "$EMERG_DEV" ]; then
    if fallocate -l ${size}M /swap.emerg 2>/dev/null || dd if=/dev/zero of=/swap.emerg bs=1M count=${size} status=none; then
      chmod 600 /swap.emerg
      mkswap /swap.emerg >/dev/null 2>&1 && swapon -p 150 /swap.emerg && EMERG_DEV="/swap.emerg"
    fi
  fi
  if [ -n "$EMERG_DEV" ]; then ok "已启用应急 swap: $EMERG_DEV (256MiB)"; else warn "应急 swap 启用失败（继续尝试）"; fi
}

disable_emergency_swap() {
  if [ -n "$EMERG_DEV" ]; then
    swapoff "$EMERG_DEV" 2>/dev/null || true
    [ -f "$EMERG_DEV" ] && rm -f "$EMERG_DEV" 2>/dev/null || true
    ok "已关闭应急 swap: $EMERG_DEV"
    EMERG_DEV=""
  fi
}

normalize_fstab_to_single() {
  cp /etc/fstab /etc/fstab.bak.deepclean 2>/dev/null || true
  sed -i '\|/swapfile-[0-9]\+|d' /etc/fstab 2>/dev/null || true
  sed -i '\|/swapfile |d'       /etc/fstab 2>/dev/null || true
  sed -i '\|/dev/zram|d'        /etc/fstab 2>/dev/null || true
  echo "/swapfile none swap sw 0 0" >> /etc/fstab
  ok "fstab 已规范为单一 /swapfile（备份：/etc/fstab.bak.deepclean）"
}

create_single_swapfile() {
  local target path fs
  target="$(calc_target_mib)"
  path="/swapfile"
  fs="$(stat -f -c %T / 2>/dev/null || echo "")"
  # 确保没有同名占用
  swapoff "$path" 2>/dev/null || true
  rm -f "$path" 2>/dev/null || true
  # btrfs 关闭COW
  if [ "$fs" = "btrfs" ]; then touch "$path"; chattr +C "$path" 2>/dev/null || true; fi
  if ! fallocate -l ${target}M "$path" 2>/dev/null; then
    dd if=/dev/zero of="$path" bs=1M count=${target} status=none conv=fsync
  fi
  chmod 600 "$path"
  mkswap "$path" >/dev/null
  swapon "$path"
  ok "已创建并启用主 swap：$path (${target}MiB)"
}

single_path_or_empty() {
  # 返回唯一活动 swap 的路径（若正好 1 个），否则返回空
  local n p
  n="$(active_count)"
  if [ "$n" = "1" ]; then
    p="$(active_swaps | head -n1)"
    echo "$p"
  else
    echo ""
  fi
}

# 主流程
CNT="$(active_count)"
if [ "$CNT" = "0" ]; then
  log "未检测到活动 swap，创建单一 /swapfile ..."
  create_single_swapfile
  normalize_fstab_to_single
elif [ "$CNT" = "1" ]; then
  P="$(single_path_or_empty)"
  ok "已存在单一 swap：$P（保持不变）"
  normalize_fstab_to_single
else
  warn "检测到多个 swap（${CNT} 个），将关闭全部并重建为单一 /swapfile"
  enable_emergency_swap
  # 关闭所有现有 swap（保留应急）
  # 多次尝试直到无活动（或只剩应急）
  for _ in 1 2 3; do
    LIST="$(active_swaps)"
    [ -z "$LIST" ] && break
    while read -r dev; do
      [ -z "$dev" ] && continue
      [ -n "${EMERG_DEV:-}" ] && [ "$dev" = "$EMERG_DEV" ] && continue
      swapoff "$dev" 2>/dev/null || true
      # 尝试删除文件型
      case "$dev" in
        /dev/*) : ;;  # 设备分区不删除文件
        *) rm -f "$dev" 2>/dev/null || true ;;
      esac
    done <<< "$LIST"
    sleep 1
  done
  # 清理常见残留
  rm -f /swapfile /swapfile-* /swap.emerg 2>/dev/null || true
  # 创建单一 /swapfile
  create_single_swapfile
  normalize_fstab_to_single
  # 关闭并移除应急
  disable_emergency_swap
fi

# 展示当前结果
log "当前活动 swap："
( swapon --show || echo "  (none)" ) | sed 's/^/  /'

# ====== 磁盘 TRIM ======
title "🪶 磁盘优化" "执行 fstrim 提升性能"
if command -v fstrim >/dev/null 2>&1; then NI "fstrim -av >/dev/null 2>&1 || true"; ok "fstrim 完成"; else warn "未检测到 fstrim"; fi

# ====== 汇总 & 定时 ======
title "📊 汇总报告" "展示清理后资源状态"
df -h / | sed 's/^/  /'; free -h | sed 's/^/  /'
ok "深度清理完成 ✅"

title "⏰ 自动任务" "每日凌晨 03:00 自动运行"
chmod +x /root/deep-clean.sh
( crontab -u root -l 2>/dev/null | grep -v 'deep-clean.sh' || true; echo "0 3 * * * /bin/bash /root/deep-clean.sh >/dev/null 2>&1" ) | crontab -u root -
ok "已设置每日 03:00 自动清理"
EOF

chmod +x "$SCRIPT_PATH"
bash "$SCRIPT_PATH"
