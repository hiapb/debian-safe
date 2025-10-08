#!/bin/bash
# Debian 安全深度清理脚本（适合运行中生产环境）
# 不会暂停服务，不会清除用户数据

echo "🧹 [安全深度清理开始] $(date)"
echo "------------------------------------"

# 0. 检查 root
if [ "$EUID" -ne 0 ]; then
  echo "❌ 请以 root 用户运行"
  exit 1
fi

# 1. 清理 apt 缓存和旧包
echo "🧩 清理 apt 缓存..."
apt-get clean -y >/dev/null 2>&1
apt-get autoclean -y >/dev/null 2>&1
apt-get autoremove -y --purge >/dev/null 2>&1

# 2. 清理日志文件（仅保留最近3天）
echo "🧾 清理系统日志..."
if command -v journalctl >/dev/null 2>&1; then
  journalctl --vacuum-time=3d >/dev/null 2>&1
fi
find /var/log -type f -name "*.log" -mtime +3 -delete 2>/dev/null
find /var/log -type f -size +50M -delete 2>/dev/null
find /var/log -type f -exec truncate -s 0 {} \; 2>/dev/null

# 3. 清理临时文件与缓存
echo "🧺 删除临时与缓存文件..."
rm -rf /tmp/* /var/tmp/* 2>/dev/null
rm -rf ~/.cache/* /root/.cache/* 2>/dev/null

# 4. 清理旧备份（仅删除 1 天前的）
echo "💾 清理旧备份文件（保留最近一天）..."
find / -type f \( -name "*.tar.gz" -o -name "*.zip" -o -name "*.bak" -o -name "*.sql" \) -mtime +1 -exec rm -f {} \; 2>/dev/null

# 5. 清理孤立包（不会影响当前服务）
echo "🧬 清理孤立依赖包..."
apt-get install -y deborphan >/dev/null 2>&1
deborphan | xargs apt-get -y remove --purge >/dev/null 2>&1 || true

# 6. 清理 Docker 缓存（不删除运行容器）
if command -v docker >/dev/null 2>&1; then
  echo "🐳 清理 Docker 缓存（安全模式）..."
  docker system prune -f --volumes >/dev/null 2>&1
fi

# 7. 清理 Python / npm 缓存（仅缓存）
if command -v pip >/dev/null 2>&1; then
  pip cache purge >/dev/null 2>&1
fi
if command -v npm >/dev/null 2>&1; then
  npm cache clean --force >/dev/null 2>&1
fi

# 8. 清理 core dump
rm -rf /var/crash/* /core* >/dev/null 2>&1

# 9. 释放系统缓存（安全）
echo "🧠 释放系统缓存..."
sync
echo 3 > /proc/sys/vm/drop_caches

# 10. 汇总结果
echo "------------------------------------"
echo "✅ 清理完成！系统状态如下："
df -h | grep -E '^/|Filesystem'
echo "------------------------------------"
free -h
echo "------------------------------------"
echo "✨ 已安全释放系统缓存与无用文件"
