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
title "系统概况" "采集中"
uname -a | sed 's/^/  /'
log "磁盘占用（根分区）："; df -h / | sed 's/^/  /'
log "内存占用："; free -h | sed 's/^/  /'
ok "概况完成"

# ====== 进程与锁（只处理 APT）======
title "进程与锁" "清理 apt/dpkg 残留锁（不杀 web/db/php）"
pkill -9 -f 'apt|apt-get|dpkg|unattended-upgrade' 2>/dev/null || true
rm -f /var/lib/dpkg/lock* /var/cache/apt/archives/lock || true
dpkg --configure -a >/dev/null 2>&1 || true
ok "apt/dpkg 锁处理完成"

# ====== 日志（保 1 天，保结构）======
title "日志清理" "journal + 常规日志（不删活动目录）"
journalctl --rotate || true
journalctl --vacuum-time=1d --vacuum-size=64M >/dev/null 2>&1 || true
NI "find /var/log -type f -not -path '/www/server/panel/logs/*' -not -path '/www/wwwlogs/*' -exec truncate -s 0 {} + 2>/dev/null || true"
: > /var/log/wtmp  || true
: > /var/log/btmp  || true
: > /var/log/lastlog || true
: > /var/log/faillog || true
ok "日志清理完成"

# ====== 临时/缓存（排除 PHP 会话）======
title "临时与缓存" "/tmp /var/tmp /var/cache（安全）"
NI "find /tmp -xdev -type f -atime +1 -not -name 'sess_*' -delete 2>/dev/null || true"
NI "find /var/tmp -xdev -type f -atime +1 -delete 2>/dev/null || true"
NI "find /tmp -xdev -type f -size +50M -not -name 'sess_*' -delete 2>/dev/null || true"
NI "find /var/tmp -xdev -type f -size +50M -delete 2>/dev/null || true"
NI "find /var/cache -xdev -type f -mtime +1 -delete 2>/dev/null || true"
rm -rf /var/crash/* /var/lib/systemd/coredump/* 2>/dev/null || true
ok "临时/缓存清理完成"

# ====== 包管理缓存 ======
title "包管理缓存" "APT / Snap / 语言包"
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
title "容器清理" "Docker 构建缓存/镜像/卷/网络（低优先级）"
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
title "备份与用户下载" "全部清空（保护站点/DB/PHP）"
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
title "大文件补充清理" "安全路径 >100MB"
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
title "旧内核清理" "仅移除非当前且非最新"
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
title "内存/CPU 优化" "温和回收（不 swapoff、不杀进程）"
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

# ===== Swap 强制重建（关闭所有，再重建为单一 /swapfile） =====
title "Swap Rebuild" "swapoff all -> build a single /swapfile"

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

# 创建应急 swap：优先 zram(256MiB)，不行则临时文件 /swap.emerg (256MiB)
EMERG_DEV=""
ensure_emergency_swap() {
  local size=256
  # 优先 zram
  if modprobe zram 2>/dev/null && [[ -e /sys/class/zram-control/hot_add ]]; then
    local id dev="/dev/zram$(cat /sys/class/zram-control/hot_add)"
    echo "${size}M" > "/sys/block/$(basename "$dev")/disksize"
    mkswap "$dev" >/dev/null 2>&1 && swapon -p 200 "$dev" && EMERG_DEV="$dev"
  fi
  # 退回临时文件
  if [[ -z "$EMERG_DEV" ]]; then
    if fallocate -l ${size}M /swap.emerg 2>/dev/null || dd if=/dev/zero of=/swap.emerg bs=1M count=${size} status=none; then
      chmod 600 /swap.emerg
      mkswap /swap.emerg >/dev/null 2>&1 && swapon -p 150 /swap.emerg && EMERG_DEV="/swap.emerg"
    fi
  fi
  if [[ -n "$EMERG_DEV" ]]; then ok "emergency swap on: $EMERG_DEV (256MiB)"; else warn "failed to enable emergency swap"; fi
}

# 关闭所有活动 swap（包括 /swapfile 与各类 swapfile/分区/zram）
swapoff_all() {
  local listed names
  # 多次尝试，直到没有活动 swap
  for _ in 1 2 3; do
    listed="$(swapon --show=NAME --noheadings 2>/dev/null || true)"
    [[ -z "$listed" ]] && break
    while read -r dev; do
      [[ -z "$dev" ]] && continue
      swapoff "$dev" 2>/dev/null || true
    done <<< "$listed"
    sleep 1
  done
  if swapon --show | grep -q .; then
    warn "some swap still active:"
    swapon --show | sed 's/^/  /'
  else
    ok "all swapoff done"
  fi
}

# 清理残留 swap 文件
cleanup_swapfiles() {
  # 清理常见路径：/swapfile /swapfile-* /swap.emerg
  rm -f /swap.emerg 2>/dev/null || true
  rm -f /swapfile 2>/dev/null || true
  rm -f /swapfile-* 2>/dev/null || true
}

# 写 fstab 只留 /swapfile
write_fstab_single() {
  cp /etc/fstab /etc/fstab.bak.deepclean 2>/dev/null || true
  sed -i '\|/swapfile-[0-9]\+|d' /etc/fstab 2>/dev/null || true
  sed -i '\|/swapfile |d'       /etc/fstab 2>/dev/null || true
  sed -i '\|/dev/zram|d'        /etc/fstab 2>/dev/null || true
  echo "/swapfile none swap sw 0 0" >> /etc/fstab
  ok "fstab normalized -> single /swapfile (backup: /etc/fstab.bak.deepclean)"
}

# 创建 /swapfile 并启用
create_main_swapfile() {
  local target size path fs
  target="$(calc_target_mib)"
  path="/swapfile"
  fs="$(stat -f -c %T / 2>/dev/null || echo "")"
  if [[ "$fs" == "btrfs" ]]; then touch "$path"; chattr +C "$path" 2>/dev/null || true; fi
  # 确保不存在同名、且没被占用
  rm -f "$path" 2>/dev/null || true
  if ! fallocate -l ${target}M "$path" 2>/dev/null; then
    dd if=/dev/zero of="$path" bs=1M count=${target} status=none conv=fsync
  fi
  chmod 600 "$path"
  mkswap "$path" >/dev/null
  swapon "$path"
  ok "main swap on: $path (${target}MiB)"
}

# 拆除应急 swap
teardown_emergency_swap() {
  if [[ -n "$EMERG_DEV" ]]; then
    swapoff "$EMERG_DEV" 2>/dev/null || true
    [[ -f "$EMERG_DEV" ]] && rm -f "$EMERG_DEV" 2>/dev/null || true
    ok "emergency swap off: $EMERG_DEV"
    EMERG_DEV=""
  fi
}

# === 执行顺序 ===
ttl "Swap Rebuild (force)"
ensure_emergency_swap
swapoff_all
cleanup_swapfiles
write_fstab_single
create_main_swapfile
teardown_emergency_swap

# 展示结果
log "active swap now:"
(swapon --show || echo "  (none)") | sed 's/^/  /'
# ====== 磁盘 TRIM ======
title "磁盘优化" "fstrim（若可用）"
if command -v fstrim >/dev/null 2>&1; then NI "fstrim -av >/dev/null 2>&1 || true"; ok "fstrim 完成"; else warn "未检测到 fstrim"; fi

# ====== 汇总 & 定时 ======
title "完成汇总" "当前资源状态"
df -h / | sed 's/^/  /'; free -h | sed 's/^/  /'
ok "深度清理完成 ✅"

title "计划任务" "写入 crontab (每日 03:00)"
chmod +x /root/deep-clean.sh
( crontab -u root -l 2>/dev/null | grep -v 'deep-clean.sh' || true; echo "0 3 * * * /bin/bash /root/deep-clean.sh >/dev/null 2>&1" ) | crontab -u root -
ok "已设置每日 03:00 自动清理"
EOF

chmod +x "$SCRIPT_PATH"
bash "$SCRIPT_PATH"
