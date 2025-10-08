#!/usr/bin/env bash
# =========================================================
# Nuro Deep Clean Script (宝塔安全版)
# 作者: hiapb
# 功能: 深度清理 + 日志保留1天 + 自动写入自身（每次覆盖） + 每日3点cron
# =========================================================

set -e
SCRIPT_PATH="/root/deep-clean.sh"

# ========================
# 0. 写入自身（每次覆盖）
# ========================
echo "📝 写入脚本到 $SCRIPT_PATH ..."
cat > "$SCRIPT_PATH" <<'EOF'
#!/usr/bin/env bash
set -e
echo -e "\n🧹 [Nuro Deep Clean] 开始深度清理...\n"

# 1. 系统信息
echo "系统信息："
uname -a
echo "磁盘占用前："
df -h /
echo "内存使用前："
free -h
echo "--------------------------------------"

# 2. 清理系统日志（排除宝塔面板和网站日志，保留1天）
echo "清理系统日志..."
find /var/log -type f -name "*.log" \
  ! -path "/www/server/panel/logs/*" \
  ! -path "/www/wwwlogs/*" \
  -mtime +1 -exec truncate -s 0 {} \; 2>/dev/null || true

journalctl --rotate
journalctl --vacuum-time=1d >/dev/null 2>&1 || true
rm -rf /var/log/journal/* 2>/dev/null || true

# 清理登录记录
truncate -s 0 /var/log/wtmp 2>/dev/null || true
truncate -s 0 /var/log/btmp 2>/dev/null || true
truncate -s 0 /var/log/lastlog 2>/dev/null || true
truncate -s 0 /var/log/faillog 2>/dev/null || true

# 3. 清理 apt 缓存
echo "清理 APT 缓存..."
apt-get autoremove -y >/dev/null 2>&1 || true
apt-get autoclean -y >/dev/null 2>&1 || true
apt-get clean -y >/dev/null 2>&1 || true

# 4. 清理临时文件（仅删除超过1天未访问文件）
echo "清理 /tmp 和 /var/tmp ..."
find /tmp -type f -atime +1 -delete 2>/dev/null || true
find /var/tmp -type f -atime +1 -delete 2>/dev/null || true

# 5. 清理用户缓存
echo "清理用户缓存..."
rm -rf /root/.cache/* 2>/dev/null || true
for user in /home/*; do
  [ -d "$user" ] && rm -rf "$user/.cache/"* 2>/dev/null || true
done

# 6. 清理 Docker 镜像与容器（仅存在的）
if command -v docker >/dev/null 2>&1; then
  echo "清理 Docker 无用镜像/容器..."
  docker system prune -af --volumes --filter "until=168h" >/dev/null 2>&1 || true
fi

# 7. 删除旧内核（仅保留当前运行版本）
echo "清理旧内核..."
CURRENT_KERNEL=$(uname -r)
dpkg -l | grep linux-image | awk '{print $2}' | grep -v "$CURRENT_KERNEL" | xargs apt-get -y purge >/dev/null 2>&1 || true

# 8. 清理孤立包
echo "清理孤立包..."
if command -v deborphan >/dev/null 2>&1; then
  deborphan 2>/dev/null | xargs apt-get -y remove --purge >/dev/null 2>&1 || true
fi

# 9. 释放内存缓存
sync
echo 3 > /proc/sys/vm/drop_caches

# 10. 设置每日凌晨3点自动定时任务（只添加一次）
CRON_JOB="0 3 * * * /bin/bash /root/deep-clean.sh >/dev/null 2>&1"
(crontab -u root -l 2>/dev/null | grep -v 'deep-clean.sh' || true; echo "$CRON_JOB") | crontab -u root -

# 11. 完成
echo -e "\n✅ 深度清理完成！"
echo "磁盘占用后："
df -h /
echo "内存使用后："
free -h
echo -e "\n🕒 自动清理任务已添加至 root crontab，每天凌晨3点执行"
EOF

chmod +x "$SCRIPT_PATH"

# ========================
# 执行一次清理（安全模式）
# ========================
echo "🛡️ 执行深度清理..."
bash "$SCRIPT_PATH"
