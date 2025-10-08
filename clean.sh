#!/usr/bin/env bash
# ======================================================================
# 🚀 Nuro Deep Clean • Safe-Deep+++ (Swap 三段式容错：/swapfile -> /swapfile-TS -> zram)
# 深度清理 + 智能/稳健 Swap + BT/站点/DB/PHP 强保护 + 美观输出
# ======================================================================

set -e
SCRIPT_PATH="/root/deep-clean.sh"
echo "📝 写入/覆盖 $SCRIPT_PATH ..."

cat > "$SCRIPT_PATH" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

# ======= 彩色输出 =======
C_RESET="\033[0m"; C_B="\033[1m"; C_BLUE="\033[38;5;33m"; C_GREEN="\033[38;5;40m"; C_YELLOW="\033[38;5;178m"; C_RED="\033[38;5;196m"; C_CYAN="\033[36m"; C_GRAY="\033[90m"
hr(){ printf "${C_GRAY}%s${C_RESET}\n" "────────────────────────────────────────────────────────"; }
title(){ printf "\n${C_B}${C_BLUE}[%s]${C_RESET} %s\n" "$1" "$2"; hr; }
ok(){ printf "${C_GREEN}✔${C_RESET} %s\n" "$*"; }
warn(){ printf "${C_YELLOW}⚠${C_RESET} %s\n" "$*"; }
err(){ printf "${C_RED}✘${C_RESET} %s\n" "$*"; }
log(){ printf "${C_CYAN}•${C_RESET} %s\n" "$*"; }
trap 'err "出错：行 $LINENO"; exit 1' ERR

# ======= 强保护：绝不触碰（BT/站点/DB/PHP） =======
EXCLUDES=(
  "/www/server/panel" "/www/wwwlogs" "/www/wwwroot"
  "/www/server/nginx" "/www/server/apache" "/www/server/openresty"
  "/www/server/mysql" "/var/lib/mysql" "/var/lib/mariadb" "/var/lib/postgresql"
  "/www/server/php" "/etc/php" "/var/lib/php/sessions"
)
is_excluded(){ local p="$1"; for e in "${EXCLUDES[@]}"; do [[ "$p" == "$e"* ]] && return 0; done; return 1; }

# ======= 概况 =======
title "系统概况" "采集中"
uname -a | sed 's/^/  /'
log "磁盘占用（根分区）："; df -h / | sed 's/^/  /'
log "内存占用："; free -h | sed 's/^/  /'
ok "概况完成"

# ======= APT 锁 =======
title "进程与锁" "只处理 apt/dpkg"
pkill -9 -f 'apt|apt-get|dpkg|unattended-upgrade' 2>/dev/null || true
rm -f /var/lib/dpkg/lock* /var/cache/apt/archives/lock || true
dpkg --configure -a >/dev/null 2>&1 || true
ok "apt/dpkg 锁处理完成"

# ======= 日志（保留 1 天，保结构） =======
title "日志清理" "journal + 常规日志"
journalctl --rotate || true
journalctl --vacuum-time=1d --vacuum-size=64M >/dev/null 2>&1 || true
find /var/log -type f -not -path "/www/server/panel/logs/*" -not -path "/www/wwwlogs/*" -exec truncate -s 0 {} \; 2>/dev/null || true
: > /var/log/wtmp || true; : > /var/log/btmp || true; : > /var/log/lastlog || true; : > /var/log/faillog || true
ok "日志清理完成"

# ======= 临时/缓存 =======
title "临时与缓存" "/tmp /var/tmp /var/cache（排除 PHP 会话等）"
find /tmp -xdev -type f -atime +1 -not -name 'sess_*' -delete 2>/dev/null || true
find /var/tmp -xdev -type f -atime +1 -delete 2>/dev/null || true
find /tmp -xdev -type f -size +50M -not -name 'sess_*' -delete 2>/dev/null || true
find /var/tmp -xdev -type f -size +50M -delete 2>/dev/null || true
find /var/cache -xdev -type f -mtime +1 -delete 2>/dev/null || true
rm -rf /var/crash/* /var/lib/systemd/coredump/* 2>/dev/null || true
ok "临时/缓存清理完成"

# ======= 包管理缓存 =======
title "包管理缓存" "APT / Snap / 语言包"
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

# ======= 容器清理 =======
title "容器清理" "Docker 构建缓存/镜像/卷/网络"
if command -v docker >/dev/null 2>&1; then
  docker builder prune -af >/dev/null 2>&1 || true
  docker image prune   -af --filter 'until=168h' >/dev/null 2>&1 || true
  docker container prune -f --filter 'until=24h' >/dev/null 2>&1 || true
  docker volume prune -f >/dev/null 2>&1 || true
  docker network prune -f >/dev/null 2>&1 || true
  docker system prune -af --volumes >/dev/null 2>&1 || true
fi
command -v ctr >/dev/null 2>&1 && ctr -n k8s.io images prune >/dev/null 2>&1 || true
ok "容器清理完成"

# ======= 备份 & 用户 Downloads —— 全量删除 =======
title "备份与用户下载" "不限大小，全部清空（保护站点/DB/PHP）"
[[ -d /www/server/backup ]] && rm -rf /www/server/backup/* 2>/dev/null || true
[[ -d /root/Downloads    ]] && rm -rf /root/Downloads/* 2>/dev/null || true
for d in /home/*/Downloads; do [[ -d "$d" ]] && rm -rf "$d"/* 2>/dev/null || true; done
for base in /root /home/*; do
  [[ -d "$base" ]] || continue
  find "$base" -type f \( -name "*.zip" -o -name "*.tar.gz" -o -name "*.tgz" -o -name "*.rar" -o -name "*.7z" -o -name "*.bak" \) -print0 2>/dev/null \
  | xargs -0r rm -f 2>/dev/null || true
done
ok "备份 & 用户下载清空完成"

# ======= 大文件补充（安全路径 >100MB） =======
title "大文件补充清理" "安全路径 >100MB"
SAFE_BASES=(/tmp /var/tmp /var/cache /var/backups /root /home /www/server/backup)
for base in "${SAFE_BASES[@]}"; do
  [[ -d "$base" ]] || continue
  while IFS= read -r -d '' f; do is_excluded "$f" && continue; rm -f "$f" 2>/dev/null || true; done \
  < <(find "$base" -xdev -type f -size +100M -print0 2>/dev/null)
done
ok "大文件补充清理完成"

# ======= 旧内核（保留当前+最新） =======
title "旧内核清理" "仅移除非当前且非最新"
if command -v dpkg >/dev/null 2>&1; then
  CURK="$(uname -r)"
  mapfile -t KS < <(dpkg -l | awk '/linux-image-[0-9]/{print $2}' | sort -V)
  KEEP=("linux-image-${CURK}")
  LATEST="$(printf "%s\n" "${KS[@]}" | grep -v "$CURK" | tail -n1 || true)"
  [[ -n "${LATEST:-}" ]] && KEEP+=("$LATEST")
  PURGE=(); for k in "${KS[@]}"; do [[ " ${KEEP[*]} " == *" $k "* ]] || PURGE+=("$k"); done
  ((${#PURGE[@]})) && apt-get -y purge "${PURGE[@]}" >/dev/null 2>&1 || true
fi
ok "内核清理完成"

# ======= 内存/CPU 深度优化 =======
title "内存/CPU 优化" "drop_caches + compact_memory"
sync; echo 3 > /proc/sys/vm/drop_caches || true
[[ -w /proc/sys/vm/compact_memory ]] && echo 1 > /proc/sys/vm/compact_memory || true
ok "内存释放完成"

# ======= ★ Swap 三段式容错：/swapfile -> /swapfile-TS -> zram =======
title "Swap 优化" "自动选择最稳路径（文件 busy 直接绕过）"

calc_target_mib(){ # half RAM, [256, 2048], keep >=25% disk free
  local mem_mib avail_mib target maxsafe
  mem_mib=$(awk '/MemTotal/ {printf "%.0f",$2/1024}' /proc/meminfo)
  target=$(( mem_mib / 2 ))
  (( target < 256 ))  && target=256
  (( target > 2048 )) && target=2048
  avail_mib=$(df -Pm / | awk 'NR==2{print $4}')
  maxsafe=$(( avail_mib * 75 / 100 ))
  (( target > maxsafe )) && target=$maxsafe
  echo "$target"
}

disable_swapfile_unit(){ systemctl disable --now swapfile.swap >/dev/null 2>&1 || true; }

mk_swap_file(){
  local path="$1" size="$2"
  local root_fs; root_fs=$(stat -f -c %T / 2>/dev/null || echo "")
  [[ "$root_fs" == "btrfs" ]] && { touch "$path"; chattr +C "$path" 2>/dev/null || true; }
  if ! fallocate -l "${size}M" "$path" 2>/dev/null; then
    dd if=/dev/zero of="$path" bs=1M count="${size}" status=none conv=fsync
  fi
  chmod 600 "$path"
  mkswap "$path" >/dev/null
  swapon "$path"
}

try_swapfile_primary(){ # /swapfile
  local target size; size="$(calc_target_mib)"
  [[ -z "$size" || "$size" -lt 128 ]] && return 1
  disable_swapfile_unit
  # 关现有
  swapoff /swapfile 2>/dev/null || true; swapoff -a 2>/dev/null || true
  fuser -km /swapfile 2>/dev/null || true
  chattr -i /swapfile 2>/dev/null || true
  rm -f /swapfile 2>/dev/null || true
  # 创建
  mk_swap_file "/swapfile" "$size"
  # fstab
  sed -i '\|/swapfile |d' /etc/fstab 2>/dev/null || true
  grep -q '^/swapfile ' /etc/fstab || echo "/swapfile none swap sw 0 0" >> /etc/fstab
  ok "已启用 /swapfile (${size}MiB)"
  return 0
}

try_swapfile_alt(){ # /swapfile-TS，避开 Text file busy
  local size ts path
  size="$(calc_target_mib)"; [[ -z "$size" || "$size" -lt 128 ]] && return 1
  ts="$(date +%s)"; path="/swapfile-${ts}"
  log "主路径忙/失败，改用 ${path}"
  mk_swap_file "$path" "$size"
  # fstab：移除旧的，写入新的
  sed -i '\|/swapfile |d' /etc/fstab 2>/dev/null || true
  echo "${path} none swap sw 0 0" >> /etc/fstab
  ok "已启用 ${path} (${size}MiB)"
  return 0
}

try_zram(){ # 兜底：内存压缩 swap（不落盘）
  modprobe zram 2>/dev/null || true
  [[ -e /sys/class/zram-control/hot_add ]] || { warn "zram 不可用"; return 1; }
  local id path size mem_mib
  id=$(cat /sys/class/zram-control/hot_add)
  path="/dev/zram${id}"
  mem_mib=$(awk '/MemTotal/ {printf "%.0f",$2/1024}' /proc/meminfo)
  size=$(( mem_mib * 3 / 4 )) # 取物理内存的 75%
  echo "${size}M" > "/sys/block/zram${id}/disksize"
  mkswap "$path" >/dev/null
  swapon -p 100 "$path"
  ok "已启用 zram swap (${size}MiB @ ${path})"
  return 0
}

if grep -q ' swap ' /proc/swaps 2>/dev/null; then
  log "已有 swap，重建刷新"
  swapoff -a || true; swapon -a || true; ok "Swap 重建完成"
else
  try_swapfile_primary || try_swapfile_alt || try_zram || warn "Swap 启用失败（磁盘/内核限制）"
fi

# ======= 磁盘 TRIM =======
title "磁盘优化" "fstrim（若可用）"
if command -v fstrim >/dev/null 2>&1; then fstrim -av >/dev/null 2>&1 || true; ok "fstrim 完成"; else warn "未检测到 fstrim"; fi

# ======= 汇总 & 定时 =======
title "完成汇总" "当前资源状态"
df -h / | sed 's/^/  /'; free -h | sed 's/^/  /'
ok "深度清理完成 🎉"
title "计划任务" "写入 crontab (每日 03:00)"
chmod +x /root/deep-clean.sh
( crontab -u root -l 2>/dev/null | grep -v 'deep-clean.sh' || true; echo "0 3 * * * /bin/bash /root/deep-clean.sh >/dev/null 2>&1" ) | crontab -u root -
ok "已设置每日 03:00 自动清理"
EOF

chmod +x "$SCRIPT_PATH"
bash "$SCRIPT_PATH"
