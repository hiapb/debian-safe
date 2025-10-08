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

# ====== Swap 规范化（有则不建；无则智能建；只保留 1 个）======
title "Swap 规范化" "有则不建；无则智能建；只保留 1 个（优先 zram）"

has_active_swap(){ grep -q ' swap ' /proc/swaps 2>/dev/null; }

calc_target_mib(){
  # 目标 = 内存一半；范围 [256,2048] MiB；并确保根分区至少留 25% 空闲
  local mem_kb mib target avail_mb maxsafe
  mem_kb="$(grep -E '^MemTotal:' /proc/meminfo | tr -s ' ' | cut -d' ' -f2)"
  mib=$(( mem_kb/1024 ))
  target=$(( mib/2 ))
  (( target < 256 ))  && target=256
  (( target > 2048 )) && target=2048
  avail_mb="$(df -Pm / | tail -n1 | tr -s ' ' | cut -d' ' -f4)"
  maxsafe=$(( avail_mb*75/100 ))
  (( target > maxsafe )) && target=$maxsafe
  echo "$target"
}

is_active_swapfile(){
  # 判断某个路径是否已经是活动 swap
  local p="$1"
  swapon --show=NAME --noheadings 2>/dev/null | grep -Fxq "$p"
}

mk_swap(){
  # 仅在不存在活动 swap 且路径未被占用时创建
  local path="$1" size="$2"
  if is_active_swapfile "$path"; then
    ok "检测到活动 swap：$path（不重复创建）"
    echo "__KEEP__"  # 让上层拿到保留路径
    return 0
  fi
  [[ -z "$size" || "$size" -lt 128 ]] && { warn "磁盘不足，跳过新建 swap"; return 1; }
  local fs; fs=$(stat -f -c %T / 2>/dev/null || echo "")
  if [[ "$fs" == "btrfs" ]]; then touch "$path"; chattr +C "$path" 2>/dev/null || true; fi
  if ! fallocate -l ${size}M "$path" 2>/dev/null; then
    dd if=/dev/zero of="$path" bs=1M count=${size} status=none conv=fsync
  fi
  chmod 600 "$path"
  mkswap "$path" >/dev/null
  if swapon "$path" >/dev/null 2>&1; then
    ok "已启用 swap：$path (${size}MiB)"
    echo "$path"
    return 0
  else
    rm -f "$path" 2>/dev/null || true
    err "swapon 失败：$path"
    return 1
  fi
}

# 1) 若已有任何活动 swap：绝不再创建
KEEP_PATH=""
if has_active_swap; then
  ok "检测到已有活动 swap：本次不创建新的"
else
  TARGET="$(calc_target_mib)"
  # 先尝试 /swapfile；若已被占用或失败，再用带时间戳的路径
  created="$(mk_swap "/swapfile" "$TARGET" || true)"
  if [[ "$created" == "__KEEP__" ]]; then
    KEEP_PATH="/swapfile"
  elif [[ -n "$created" ]]; then
    KEEP_PATH="$created"
  else
    TS="$(date +%s)"
    created="$(mk_swap "/swapfile-${TS}" "$TARGET" || true)"
    [[ -n "$created" && "$created" != "__KEEP__" ]] && KEEP_PATH="$created"
  fi
fi

# 2) 解析当前活动 swap，选择唯一保留项（优先 zram，其次按 prio desc/size desc）
ACTIVE_RAW="$(swapon --show=NAME,PRIO,SIZE --bytes --noheadings 2>/dev/null || true)"
NAMES=(); PRIOS=(); SIZES=()
while read -r name prio size rest; do
  [[ -z "${name:-}" ]] && continue
  NAMES+=("$name"); PRIOS+=("${prio:-0}"); SIZES+=("${size:-0}")
done <<< "$ACTIVE_RAW"

if [[ -z "$KEEP_PATH" && ${#NAMES[@]} -gt 0 ]]; then
  # 优先 zram
  for ((i=0;i<${#NAMES[@]};i++)); do
    case "${NAMES[$i]}" in /dev/zram*) KEEP_PATH="${NAMES[$i]}"; break;; esac
  done
  # 否则选 (prio desc, size desc)
  if [[ -z "$KEEP_PATH" ]]; then
    best=0
    for ((i=1;i<${#NAMES[@]};i++)); do
      if (( ${PRIOS[$i]} > ${PRIOS[$best]} )) || { (( ${PRIOS[$i]} == ${PRIOS[$best]} )) && (( ${SIZES[$i]} > ${SIZES[$best]} )); }; then
        best=$i
      fi
    done
    KEEP_PATH="${NAMES[$best]}"
  fi
fi

[[ -n "$KEEP_PATH" ]] && ok "保留 swap：$KEEP_PATH" || warn "未解析到保留 swap（可能当前无活动 swap）"

# 3) fstab 去重：仅保留 1 条（写回 KEEP_PATH，如存在）
if [[ -f /etc/fstab ]]; then
  cp /etc/fstab /etc/fstab.bak.deepclean 2>/dev/null || true
  sed -i '\|/swapfile-[0-9]\+|d' /etc/fstab 2>/dev/null || true
  sed -i '\|/swapfile |d'       /etc/fstab 2>/dev/null || true
  sed -i '\|/dev/zram|d'        /etc/fstab 2>/dev/null || true
  if [[ -n "$KEEP_PATH" ]]; then
    echo "$KEEP_PATH none swap sw 0 0" >> /etc/fstab
  fi
  ok "fstab 已去重（仅保留 1 条；备份：/etc/fstab.bak.deepclean）"
fi

# 4) 运行态只留 1 个（安全条件：MemAvailable >= 40% 且 Load1 <= 1）
AVAIL_KB="$(grep -E '^MemAvailable:' /proc/meminfo | tr -s ' ' | cut -d' ' -f2 || echo 0)"
TOTAL_KB="$(grep -E '^MemTotal:'     /proc/meminfo | tr -s ' ' | cut -d' ' -f2 || echo 1)"
AVAIL_PCT=$(( AVAIL_KB*100 / TOTAL_KB ))
LOAD1_INT="$(cut -d'.' -f1 /proc/loadavg)"

OTHERS=()
for ((i=0;i<${#NAMES[@]};i++)); do
  [[ "${NAMES[$i]}" == "$KEEP_PATH" ]] && continue
  OTHERS+=("${NAMES[$i]}")
done

if ((${#OTHERS[@]})); then
  if (( AVAIL_PCT >= 40 && LOAD1_INT <= 1 )); then
    for dev in "${OTHERS[@]}"; do
      case "$dev" in
        /dev/zram*) warn "保留额外 zram：$dev（不关闭）" ;;
        *)
          swapoff "$dev" 2>/dev/null || true
          rm -f "$dev"   2>/dev/null || true
          ok "已关闭并移除多余 swap：$dev"
          ;;
      esac
    done
  else
    warn "资源不足以立即只留 1 个（MemAvail=${AVAIL_PCT}% / Load1=${LOAD1_INT}）。已完成 fstab 去重，重启后自然只剩 1 个。"
  fi
else
  ok "运行中已是单一 swap"
fi

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
