#!/usr/bin/env bash
# =========================================================
# Deep Clean Script (自动深度清理)
# 作者: hiapb
# 功能: 深度清理 + 自动定时任务 (每天凌晨3点执行)
# =========================================================

set -e

echo -e "\n🧹 [Nuro Deep Clean] 开始深度清理...\n"

# ========================
# 1. 检查系统信息
# ========================
echo "系统信息："
uname -a
echo "磁盘占用前："
df -h /
echo "内存使用前："
free -h
echo "--------------------------------------"

# ========================
# 2. 清理 apt 缓存和依赖
# ========================
echo "清理 APT 缓存与依赖..."
apt-get autoremove -y >/dev/null 2>&1 || true
apt-get autoclean -y >/dev/null 2>&1 || true
apt-get clean -y >/dev/null 2>&1 || true

# ========================
# 3. 清理日志文件
# ========================
echo "清理日志文件（仅保留7天内）..."
journalctl --vacuum-time=7d >/dev/null 2>&1 || true
find /var/log -type f -name "*.log" -mtime +7 -exec truncate -s 0 {} \; 2>/dev/null || true

# ========================
# 4. 清理临时文件
# ========================
echo "清理临时目录..."
rm -rf /tmp/* /var/tmp/* 2>/dev/null || true

# ========================
# 5. 清理缓存目录
# ========================
echo "清理用户缓存..."
rm -rf /root/.cache/* 2>/dev/null || true
for user in /home/*; do
  [ -d "$user" ] && rm -rf "$user/.cache/"* 2>/dev/null || true
done

# ========================
# 6. 清理 Docker 镜像与容器（如存在）
# ========================
if command -v docker >/dev/null 2>&1; then
  echo "检测到 Docker，正在清理无用镜像/容器..."
  docker system prune -af --volumes >/dev/null 2>&1 || true
fi

# ========================
# 7. 删除旧内核（仅保留当前运行版本）
# ========================
echo "清理旧内核..."
CURRENT_KERNEL=$(uname -r)
dpkg -l | grep linux-image | awk '{print $2}' | grep -v "$CURRENT_KERNEL" | xargs apt-get -y purge >/dev/null 2>&1 || true

# ========================
# 8. 清理 swap 缓存
# ========================
echo "刷新 swap 缓存..."
swapoff -a && swapon -a || true

# ========================
# 9. 清理孤立包
# ========================
echo "清理孤立包..."
if command -v deborphan >/dev/null 2>&1; then
  deborphan 2>/dev/null | xargs apt-get -y remove --purge >/dev/null 2>&1 || true
fi

# ========================
# 10. 自动设置定时任务（每天凌晨3点）
# ========================
echo "设置自动清理任务（每天凌晨 3 点执行）..."
CRON_JOB="0 3 * * * bash /root/deep-clean.sh >/dev/null 2>&1"
( crontab -l 2>/dev/null | grep -v 'deep-clean.sh' ; echo "$CRON_JOB" ) | crontab -

# ========================
# 11. 完成
# ========================
echo -e "\n✅ 深度清理完成！"
echo "磁盘占用后："
df -h /
echo "内存使用后："
free -h
echo -e "\n🕒 自动清理任务已添加至 crontab，每天凌晨 3 点执行。"
echo -e "如需查看任务，可运行：crontab -l"
