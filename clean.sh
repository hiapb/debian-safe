#!/usr/bin/env bash
# ======================================================================
# 💥 Nuro Deep Clean • Safe-Deep COLOR (BT友好 · 智能单一Swap · 彩色输出)
# - 深度清理 CPU/内存/硬盘
# - 智能 Swap：只保留 1 个；若无则新建（安全自适应容量）；去重 fstab
# - 宝塔/网站/数据库/PHP/session 强保护
# - 彩色美观输出；每天 03:00 自动执行
# ======================================================================

set -e
SCRIPT_PATH="/root/deep-clean.sh"

echo "📝 正在写入/覆盖 $SCRIPT_PATH ..."
cat > "$SCRIPT_PATH" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

# ============ 彩色输出 ============ #
C0="\033[0m"; B="\033[1m"; DIM="\033[2m"
BLU="\033[38;5;33m"; GRN="\033[38;5;40m"; YEL="\033[38;5;178m"; RED="\033[38;5;196m"; CYA="\033[36m"; GY="\033[90m"
hr(){ printf "${GY}%s${C0}\n" "────────────────────────────────────────────────────────"; }
ttl(){ printf "\n${B}${BLU}%s${C0}\n" "$1"; hr; }
ok(){  printf "${GRN}✔${C0} %s\n" "$*"; }
warn(){printf "${YEL}⚠${C0} %s\n" "$*"; }
err(){ printf "${RED}✘${C0} %s\n" "$*"; }
log(){ printf "${CYA}•${C0} %s\n" "$*"; }
trap 'err "出错：行 $LINENO"; exit 1' ERR

# ============ 强保护目录（绝不触碰）=========== #
EXCLUDES=(
  "/www/server/panel" "/www/wwwlogs" "/www/wwwroot"
  "/www/server/nginx" "/www/server/apache" "/www/server/openresty"
  "/www/server/mysql" "/var/lib/mysql" "/var/lib/mariadb" "/var/lib/postgresql"
  "/www/server/php" "/etc/php" "/var/lib/php/sessions"
)
is_excluded(){ local p="$1"; for e in "${EXCLUDES[@]}"; do [[ "$p" == "$e"* ]] && return 0; done; return 1; }

# ============ 降优先级工具 ============ #
NI(){ nice -n 19 ionice -c3 bash -c "$*"; }

# ============ 状态（前）=========== #
ttl "系统概况（清理前）"
uname -a | sed 's/^/  /'
log "磁盘（/）："; df -h / | sed 's/^/  /'
log "内存：";      free -h  | sed 's/^/  /'
log "Swap：";     (swapon --show || true) | sed 's/^/  /' || true
hr

# ============ 进程与锁（APT）=========== #
ttl "进程与锁（仅 APT 相关）"
pkill -9 -f 'apt|apt-get|dpkg|unattended-upgrade' 2>/dev/null || true
rm -f /var/lib/dpkg/lock* /var/cache/apt/archives/lock || true
dpkg --configure -a >/dev/null 2>&1 || true
ok "APT/dpkg 锁已清"

# ============ 日志（保1天，保结构）=========== #
ttl "日志清理（保留 1 天）"
journalctl --rotate || true
journalctl --vacuum-time=1d --vacuum-size=64M >/dev/null 2>&1 || true
find /var/log -type f \
  -not -path "/www/server/panel/logs/*" -not -path "/www/wwwlogs/*" \
  -exec truncate -s 0 {} \; 2>/dev/null || true
: > /var/log/wtmp  || true
: > /var/log/btmp  || true
: > /var/log/lastlog || true
: > /var/log/faillog || true
ok "日志清理完成"

# ============ 临时/缓存（排除 PHP 会话）=========== #
ttl "临时与缓存（安全）"
NI "find /tmp -xdev -type f -atime +1 -not -name 'sess_*' -delete 2>/dev/null || true"
NI "find /var/tmp -xdev -type f -atime +1 -delete 2>/dev/null || true"
NI "find /tmp     -xdev -type f -size +50M -not -name 'sess_*' -delete 2>/dev/null || true"
NI "find /var/tmp -xdev -type f -size +50M -delete 2>/dev/null || true"
NI "find /var/cache -xdev -type f -mtime +1 -delete 2>/dev/null || true"
rm -rf /var/crash/* /var/lib/systemd/coredump/* 2>/dev/null || true
ok "临时/缓存清理完成"

# ============ 包管理缓存 =========== #
ttl "包管理缓存（APT / Snap / 语言包）"
if command -v apt-get >/dev/null 2>&1; then
  apt-get -y autoremove >/dev/null 2>&1 || true
  apt-get -y autoclean  >/dev/null 2>&1 || true
  apt-get -y clean      >/dev/null 2>&1 || true
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

# ============ 容器清理（不动业务卷绑定）=========== #
ttl "容器清理（Docker / containerd）"
if command -v docker >/dev/null 2>&1; then
  NI "docker builder prune -af >/dev/null 2>&1 || true"
  NI "docker image prune   -af --filter 'until=168h' >/dev/null 2>&1 || true"
  NI "docker container prune -f --filter 'until=24h' >/dev/null 2>&1 || true"
  NI "docker volume prune -f  >/dev/null 2>&1 || true"
  NI "docker network prune -f >/dev/null 2>&1 || true"
  NI "docker system prune -af --volumes >/dev/null 2>&1 || true"
fi
command -v ctr >/dev/null 2>&1 && NI "ctr -n k8s.io images prune >/dev/null 2>&1 || true"
ok "容器清理完成"

# ============ 备份 & 用户 Downloads —— 全量删除（不限大小）=========== #
ttl "备份 & 用户下载（不限大小，全清）"
[[ -d /www/server/backup ]] && NI "rm -rf /www/server/backup/* 2>/dev/null || true"
[[ -d /root/Downloads    ]] && NI "rm -rf /root/Downloads/* 2>/dev/null || true"
for d in /home/*/Downloads; do [[ -d "$d" ]] && NI "rm -rf '$d'/* 2>/dev/null || true"; done
# 家目录里的常见压缩/备份包
for base in /root /home/*; do
  [[ -d "$base" ]] || continue
  NI "find '$base' -type f \\( -name '*.zip' -o -name '*.tar.gz' -o -name '*.tgz' -o -name '*.rar' -o -name '*.7z' -o -name '*.bak' \\) -delete 2>/dev/null || true"
done
ok "备份 & 下载清空完成"

# ============ 大文件补充（安全路径 >100MB）=========== #
ttl "大文件补充（安全路径 >100MB）"
SAFE_BASES=(/tmp /var/tmp /var/cache /var/backups /root /home /www/server/backup)
for base in "${SAFE_BASES[@]}"; do
  [[ -d "$base" ]] || continue
  while IFS= read -r -d '' f; do
    is_excluded "$f" && continue
    NI "rm -f '$f' 2>/dev/null || true"
  done < <(find "$base" -xdev -type f -size +100M -print0 2>/dev/null)
done
ok "大文件清理完成"

# ============ 旧内核（保留当前+最新）=========== #
ttl "旧内核（保留当前 + 最新）"
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

# ============ 内存/CPU（温和）=========== #
ttl "内存/CPU 优化（温和）"
LOAD1=$(awk '{print int($1)}' /proc/loadavg)
AVAIL_KB=$(awk '/MemAvailable/{print $2}' /proc/meminfo)
TOTAL_KB=$(awk '/MemTotal/{print $2}' /proc/meminfo)
AVAIL_PCT=$(( AVAIL_KB*100 / TOTAL_KB ))
if (( LOAD1 <= 2 && AVAIL_PCT >= 30 )); then
  sync
  echo 1 > /proc/sys/vm/drop_caches || true
  [[ -w /proc/sys/vm/compact_memory ]] && echo 1 > /proc/sys/vm/compact_memory || true
  ok "回收完成（Load1=${LOAD1}, 可用内存=${AVAIL_PCT}%）"
else
  warn "跳过（Load1=${LOAD1}, 可用内存=${AVAIL_PCT}%）"
fi

# ============ 智能 Swap：只保留 1 个；无则新建；去重 fstab =========== #
ttl "Swap 管理（智能去重，只保留 1 个）"
has_swap(){ grep -q ' swap ' /proc/swaps 2>/dev/null; }
calc_target_mib(){
  local mem_mib avail_mib target maxsafe
  mem_mib=$(awk '/MemTotal/ {printf "%.0f",$2/1024}' /proc/meminfo)  # MiB
  target=$(( mem_mib / 2 ))
  (( target < 256 ))  && target=256
  (( target > 2048 )) && target=2048
  avail_mib=$(df -Pm / | awk 'NR==2{print $4}')
  maxsafe=$(( avail_mib * 75 / 100 ))
  (( target > maxsafe )) && target=$maxsafe
  echo "$target"
}
mk_swap(){
  local path="$1" size="$2"
  [[ -z "$size" || "$size" -lt 128 ]] && { warn "磁盘不足，跳过新建 swap"; return 1; }
  local fs; fs=$(stat -f -c %T / 2>/dev/null || echo "")
  if [[ "$fs" == "btrfs" ]]; then touch "$path"; chattr +C "$path" 2>/dev/null || true; fi
  if ! fallocate -l ${size}M "$path" 2>/dev/null; then
    dd if=/dev/zero of="$path" bs=1M count=${size} status=none conv=fsync
  fi
  chmod 600 "$path"; mkswap "$path" >/dev/null; swapon "$path"
  sed -i '\|/swapfile|d' /etc/fstab 2>/dev/null || true
  sed -i '\|/swapfile-[0-9]\+|d' /etc/fstab 2>/dev/null || true
  echo "$path none swap sw 0 0" >> /etc/fstab
  ok "已启用 swap：$path (${size}MiB)"
  return 0
}

# 1) 若无 swap，则新建（优先 /swapfile，busy 就 /swapfile-TS）
if ! has_swap; then
  SIZE=$(calc_target_mib)
  if ! mk_swap "/swapfile" "$SIZE"; then
    TS=$(date +%s); mk_swap "/swapfile-${TS}" "$SIZE" || warn "无法创建文件型 swap；可考虑 zram"
  fi
else
  ok "已检测到 swap：保持运行中的 swap"
fi

# 2) fstab 去重：只保留 1 条（优先保留 zram；否则保留容量最大/优先级最高的）
#    运行态清理：若启用了多个 swap，则在“可用内存 ≥ 40%”时，逐个安全关闭多余的
# 2.1 解析当前启用的 swap 列表
ACTIVE_LIST=$(swapon --show=NAME,PRIO,SIZE --bytes --noheadings 2>/dev/null || true)
# 2.2 选择保留项（KEEP_PATH）
KEEP_PATH=""
if echo "$ACTIVE_LIST" | grep -q 'zram'; then
  KEEP_PATH=$(echo "$ACTIVE_LIST" | awk '/zram/{print $1; exit}')
else
  # 选择：优先级高的；若相同，选择 SIZE 最大的
  KEEP_PATH=$(echo "$ACTIVE_LIST" | awk '{printf "%s %s %s\n",$1,$2,$3}' \
    | sort -k2,2nr -k3,3nr | awk 'NR==1{print $1}')
fi
if [[ -n "$KEEP_PATH" ]]; then
  ok "保留运行中的 swap：$KEEP_PATH"
else
  warn "未能解析保留 swap（可能当前无 swap）"
fi

# 2.3 fstab 归一化：只保留 KEEP_PATH
if [[ -f /etc/fstab ]]; then
  cp /etc/fstab /etc/fstab.bak.deepclean 2>/dev/null || true
  # 删除所有 swapfile 条目
  sed -i '\|/swapfile-[0-9]\+|d' /etc/fstab 2>/dev/null || true
  sed -i '\|/swapfile |d'       /etc/fstab 2>/dev/null || true
  sed -i '\|/dev/zram|d'        /etc/fstab 2>/dev/null || true
  # 写回保留项（如果存在）
  if [[ -n "$KEEP_PATH" ]]; then
    echo "$KEEP_PATH none swap sw 0 0" >> /etc/fstab
  fi
  ok "fstab 已去重（备份：/etc/fstab.bak.deepclean）"
fi

# 2.4 运行态多余 swap：仅在内存充足时，逐个关闭并删除文件型多余 swap
AVAIL_PCT=$(( AVAIL_KB*100 / TOTAL_KB ))
if [[ -n "$ACTIVE_LIST" ]]; then
  # 列出除 KEEP_PATH 外的其它 swap
  OTHERS=$(echo "$ACTIVE_LIST" | awk -v keep="$KEEP_PATH" '{if($1!=keep)print $1}')
  if [[ -n "$OTHERS" ]]; then
    if (( AVAIL_PCT >= 40 )); then
      while read -r dev; do
        [[ -z "$dev" ]] && continue
        if [[ "$dev" == /dev/zram* ]]; then
          # 不强关 zram（稳定为先）
          warn "保留额外 zram：$dev（未强制关闭）"
        else
          # 安全关闭并删除文件型 swap
          swapoff "$dev" 2>/dev/null || true
          rm -f "$dev"   2>/dev/null || true
          ok "已关闭并移除多余 swap：$dev"
        fi
      done <<< "$OTHERS"
    else
      warn "可用内存不足（${AVAIL_PCT}%），暂不关闭多余 swap（已在 fstab 去重，重启后只保留 1 个）"
    fi
  fi
fi

# ============ TRIM =========== #
ttl "磁盘优化（TRIM）"
if command -v fstrim >/dev/null 2>&1; then
  NI "fstrim -av >/dev/null 2>&1 || true"
  ok "TRIM 完成"
else
  warn "未检测到 fstrim"
fi

# ============ 状态（后）=========== #
ttl "系统概况（清理后）"
log "磁盘（/）："; df -h / | sed 's/^/  /'
log "内存：";      free -h  | sed 's/^/  /'
log "Swap：";     (swapon --show || true) | sed 's/^/  /' || true
ok "深度清理完成 🎉"

# ============ 定时任务 =========== #
ttl "计划任务"
chmod +x /root/deep-clean.sh
( crontab -u root -l 2>/dev/null | grep -v 'deep-clean.sh' || true; echo "0 3 * * * /bin/bash /root/deep-clean.sh >/dev/null 2>&1" ) | crontab -u root -
ok "已设置每日 03:00 自动清理（03:00）"
EOF

chmod +x "$SCRIPT_PATH"
bash "$SCRIPT_PATH"
