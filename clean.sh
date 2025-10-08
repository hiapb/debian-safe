#!/usr/bin/env bash
# =========================================================
# Nuro Deep Clean Script (极致清理)
# 作者: hiapb
# 功能: 深度清理 + 日志保留1天 + 自动写入自身 + 每日3点cron
# =========================================================

set -e

SCRIPT_PATH="/root/deep-clean.sh"

# ========================
# 0. 自动写入自身
# ========================
if [ ! -f "$SCRIPT_PATH" ]; then
    echo "📝 将脚本写入 $SCRIPT_PATH ..."
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

# 2. 清理 apt 缓存和依赖
echo "清理 APT 缓存与依赖..."
for i in {1..2}; do
    apt-get autoremove -y >/dev/null 2>&1 || true
    apt-get autoclean -y >/dev/null 2>&1 || true
    apt-get clean -y >/dev/null 2>&1 || true
done

# 3. 清理日志文件 (仅保留1天)
echo "清理日志文件（仅保留1天）..."
journalctl --vacuum-time=1d >/dev/null 2>&1 || true
find /var/log -type f -name "*.log" -mtime +1 -exec truncate -s 0 {} \; 2>/dev/null || true

# 4. 清理临时文件
echo "清理临时目录..."
rm -rf /tmp/* /var/tmp/* 2>/dev/null || true

# 5. 清理用户缓存
echo "清理用户缓存..."
rm -rf /root/.cache/* 2>/dev/null || true
for user in /home/*; do
  [ -d "$user" ] && rm -rf "$user/.cache/"* 2>/dev/null || true
done

# 6. 清理 Docker 镜像与容器
if command -v docker >/dev/null 2>&1; then
  echo "检测到 Docker，正在清理无用镜像/容器..."
  docker system prune -af --volumes --filter "until=168h" >/dev/null 2>&1 || true
fi

# 7. 删除旧内核（仅保留当前运行版本）
echo "清理旧内核..."
CURRENT_KERNEL=$(uname -r)
dpkg -l | grep linux-image | awk '{print $2}' | grep -v "$CURRENT_KERNEL" | xargs apt-get -y purge >/dev/null 2>&1 || true

# 8. 清理 swap 缓存
echo "刷新 swap 缓存..."
swapoff -a
swapon -a

# 9. 清理孤立包
echo "清理孤立包..."
if command -v deborphan >/dev/null 2>&1; then
  deborphan 2>/dev/null | xargs apt-get -y remove --purge >/dev/null 2>&1 || true
fi

# 10. 清理大文件（超过50M）
echo "清理大文件..."
find /var/cache/apt/archives -type f -size +50M -exec rm -f {} \; 2>/dev/null || true
find /home/*/Downloads -type f -size +100M -exec rm -f {} \; 2>/dev/null || true
find /backup -type f -mtime +7 -exec rm -f {} \; 2>/dev/null || true

# 11. 清理 snap / flatpak 缓存
if command -v snap >/dev/null 2>&1; then
    echo "清理 Snap 缓存..."
    rm -rf /var/cache/snapd/* 2>/dev/null || true
fi
if command -v flatpak >/dev/null 2>&1; then
    echo "清理 Flatpak 缓存..."
    flatpak uninstall --unused -y >/dev/null 2>&1 || true
fi

# 12. 释放内存缓存
sync
echo 1 > /proc/sys/vm/drop_caches
echo 2 > /proc/sys/vm/drop_caches
echo 3 > /proc/sys/vm/drop_caches

# 13. 设置自动定时任务
echo "设置每日凌晨3点自动清理任务..."
CRON_JOB="0 3 * * * /bin/bash /root/deep-clean.sh >/dev/null 2>&1"
chmod +x /root/deep-clean.sh
(crontab -u root -l 2>/dev/null | grep -v 'deep-clean.sh' || true; echo "$CRON_JOB") | crontab -u root -

# 14. 完成
echo -e "\n✅ 深度清理完成！"
echo "磁盘占用后："
df -h /
echo "内存使用后："
free -h
echo -e "\n🕒 自动清理任务已添加至 root crontab，每天凌晨3点执行"
EOF

    chmod +x "$SCRIPT_PATH"
fi

# ========================
# 执行一次深度清理
# ========================
bash "$SCRIPT_PATH"
