#!/usr/bin/env bash
# ======================================================================
# 💥 Nuro Deep Clean · no-awk-braces (BT 友好 · 智能单一 Swap · 彩色输出)
# - 不使用 awk 的 { ... } 代码块（避免 "syntax error near {printf"）
# - 强制 /usr/bin/env bash 执行
# - 深度清理：日志(保1天)/tmp/var/tmp/var/cache/APT+Snap+语言包/Docker/旧内核
# - 备份 & 所有用户 Downloads：不限大小全清
# - Swap：只保留 1 个；无则智能新建（半内存，最小256/最大2048，留25%磁盘）
# - 不 swapoff，不杀 web/db/php；BT/站点/DB/PHP/session 强保护
# ======================================================================

set -e
SCRIPT_PATH="/root/deep-clean.sh"
echo "📝 正在写入/覆盖 $SCRIPT_PATH ..."

cat > "$SCRIPT_PATH" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

# ===== 彩色输出 =====
C0="\033[0m"; B="\033[1m"; BLU="\033[38;5;33m"; GRN="\033[38;5;40m"; YEL="\033[38;5;178m"; RED="\033[38;5;196m"; CYA="\033[36m"; GY="\033[90m"
hr(){ printf "${GY}%s${C0}\n" "────────────────────────────────────────────────────────"; }
ttl(){ printf "\n${B}${BLU}%s${C0}\n" "$1"; hr; }
ok(){  printf "${GRN}✔${C0} %s\n" "$*"; }
warn(){printf "${YEL}⚠${C0} %s\n" "$*"; }
err(){ printf "${RED}✘${C0} %s\n" "$*"; }
log(){ printf "${CYA}•${C0} %s\n" "$*"; }
trap 'err "出错：行 $LINENO"; exit 1' ERR

# ===== 强保护 =====
PROTECT=(
  "/www/server/panel" "/www/wwwlogs" "/www/wwwroot"
  "/www/server/nginx" "/www/server/apache" "/www/server/openresty"
  "/www/server/mysql" "/var/lib/mysql" "/var/lib/mariadb" "/var/lib/postgresql"
  "/www/server/php" "/etc/php" "/var/lib/php/sessions"
)
is_protect(){ local p="$1"; for e in "${PROTECT[@]}"; do [[ "$p" == "$e"* ]] && return 0; done; return 1; }

NI(){ nice -n 19 ionice -c3 bash -c "$*"; }

# ===== 状态（前）=====
ttl "系统概况（清理前）"
uname -a | sed 's/^/  /'
log "磁盘(/)："; df -h / | sed 's/^/  /'
log "内存：";     free -h | sed 's/^/  /'
log "Swap：";    (swapon --show || true) | sed 's/^/  /' || true

# ===== APT 锁 =====
ttl "进程与锁（仅 APT）"
pkill -9 -f 'apt|apt-get|dpkg|unattended-upgrade' 2>/dev/null || true
rm -f /var/lib/dpkg/lock* /var/cache/apt/archives/lock || true
dpkg --configure -a >/dev/null 2>&1 || true
ok "APT/dpkg 锁已清"

# ===== 日志（保1天）=====
ttl "日志清理（保留 1 天，保结构）"
journalctl --rotate || true
journalctl --vacuum-time=1d --vacuum-size=64M >/dev/null 2>&1 || true
NI "find /var/log -type f -not -path '/www/server/panel/logs/*' -not -path '/www/wwwlogs/*' -exec truncate -s 0 {} + 2>/dev/null || true"
: > /var/log/wtmp  || true
: > /var/log/btmp  || true
: > /var/log/lastlog || true
: > /var/log/faillog || true
ok "日志清理完成"

# ===== 临时/缓存 =====
ttl "临时与缓存（安全）"
NI "find /tmp -xdev -type f -atime +1 -not -name 'sess_*' -delete 2>/dev/null || true"
NI "find /var/tmp -xdev -type f -atime +1 -delete 2>/dev/null || true"
NI "find /tmp -xdev -type f -size +50M -not -name 'sess_*' -delete 2>/dev/null || true"
NI "find /var/tmp -xdev -type f -size +50M -delete 2>/dev/null || true"
NI "find /var/cache -xdev -type f -mtime +1 -delete 2>/dev/null || true"
rm -rf /var/crash/* /var/lib/systemd/coredump/* 2>/dev/null || true
ok "临时/缓存清理完成"

# ===== 包缓存 =====
ttl "包缓存（APT/Snap/语言包）"
if command -v apt-get >/dev/null 2>&1; then
  apt-get -y autoremove >/dev/null 2>&1 || true
  apt-get -y autoclean  >/dev/null 2>&1 || true
  apt-get -y clean      >/dev/null 2>&1 || true
  dpkg -l | grep -E '^rc\s' | tr -s ' ' | cut -d' ' -f2 | xargs -r dpkg -P >/dev/null 2>&1 || true
fi
if command -v snap >/dev/null 2>&1; then
  snap list --all | grep disabled | tr -s ' ' | cut -d' ' -f1,3 | xargs -r -n2 snap remove || true
fi
command -v pip >/dev/null      && pip cache purge >/dev/null 2>&1 || true
command -v npm >/dev/null      && npm cache clean --force >/dev/null 2>&1 || true
command -v yarn >/dev/null     && yarn cache clean >/dev/null 2>&1 || true
command -v composer >/dev/null && composer clear-cache >/dev/null 2>&1 || true
command -v gem >/dev/null      && gem cleanup -q >/dev/null 2>&1 || true
ok "包缓存清理完成"

# ===== 容器 =====
ttl "容器清理（Docker/containerd）"
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

# ===== 备份 & Downloads 全清 =====
ttl "备份 & 用户下载（不限大小，全清）"
[[ -d /www/server/backup ]] && NI "rm -rf /www/server/backup/* 2>/dev/null || true"
[[ -d /root/Downloads    ]] && NI "rm -rf /root/Downloads/* 2>/dev/null || true"
for d in /home/*/Downloads; do [[ -d "$d" ]] && NI "rm -rf '$d'/* 2>/dev/null || true"; done
# 家目录常见压缩/备份包
for base in /root /home/*; do
  [[ -d "$base" ]] || continue
  NI "find '$base' -type f \\( -name '*.zip' -o -name '*.tar.gz' -o -name '*.tgz' -o -name '*.rar' -o -name '*.7z' -o -name '*.bak' \\) -delete 2>/dev/null || true"
done
ok "备份 & 下载清空完成"

# ===== 旧内核（保当前+最新）=====
ttl "旧内核（保留当前+最新）"
if command -v dpkg-query >/dev/null 2>&1; then
  CURK="$(uname -r)"
  # 获取所有 linux-image 包名（不带 awk 代码块）
  mapfile -t KS < <(dpkg-query -W -f='${Package}\n' 'linux-image-*' 2>/dev/null | sort -V || true)
  KEEP=("linux-image-${CURK}")
  # 选一个最新的（不等于当前）
  LATEST="$(printf '%s\n' "${KS[@]}" | grep -v "linux-image-${CURK}" | tail -n1 || true)"
  [[ -n "${LATEST:-}" ]] && KEEP+=("$LATEST")
  # 生成 PURGE 列表
  PURGE=()
  for k in "${KS[@]}"; do
    [[ -z "$k" ]] && continue
    # 不清除 meta 包 (linux-image-amd64 等)，并保留 KEEP
    if [[ "$k" == linux-image-[0-9]* ]]; then
      keepflag=0
      for kk in "${KEEP[@]}"; do [[ "$k" == "$kk" ]] && keepflag=1; done
      (( keepflag == 0 )) && PURGE+=("$k")
    fi
  done
  if ((${#PURGE[@]})); then
    NI "apt-get -y purge ${PURGE[*]} >/dev/null 2>&1 || true"
    ok "已移除：${PURGE[*]}"
  else
    ok "无可移除旧内核"
  fi
fi

# ===== 内存/CPU（温和）=====
ttl "内存/CPU 优化（温和）"
LOAD1_INT="$(cut -d'.' -f1 /proc/loadavg)"
MEM_AVAIL_KB="$(grep -E '^MemAvailable:' /proc/meminfo | tr -s ' ' | cut -d' ' -f2)"
MEM_TOTAL_KB="$(grep -E '^MemTotal:'     /proc/meminfo | tr -s ' ' | cut -d' ' -f2)"
MEM_AVAIL_PCT=$(( MEM_AVAIL_KB*100 / MEM_TOTAL_KB ))
if (( LOAD1_INT <= 2 && MEM_AVAIL_PCT >= 30 )); then
  sync
  echo 1 > /proc/sys/vm/drop_caches || true
  [[ -w /proc/sys/vm/compact_memory ]] && echo 1 > /proc/sys/vm/compact_memory || true
  ok "回收完成（Load1=${LOAD1_INT}, 可用内存=${MEM_AVAIL_PCT}%）"
else
  warn "跳过（Load1=${LOAD1_INT}, 可用内存=${MEM_AVAIL_PCT}%）"
fi

# ===== Swap（智能单一；不 swapoff）=====
ttl "Swap 管理（只保留 1 个；无则新建；不 swapoff）"
has_swap(){ grep -q ' swap ' /proc/swaps 2>/dev/null; }
calc_target_mib(){ # half RAM, [256,2048], keep >=25% disk free —— 无 awk 代码块
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
mk_swap(){ # 创建并写入 fstab（只保留唯一条目）
  local path="$1" size="$2"
  [[ -z "$size" || "$size" -lt 128 ]] && { warn "磁盘不足，跳过新建 swap"; return 1; }
  local fs; fs=$(stat -f -c %T / 2>/dev/null || echo "")
  if [[ "$fs" == "btrfs" ]]; then touch "$path"; chattr +C "$path" 2>/dev/null || true; fi
  if ! fallocate -l ${size}M "$path" 2>/dev/null; then
    dd if=/dev/zero of="$path" bs=1M count=${size} status=none conv=fsync
  fi
  chmod 600 "$path"; mkswap "$path" >/dev/null; swapon "$path"
  # fstab 去重 + 写入
  sed -i '\|/swapfile-[0-9]\+|d' /etc/fstab 2>/dev/null || true
  sed -i '\|/swapfile |d'       /etc/fstab 2>/dev/null || true
  sed -i '\|/dev/zram|d'        /etc/fstab 2>/dev/null || true
  echo "$path none swap sw 0 0" >> /etc/fstab
  ok "已启用 swap：$path (${size}MiB)"
  return 0
}

# 1) 如果没有 swap，就新建（优先 /swapfile，busy 则 /swapfile-TS）
if ! has_swap; then
  SIZE="$(calc_target_mib)"
  if ! mk_swap "/swapfile" "$SIZE"; then
    TS="$(date +%s)"
    mk_swap "/swapfile-${TS}" "$SIZE" || warn "无法创建文件型 swap；考虑 zram"
  fi
else
  ok "已检测到 swap：不新建、不关闭（稳定优先）"
fi

# 2) fstab 去重（只保留 1 个；优先 zram，否则选优先级/容量最高的）
ACTIVE="$(swapon --show=NAME,PRIO,SIZE --bytes --noheadings 2>/dev/null || true)"
KEEP=""
if echo "$ACTIVE" | grep -q 'zram'; then
  KEEP="$(echo "$ACTIVE" | grep 'zram' | head -n1 | tr -s ' ' | cut -d' ' -f1)"
else
  # 选优先级高 & size 大：用 sort；避免 awk 代码块
  KEEP="$(printf '%s\n' "$ACTIVE" \
    | tr -s ' ' \
    | awk '{print $1" "$2" "$3}' \
    | sort -k2,2nr -k3,3nr \
    | head -n1 \
    | cut -d' ' -f1)"
fi
if [[ -f /etc/fstab ]]; then
  cp /etc/fstab /etc/fstab.bak.deepclean 2>/dev/null || true
  sed -i '\|/swapfile-[0-9]\+|d' /etc/fstab 2>/dev/null || true
  sed -i '\|/swapfile |d'       /etc/fstab 2>/dev/null || true
  sed -i '\|/dev/zram|d'        /etc/fstab 2>/dev/null || true
  [[ -n "$KEEP" ]] && echo "$KEEP none swap sw 0 0" >> /etc/fstab
  ok "fstab 已去重（只保留 1 个；备份：/etc/fstab.bak.deepclean）"
fi

# ===== TRIM =====
ttl "磁盘优化（TRIM）"
if command -v fstrim >/dev/null 2>&1; then NI "fstrim -av >/dev/null 2>&1 || true"; ok "TRIM 完成"; else warn "未检测到 fstrim"; fi

# ===== 状态（后）=====
ttl "系统概况（清理后）"
log "磁盘(/)："; df -h / | sed 's/^/  /'
log "内存：";     free -h | sed 's/^/  /'
log "Swap：";    (swapon --show || true) | sed 's/^/  /' || true
ok "深度清理完成 ✅"

# ===== 定时任务 =====
ttl "计划任务"
chmod +x /root/deep-clean.sh
( crontab -u root -l 2>/dev/null | grep -v 'deep-clean.sh' || true; echo "0 3 * * * /usr/bin/env bash /root/deep-clean.sh >/dev/null 2>&1" ) | crontab -u root -
ok "已设置每日 03:00 自动清理（03:00）"
EOF

chmod +x "$SCRIPT_PATH"
/usr/bin/env bash "$SCRIPT_PATH"
