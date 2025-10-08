#!/usr/bin/env bash
# =========================================================
# 💣 Deep Clean Ultimate (智能 Swap + 深度清理 + 自动写入)
# 作者: ChatGPT 改进版 hiapb
# =========================================================

set -e
SCRIPT_PATH="/root/deep-clean.sh"

echo "📝 正在写入/覆盖脚本到 $SCRIPT_PATH ..."
cat > "$SCRIPT_PATH" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

echo -e "\n🔥 [Deep Clean Ultimate] 开始系统深度清理...\n"

log(){ echo "[$(date '+%F %T')] $*"; }

# -----------------------
# 0. 系统状态
# -----------------------
log "系统信息:"
uname -a
df -h /
free -h
echo "--------------------------------------"

# -----------------------
# 1. 清理锁 & 残留进程
# -----------------------
log "终止残留 apt/dpkg/升级进程..."
pkill -9 -f 'apt|dpkg|unattended-upgrade' 2>/dev/null || true
rm -f /var/lib/dpkg/lock* /var/cache/apt/archives/lock || true
dpkg --configure -a >/dev/null 2>&1 || true

# -----------------------
# 2. 清理日志
# -----------------------
log "强制清理系统日志..."
journalctl --rotate || true
# 如果没释放任何空间，也强制清空日志目录
journalctl --vacuum-time=1d --vacuum-size=50M >/dev/null 2>&1 || true
rm -rf /var/log/journal/* /run/log/journal/* 2>/dev/null || true
find /var/log -type f -exec truncate -s 0 {} \; 2>/dev/null || true
: > /var/log/wtmp || true
: > /var/log/btmp || true
: > /var/log/lastlog || true
: > /var/log/faillog || true

# -----------------------
# 3. 清理缓存目录
# -----------------------
log "清理 /tmp /var/tmp /var/cache..."
find /tmp /var/tmp /var/cache -type f -atime +1 -delete 2>/dev/null || true
find /tmp /var/tmp /var/cache -type f -size +50M -delete 2>/dev/null || true
rm -rf /var/backups/* /var/crash/* /var/lib/systemd/coredump/* 2>/dev/null || true

# -----------------------
# 4. APT & Snap 缓存
# -----------------------
if command -v apt-get >/dev/null 2>&1; then
  log "APT 缓存与孤包..."
  apt-get -y autoremove >/dev/null 2>&1 || true
  apt-get -y autoclean >/dev/null 2>&1 || true
  apt-get -y clean >/dev/null 2>&1 || true
  dpkg -l | awk '/^rc/{print $2}' | xargs -r dpkg -P >/dev/null 2>&1 || true
fi
if command -v snap >/dev/null 2>&1; then
  log "清理 snap 旧版本..."
  snap list --all | awk '/disabled/{print $1, $3}' | xargs -r -n2 snap remove || true
fi

# -----------------------
# 5. 用户与构建缓存
# -----------------------
log "清理用户缓存与构建产物..."
rm -rf /root/.cache/* 2>/dev/null || true
for user in /home/*; do
  [ -d "$user/.cache" ] && rm -rf "$user/.cache/"* 2>/dev/null || true
done
command -v pip >/dev/null && pip cache purge || true
command -v npm >/dev/null && npm cache clean --force || true
command -v yarn >/dev/null && yarn cache clean || true
command -v composer >/dev/null && composer clear-cache || true
command -v gem >/dev/null && gem cleanup -q || true

# -----------------------
# 6. Docker/容器 清理
# -----------------------
if command -v docker >/dev/null 2>&1; then
  log "清理 Docker 镜像/卷/缓存..."
  docker system prune -af --volumes >/dev/null 2>&1 || true
  docker builder prune -af >/dev/null 2>&1 || true
fi

# -----------------------
# 7. 删除大文件 / 备份
# -----------------------
log "删除备份/压缩包/大文件..."
rm -rf /www/server/backup/* /root/Downloads/* /home/*/Downloads/* 2>/dev/null || true
find / -xdev -type f \( -name '*.zip' -o -name '*.tar.gz' -o -name '*.bak' -o -name '*.tgz' \) \
  -size +100M \
  -not -path "/www/server/panel/*" \
  -not -path "/www/wwwlogs/*" \
  -not -path "/var/lib/mysql/*" \
  -delete 2>/dev/null || true

# -----------------------
# 8. 删除旧内核
# -----------------------
log "清理旧内核..."
CURRENT_KERNEL=$(uname -r)
dpkg -l | grep linux-image | awk '{print $2}' | grep -v "$CURRENT_KERNEL" | xargs -r apt-get -y purge >/dev/null 2>&1 || true

# -----------------------
# 9. 内存 + Swap 优化
# -----------------------
log "释放内存缓存与紧凑内存..."
sync
echo 3 > /proc/sys/vm/drop_caches || true
[ -w /proc/sys/vm/compact_memory ] && echo 1 > /proc/sys/vm/compact_memory || true

# 动态 swap：无则自动创建 ≈ 实体内存一半
if ! grep -q ' swap ' /proc/swaps 2>/dev/null; then
  log "未检测到 swap，自动创建..."
  MEM_MB=$(awk '/MemTotal/ {printf "%.0f", $2/2048}' /proc/meminfo)
  SIZE_MB=$(( MEM_MB > 256 ? MEM_MB : 256 ))
  log "创建 swapfile ${SIZE_MB}MB ..."
  fallocate -l ${SIZE_MB}M /swapfile || dd if=/dev/zero of=/swapfile bs=1M count=$SIZE_MB
  chmod 600 /swapfile
  mkswap /swapfile >/dev/null 2>&1 || true
  swapon /swapfile || true
  grep -q '^/swapfile' /etc/fstab || echo "/swapfile none swap sw 0 0" >> /etc/fstab
else
  log "已有 swap，执行重建..."
  swapoff -a || true
  swapon -a  || true
fi

# -----------------------
# 10. 磁盘优化
# -----------------------
if command -v fstrim >/dev/null 2>&1; then
  log "SSD 空间回收 (fstrim)..."
  fstrim -av >/dev/null 2>&1 || true
fi

# -----------------------
# 11. 完成报告
# -----------------------
log "✅ 清理完成"
df -h /
free -h

# -----------------------
# 12. 自动定时任务
# -----------------------
log "写入每日 03:00 定时任务..."
CRON="0 3 * * * /bin/bash /root/deep-clean.sh >/dev/null 2>&1"
chmod +x /root/deep-clean.sh
( crontab -u root -l 2>/dev/null | grep -v 'deep-clean.sh' || true; echo "$CRON" ) | crontab -u root -
log "✅ 已添加自动清理任务"
EOF

chmod +x "$SCRIPT_PATH"
bash "$SCRIPT_PATH"
