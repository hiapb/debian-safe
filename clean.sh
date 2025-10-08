#!/usr/bin/env bash
# ======================================================================
# 🚀 Nuro Deep Clean • Safe-Deep++ (修复swap占用 + 更深清理 + BT友好)
# ======================================================================

set -e
SCRIPT_PATH="/root/deep-clean.sh"

echo "📝 写入/覆盖 $SCRIPT_PATH ..."
cat > "$SCRIPT_PATH" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

# ======= 彩色输出 =======
C_RESET="\033[0m"; C_B="\033[1m"
C_BLUE="\033[38;5;33m"; C_GREEN="\033[38;5;40m"; C_YELLOW="\033[38;5;178m"; C_RED="\033[38;5;196m"; C_CYAN="\033[36m"; C_GRAY="\033[90m"
hr(){ printf "${C_GRAY}%s${C_RESET}\n" "────────────────────────────────────────────────────────"; }
title(){ printf "\n${C_B}${C_BLUE}[%s]${C_RESET} %s\n" "$1" "$2"; hr; }
ok(){ printf "${C_GREEN}✔${C_RESET} %s\n" "$*"; }
warn(){ printf "${C_YELLOW}⚠${C_RESET} %s\n" "$*"; }
err(){ printf "${C_RED}✘${C_RESET} %s\n" "$*"; }
log(){ printf "${C_CYAN}•${C_RESET} %s\n" "$*"; }

trap 'err "出错：行 $LINENO"; exit 1' ERR

# ======= 强保护：绝不触碰 =======
EXCLUDES=(
  "/www/server/panel" "/www/wwwlogs" "/www/wwwroot"
  "/www/server/nginx" "/www/server/apache" "/www/server/openresty"
  "/www/server/mysql" "/var/lib/mysql" "/var/lib/mariadb" "/var/lib/postgresql"
  "/www/server/php" "/etc/php" "/var/lib/php/sessions"
)

is_excluded(){ local p="$1"; for e in "${EXCLUDES[@]}"; do [[ "$p" == "$e"* ]] && return 0; done; return 1; }

# ======= 基本信息 =======
title "系统概况" "采集中"
uname -a | sed 's/^/  /'
log "磁盘占用（根分区）："; df -h / | sed 's/^/  /'
log "内存占用："; free -h | sed 's/^/  /'
ok "概况完成"

# ======= 进程与锁：仅APT相关 =======
title "进程与锁" "清理 apt/dpkg 残留锁"
pkill -9 -f 'apt|apt-get|dpkg|unattended-upgrade' 2>/dev/null || true
rm -f /var/lib/dpkg/lock* /var/cache/apt/archives/lock || true
dpkg --configure -a >/dev/null 2>&1 || true
ok "apt/dpkg 锁处理完成"

# ======= 日志：1天保留，结构保留 =======
title "日志清理" "journal + 常规日志"
journalctl --rotate || true
journalctl --vacuum-time=1d --vacuum-size=64M >/dev/null 2>&1 || true
# 常规日志截断（不删文件/权限）
find /var/log -type f \
  -not -path "/www/server/panel/logs/*" -not -path "/www/wwwlogs/*" \
  -exec truncate -s 0 {} \; 2>/dev/null || true
: > /var/log/wtmp  || true
: > /var/log/btmp  || true
: > /var/log/lastlog || true
: > /var/log/faillog || true
ok "日志清理完成"

# ======= 临时/缓存 =======
title "临时与缓存" "/tmp /var/tmp /var/cache（排除PHP会话等）"
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

# ======= 容器清理（不动业务卷绑定） =======
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

# ======= 大文件与备份 =======
title "大文件与备份" "安全路径 >100MB 清理 + 压缩包"
rm -rf /www/server/backup/* 2>/dev/null || true
rm -rf /root/Downloads/* /home/*/Downloads/* 2>/dev/null || true

SAFE_BASES=(/tmp /var/tmp /var/cache /var/backups /root /home /www/server/backup)
for base in "${SAFE_BASES[@]}"; do
  [[ -d "$base" ]] || continue
  while IFS= read -r -d '' f; do
    is_excluded "$f" && continue
    rm -f "$f" 2>/dev/null || true
  done < <(find "$base" -xdev -type f -size +100M -print0 2>/dev/null)
done
while IFS= read -r -d '' f; do
  is_excluded "$f" && continue
  rm -f "$f" 2>/dev/null || true
done < <(find / -xdev -type f \( -name '*.zip' -o -name '*.tar.gz' -o -name '*.tgz' -o -name '*.bak' \) -size +100M -print0 2>/dev/null)
ok "大文件与备份清理完成"

# ======= 内核（保留当前+最新） =======
title "旧内核清理" "仅移除非当前且非最新的"
if command -v dpkg >/dev/null 2>&1; then
  CURK="$(uname -r)"
  mapfile -t KS < <(dpkg -l | awk '/linux-image-[0-9]/{print $2}' | sort -V)
  KEEP=("linux-image-${CURK}")
  LATEST="$(printf "%s\n" "${KS[@]}" | grep -v "$CURK" | tail -n1 || true)"
  [[ -n "${LATEST:-}" ]] && KEEP+=("$LATEST")
  PURGE=()
  for k in "${KS[@]}"; do [[ " ${KEEP[*]} " == *" $k "* ]] || PURGE+=("$k"); done
  ((${#PURGE[@]})) && apt-get -y purge "${PURGE[@]}" >/dev/null 2>&1 || true
fi
ok "内核清理完成"

# ======= 内存/CPU 深度：释放缓存+紧凑 =======
title "内存/CPU 优化" "drop_caches + compact_memory"
sync
echo 3 > /proc/sys/vm/drop_caches || true
[[ -w /proc/sys/vm/compact_memory ]] && echo 1 > /proc/sys/vm/compact_memory || true
ok "内存释放完成"

# ======= 智能 Swap（修复 Text file busy） =======
title "Swap 优化" "智能容量 + 兼容 btrfs + 修复占用"
# 计算目标容量（物理内存一半，min 256MiB，max 2048MiB，且不吃光磁盘）
calc_target_mib(){
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

# 如果已有 /swapfile：优雅下线→解除占用→移除不可变→重建
prepare_swapfile_path(){
  if [[ -e /swapfile ]]; then
    log "检测到已有 /swapfile，尝试下线并替换..."
    # 如果在用，先下线
    grep -q '^/swapfile' /proc/swaps 2>/dev/null && swapoff /swapfile || true
    swapoff -a || true
    # 结束占用 /swapfile 的进程（极少见）
    command -v fuser >/dev/null 2>&1 && fuser -km /swapfile 2>/dev/null || true
    # 移除不可变属性（某些环境会被 chattr +i）
    command -v chattr >/dev/null 2>&1 && chattr -i /swapfile 2>/dev/null || true
    rm -f /swapfile || true
  fi
}

create_swapfile(){
  local target="$1"
  [[ -z "${target}" || "${target}" -lt 128 ]] && { warn "磁盘空间不足，放弃新建 swap"; return 0; }
  # btrfs 上需要关闭 COW
  local root_fs
  root_fs=$(stat -f -c %T / 2>/dev/null || echo "")
  if [[ "$root_fs" == "btrfs" ]]; then
    log "检测到 btrfs，关闭 COW 再创建 swapfile"
    touch /swapfile && chattr +C /swapfile 2>/dev/null || true
  fi
  # 先尝试 fallocate，失败再 dd
  if ! fallocate -l ${target}M /swapfile 2>/dev/null; then
    log "fallocate 失败，改用 dd"
    dd if=/dev/zero of=/swapfile bs=1M count=${target} status=none conv=fsync
  fi
  chmod 600 /swapfile
  mkswap /swapfile >/dev/null
  swapon /swapfile
  grep -q '^/swapfile' /etc/fstab || echo "/swapfile none swap sw 0 0" >> /etc/fstab
  ok "Swap 已创建/启用：${target}MiB"
}

if grep -q ' swap ' /proc/swaps 2>/dev/null; then
  log "已有 swap，执行重建以刷新"
  swapoff -a || true
  swapon -a  || true
  ok "Swap 重建完成"
else
  prepare_swapfile_path
  TARGET_MIB=$(calc_target_mib)
  if [[ -n "$TARGET_MIB" && "$TARGET_MIB" -ge 128 ]]; then
    create_swapfile "$TARGET_MIB"
  else
    warn "可用空间不足，未创建 swap"
  fi
fi

# ======= SSD TRIM =======
title "磁盘优化" "fstrim（若可用）"
if command -v fstrim >/dev/null 2>&1; then
  fstrim -av >/dev/null 2>&1 || true
  ok "fstrim 完成"
else
  warn "未检测到 fstrim"
fi

# ======= 汇总 =======
title "完成汇总" "当前资源状态"
df -h / | sed 's/^/  /'
free -h | sed 's/^/  /'
ok "深度清理全部完成 🎉"

# ======= 定时任务 =======
title "计划任务" "写入 crontab (每日 03:00)"
chmod +x /root/deep-clean.sh
( crontab -u root -l 2>/dev/null | grep -v 'deep-clean.sh' || true; echo "0 3 * * * /bin/bash /root/deep-clean.sh >/dev/null 2>&1" ) | crontab -u root -
ok "已设置每日 03:00 自动清理"
EOF

chmod +x "$SCRIPT_PATH"
bash "$SCRIPT_PATH"
