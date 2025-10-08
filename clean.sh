#!/usr/bin/env bash
# ======================================================================
# 🌟 Nuro Deep Clean • Safe-Deep Final (BT友好 · 智能Swap · 美观输出)
# 目标：深度清理 CPU / 内存 / 硬盘，但严保宝塔/站点/数据库/PHP稳定
# 作者：hiapb + ChatGPT
# ======================================================================

set -e
SCRIPT_PATH="/root/deep-clean.sh"

echo "📝 正在写入/覆盖 $SCRIPT_PATH ..."
cat > "$SCRIPT_PATH" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

# ================== 美观输出/工具 ==================
C_RESET="\033[0m"; C_B="\033[1m"; C_DIM="\033[2m"
C_BLUE="\033[38;5;33m"; C_GREEN="\033[38;5;40m"; C_YELLOW="\033[38;5;178m"; C_RED="\033[38;5;196m"; C_CYAN="\033[36m"; C_GRAY="\033[90m"

hr(){ printf "${C_GRAY}%s${C_RESET}\n" "────────────────────────────────────────────────────────"; }
title(){ printf "\n${C_B}${C_BLUE}[%s]${C_RESET} %s\n" "$1" "$2"; hr; }
ok(){ printf "${C_GREEN}✔${C_RESET} %s\n" "$*"; }
warn(){ printf "${C_YELLOW}⚠${C_RESET} %s\n" "$*"; }
err(){ printf "${C_RED}✘${C_RESET} %s\n" "$*"; }
log(){ printf "${C_CYAN}•${C_RESET} %s\n" "$*"; }

trap 'err "出错：行 $LINENO"; exit 1' ERR

# ================== 强保护（绝对不能碰） ==================
# BaoTa & 站点 & 数据库 & PHP/session 等关键路径，全部排除
EXCLUDES=(
  "/www/server/panel"
  "/www/wwwlogs"
  "/www/wwwroot"
  "/www/server/nginx"
  "/www/server/apache"
  "/www/server/openresty"
  "/www/server/mysql" "/var/lib/mysql" "/var/lib/mariadb" "/var/lib/postgresql"
  "/www/server/php" "/etc/php" "/var/lib/php/sessions"
)
is_excluded(){ local p="$1"; for e in "${EXCLUDES[@]}"; do [[ "$p" == "$e"* ]] && return 0; done; return 1; }

# ================== 开始 ==================
printf "\n${C_B}${C_BLUE}💥 Nuro Deep Clean • Safe-Deep Final${C_RESET}\n"
hr

# 0) 系统概况
title "系统概况" "采集中"
uname -a | sed 's/^/  /'
log "磁盘占用（根分区）："
df -h / | sed 's/^/  /'
log "内存占用："
free -h | sed 's/^/  /'
ok "概况完成"

# 1) 解锁 apt/dpkg，仅限相关进程（不杀 web/db/php）
title "进程与锁" "清理 apt/dpkg 残留"
pkill -9 -f 'apt|apt-get|dpkg|unattended-upgrade' 2>/dev/null || true
rm -f /var/lib/dpkg/lock* /var/cache/apt/archives/lock || true
dpkg --configure -a >/dev/null 2>&1 || true
ok "apt/dpkg 锁处理完成"

# 2) 系统日志（深度、保1天、但不破 journald）
title "日志清理" "journal + 常规日志 深度清理"
journalctl --rotate || true
# 尽量强：时间+容量双阈（1天 & 64MB）；避免粗暴删除活跃目录
journalctl --vacuum-time=1d --vacuum-size=64M >/dev/null 2>&1 || true
# 常规日志全部截断（不删文件/权限/属主）
find /var/log -type f -not -path "/www/server/panel/logs/*" -not -path "/www/wwwlogs/*" -exec truncate -s 0 {} \; 2>/dev/null || true
: > /var/log/wtmp  || true
: > /var/log/btmp  || true
: > /var/log/lastlog || true
: > /var/log/faillog || true
ok "日志清理完成（保留结构，避免服务崩溃）"

# 3) 临时/缓存（谨慎，排除 PHP 会话/数据库/站点）
title "临时与缓存" "清理 /tmp /var/tmp /var/cache（安全排除）"
# 避开 PHP 会话目录
find /tmp -xdev -type f -atime +1 -not -name 'sess_*' -delete 2>/dev/null || true
find /var/tmp -xdev -type f -atime +1 -delete 2>/dev/null || true
# 大文件
find /tmp -xdev -type f -size +50M -not -name 'sess_*' -delete 2>/dev/null || true
find /var/tmp -xdev -type f -size +50M -delete 2>/dev/null || true
# /var/cache 仅清理普通缓存文件，不动 PHP 会话、数据库等
find /var/cache -xdev -type f -mtime +1 -delete 2>/dev/null || true
rm -rf /var/crash/* /var/lib/systemd/coredump/* 2>/dev/null || true
ok "临时/缓存清理完成"

# 4) APT / Snap / 语言包缓存
title "包管理缓存" "APT/Snap/语言包缓存"
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

# 5) Docker / containerd（不动运行中容器的卷数据绑定点）
title "容器清理" "Docker 构建缓存/镜像/卷（可回收项）"
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

# 6) 备份/下载/大文件（仅清理安全范围；强排除关键路径）
title "大文件与备份" ">100MB 文件清理（安全路径）"
# 定点目录先清
rm -rf /www/server/backup/* 2>/dev/null || true
rm -rf /root/Downloads/* /home/*/Downloads/* 2>/dev/null || true

# 安全路径扫描
SAFE_BASES=(/tmp /var/tmp /var/cache /var/backups /root /home /www/server/backup)
for base in "${SAFE_BASES[@]}"; do
  [[ -d "$base" ]] || continue
  while IFS= read -r -d '' f; do
    is_excluded "$f" && continue
    rm -f "$f" 2>/dev/null || true
  done < <(find "$base" -xdev -type f -size +100M -print0 2>/dev/null)
done

# 全盘压缩/备份包（排除关键路径）
while IFS= read -r -d '' f; do
  is_excluded "$f" && continue
  rm -f "$f" 2>/dev/null || true
done < <(find / -xdev -type f \( -name '*.zip' -o -name '*.tar.gz' -o -name '*.tgz' -o -name '*.bak' \) -size +100M -print0 2>/dev/null)

ok "大文件与备份清理完成"

# 7) 旧内核：保留“当前 + 最新”；不碰正在运行的
title "旧内核清理" "仅移除非当前且非最新的 kernel"
if command -v dpkg >/dev/null 2>&1; then
  CURK="$(uname -r)"
  mapfile -t KS < <(dpkg -l | awk '/linux-image-[0-9]/{print $2}' | sort -V)
  KEEP=("linux-image-${CURK}")
  LATEST="$(printf "%s\n" "${KS[@]}" | grep -v "$CURK" | tail -n1 || true)"
  [[ -n "${LATEST:-}" ]] && KEEP+=("$LATEST")
  PURGE=()
  for k in "${KS[@]}"; do [[ " ${KEEP[*]} " == *" $k "* ]] || PURGE+=("$k"); done
  if ((${#PURGE[@]})); then
    apt-get -y purge "${PURGE[@]}" >/dev/null 2>&1 || true
    ok "已移除: ${PURGE[*]}"
  else
    ok "无可移除旧内核"
  fi
else
  warn "非 dpkg 系统，跳过"
fi

# 8) 内存与 CPU：释放缓存 + 紧凑内存 + 智能 Swap
title "内存/CPU 优化" "drop_caches + compact + 智能 Swap"
sync
echo 3 > /proc/sys/vm/drop_caches || true
[[ -w /proc/sys/vm/compact_memory ]] && echo 1 > /proc/sys/vm/compact_memory || true

# 智能 Swap：无则创建≈物理内存一半（min 256MB, max 2048MB, 受磁盘空闲限制）
if ! grep -q ' swap ' /proc/swaps 2>/dev/null; then
  MEM_MB=$(awk '/MemTotal/ {printf "%.0f", $2/1024}' /proc/meminfo)    # MiB
  TARGET=$(( MEM_MB / 2 ))
  (( TARGET < 256 )) && TARGET=256
  (( TARGET > 2048 )) && TARGET=2048
  # 根分区可用空间（MiB）
  AVAIL_MB=$(df -Pm / | awk 'NR==2{print $4}')
  # 至少保留 25% 可用空间
  MAX_SAFE=$(( AVAIL_MB * 75 / 100 ))
  (( TARGET > MAX_SAFE )) && TARGET=$MAX_SAFE
  if (( TARGET >= 128 )); then
    log "创建 swapfile ${TARGET}MiB（依据内存与磁盘余量自适应）"
    fallocate -l ${TARGET}M /swapfile || dd if=/dev/zero of=/swapfile bs=1M count=$TARGET
    chmod 600 /swapfile
    mkswap /swapfile >/dev/null 2>&1 || true
    swapon /swapfile || true
    grep -q '^/swapfile' /etc/fstab || echo "/swapfile none swap sw 0 0" >> /etc/fstab
    ok "Swap 已创建并启用"
  else
    warn "磁盘空间过小，放弃创建 swap"
  fi
else
  log "检测到现有 swap：重建以刷新"
  swapoff -a || true
  swapon -a  || true
  ok "Swap 已重建"
fi

# 9) SSD TRIM（如可用）
title "磁盘优化" "SSD 空间回收（fstrim）"
if command -v fstrim >/dev/null 2>&1; then
  fstrim -av >/dev/null 2>&1 || true
  ok "fstrim 完成"
else
  warn "未检测到 fstrim，跳过"
fi

# 10) 汇总
title "完成汇总" "当前资源状态"
df -h / | sed 's/^/  /'
free -h | sed 's/^/  /'
ok "深度清理全部完成 🎉"

# 11) 定时任务（每天 03:00）
title "计划任务" "写入 crontab"
chmod +x /root/deep-clean.sh
( crontab -u root -l 2>/dev/null | grep -v 'deep-clean.sh' || true; echo "0 3 * * * /bin/bash /root/deep-clean.sh >/dev/null 2>&1" ) | crontab -u root -
ok "已设置每日 03:00 自动清理"
EOF

chmod +x "$SCRIPT_PATH"
bash "$SCRIPT_PATH"
