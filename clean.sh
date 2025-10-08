#!/usr/bin/env bash
# =========================================================
# 🔥 Nuro Deep Clean Final (自动写入覆盖 + 深度清理CPU/内存/硬盘)
# 作者: hiapb + ChatGPT
# 功能: 自动写入自身、彻底清理系统(保留1天日志)、重建swap、释放缓存
# 计划任务: 每天凌晨3点自动执行
# =========================================================

set -e
SCRIPT_PATH="/root/deep-clean.sh"

echo "📝 正在写入脚本到 $SCRIPT_PATH ..."
cat > "$SCRIPT_PATH" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

echo -e "\n🧹 [Deep Clean Final] 开始深度清理...\n"

# -----------------------
# 1. 系统信息
# -----------------------
uname -a
echo "磁盘占用前："
df -h /
echo "内存使用前："
free -h
echo "--------------------------------------"

# -----------------------
# 2. 结束残留进程
# -----------------------
echo "结束残留 apt/dpkg/后台任务..."
pkill -9 -f 'apt|dpkg|unattended-upgrade' 2>/dev/null || true
rm -f /var/lib/dpkg/lock* /var/cache/apt/archives/lock || true
dpkg --configure -a >/dev/null 2>&1 || true

# -----------------------
# 3. 清理日志 (保留1天)
# -----------------------
echo "清理系统日志..."
journalctl --rotate || true
journalctl --vacuum-time=1d || true
journalctl --vacuum-size=200M || true
find /var/log -type f -mtime +1 -exec truncate -s 0 {} \; 2>/dev/null || true
: > /var/log/wtmp || true
: > /var/log/btmp || true
: > /var/log/lastlog || true
: > /var/log/faillog || true

# -----------------------
# 4. 清理临时文件
# -----------------------
echo "清理 /tmp /var/tmp ..."
find /tmp -type f -atime +1 -delete 2>/dev/null || true
find /var/tmp -type f -atime +1 -delete 2>/dev/null || true
find /tmp -type f -size +50M -delete 2>/dev/null || true
find /var/tmp -type f -size +50M -delete 2>/dev/null || true

# -----------------------
# 5. 清理 APT 缓存
# -----------------------
echo "清理 APT 缓存..."
apt-get -y autoremove >/dev/null 2>&1 || true
apt-get -y autoclean >/dev/null 2>&1 || true
apt-get -y clean >/dev/null 2>&1 || true
dpkg -l | awk '/^rc/{print $2}' | xargs -r dpkg -P >/dev/null 2>&1 || true

# -----------------------
# 6. 用户与构建缓存
# -----------------------
echo "清理用户缓存..."
rm -rf /root/.cache/* 2>/dev/null || true
for user in /home/*; do
  [ -d "$user/.cache" ] && rm -rf "$user/.cache/"* 2>/dev/null || true
done
command -v pip >/dev/null && pip cache purge || true
command -v npm >/dev/null && npm cache clean --force || true
command -v yarn >/dev/null && yarn cache clean || true

# -----------------------
# 7. Snap / Docker / 容器清理
# -----------------------
if command -v snap >/dev/null; then
  echo "清理 snap 旧版本..."
  snap list --all | awk '/disabled/{print $1, $3}' | xargs -r -n2 snap remove || true
fi

if command -v docker >/dev/null; then
  echo "清理 Docker..."
  docker system prune -af --volumes >/dev/null 2>&1 || true
  docker builder prune -af >/dev/null 2>&1 || true
  docker volume prune -f >/dev/null 2>&1 || true
fi

# -----------------------
# 8. 清理大文件与备份
# -----------------------
echo "清理备份、下载、大文件..."
rm -rf /www/server/backup/* /root/Downloads/* /home/*/Downloads/* 2>/dev/null || true
find / -type f \( -name "*.zip" -o -name "*.tar.gz" -o -name "*.bak" \) \
  -size +100M \
  -not -path "/www/server/panel/*" \
  -not -path "/www/wwwlogs/*" \
  -not -path "/var/lib/mysql/*" \
  -delete 2>/dev/null || true

# -----------------------
# 9. 清理旧内核
# -----------------------
echo "清理旧内核..."
CURRENT_KERNEL=$(uname -r)
dpkg -l | grep linux-image | awk '{print $2}' | grep -v "$CURRENT_KERNEL" | xargs -r apt-get -y purge >/dev/null 2>&1 || true

# -----------------------
# 10. 释放内存缓存 & 重建 swap
# -----------------------
echo "释放内存缓存..."
sync
echo 3 > /proc/sys/vm/drop_caches || true
[ -w /proc/sys/vm/compact_memory ] && echo 1 > /proc/sys/vm/compact_memory || true
if grep -q ' swap ' /proc/swaps 2>/dev/null; then
  echo "重建 swap..."
  swapoff -a || true
  swapon -a || true
fi

# -----------------------
# 11. 定时任务
# -----------------------
echo "设置每日 03:00 定时清理..."
CRON="0 3 * * * /bin/bash /root/deep-clean.sh >/dev/null 2>&1"
chmod +x /root/deep-clean.sh
( crontab -u root -l 2>/dev/null | grep -v 'deep-clean.sh' || true; echo "$CRON" ) | crontab -u root -

# -----------------------
# 12. 总结
# -----------------------
echo -e "\n✅ 深度清理完成！"
echo "磁盘占用后："
df -h /
echo "内存使用后："
free -h
echo "🕒 已加入每日自动清理任务 (03:00)"
EOF

chmod +x "$SCRIPT_PATH"
bash "$SCRIPT_PATH"
