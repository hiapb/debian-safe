#!/usr/bin/env bash
# =========================================================
# Deep Clean - 极简狠版本 (保留1天 · 不玩变量)
# 适用: Debian/Ubuntu + 宝塔友好
# =========================================================
set -Eeuo pipefail
IFS=$'\n\t'

echo -e "\n🧹 [Deep Clean] START (keep=1 day)\n"

log(){ echo "[$(date '+%F %T')] $*"; }

# -------- 0) 系统信息 ----------
log "===== 清理前系统信息 ====="
uname -a
df -h /
free -h
echo "--------------------------------------"

# -------- 1) 终止占用/僵尸亲属进程，保障后续清理 ----------
log "结束残留 apt/dpkg/更新进程..."
pkill -9 -f 'apt|apt-get|unattended-upgrade|dpkg' 2>/dev/null || true
# 清锁（若无进程）
if ! pgrep -f 'apt|dpkg' >/dev/null; then
  rm -f /var/lib/dpkg/lock-frontend /var/lib/dpkg/lock /var/cache/apt/archives/lock || true
  dpkg --configure -a || true
fi

# -------- 2) 日志：只保留 1 天 ----------
log "清理系统日志（保留1天）..."
journalctl --rotate || true
journalctl --vacuum-time=1d || true
journalctl --vacuum-size=200M || true
# 置空登录类日志
: > /var/log/wtmp  || true
: > /var/log/btmp  || true
: > /var/log/lastlog || true
: > /var/log/faillog || true
# 常规 .log/.gz 只清理 >1天 + 排除宝塔/站点日志
find /var/log -type f \( -name '*.log' -o -name '*.old' -o -name '*.gz' -o -name '*.1' \) \
  -mtime +1 \
  -not -path "/www/server/panel/logs/*" \
  -not -path "/www/wwwlogs/*" \
  -exec truncate -s 0 {} + 2>/dev/null || true

# -------- 3) 临时目录 ----------
log "清理 /tmp /var/tmp （>1天未访问/大文件）..."
find /tmp -xdev -type f -atime +1 -delete 2>/dev/null || true
find /var/tmp -xdev -type f -atime +1 -delete 2>/dev/null || true
find /tmp -xdev -type f -size +100M -delete 2>/dev/null || true
find /var/tmp -xdev -type f -size +100M -delete 2>/dev/null || true
command -v systemd-tmpfiles >/dev/null 2>&1 && systemd-tmpfiles --clean || true

# -------- 4) APT 缓存/孤包/残配置 ----------
if command -v apt-get >/dev/null 2>&1; then
  log "APT 清理..."
  apt-get -y autoremove >/dev/null 2>&1 || true
  apt-get -y autoclean  >/dev/null 2>&1 || true
  apt-get -y clean      >/dev/null 2>&1 || true
  dpkg -l | awk '/^rc/{print $2}' | xargs -r dpkg -P >/dev/null 2>&1 || true
  rm -rf /var/cache/apt/archives/*.deb /var/cache/apt/archives/partial/* /var/lib/apt/lists/* 2>/dev/null || true
fi

# -------- 5) 用户/开发缓存 ----------
log "清理用户缓存与构建产物..."
rm -rf /root/.cache/* 2>/dev/null || true
for u in /home/*; do
  [ -d "$u/.cache" ] && rm -rf "$u/.cache/"* 2>/dev/null || true
done
# 语言/工具链缓存（存在则清）
command -v pip >/dev/null 2>&1      && pip cache purge || true
command -v npm >/dev/null 2>&1      && npm cache clean --force || true
command -v yarn >/dev/null 2>&1     && yarn cache clean || true
command -v composer >/dev/null 2>&1 && composer clear-cache || true
command -v gem >/dev/null 2>&1      && gem cleanup -q || true

# -------- 6) Snap 旧版本 ----------
if command -v snap >/dev/null 2>&1; then
  log "清理 snap 旧版本..."
  snap list --all | awk '/disabled/{print $1, $3}' | xargs -r -n2 snap remove || true
fi

# -------- 7) Docker/容器：狠清 ----------
if command -v docker >/dev/null 2>&1; then
  log "Docker 构建缓存/镜像/容器/网络/卷..."
  docker container prune -f --filter 'until=24h' >/dev/null 2>&1 || true
  docker image prune -af --filter 'until=168h'   >/dev/null 2>&1 || true
  docker builder prune -af --filter 'until=168h' >/dev/null 2>&1 || true
  docker network prune -f                         >/dev/null 2>&1 || true
  docker volume prune -f                          >/dev/null 2>&1 || true
  docker system prune -af --volumes               >/dev/null 2>&1 || true
fi
command -v ctr >/dev/null 2>&1 && ctr -n k8s.io images prune || true

# -------- 8) 宝塔/下载/大文件 ----------
log "清理备份/下载/大文件..."
rm -rf /www/server/backup/* 2>/dev/null || true
rm -rf /home/*/Downloads/* /root/Downloads/* 2>/dev/null || true

# 仅在相对安全的目录里清大文件；排除数据库/宝塔/站点日志
for base in /tmp /var/tmp /var/cache /var/backups /root /home /www/server/backup; do
  [ -d "$base" ] || continue
  find "$base" -xdev -type f -size +100M \
    -not -path "/www/server/panel/*" \
    -not -path "/www/wwwlogs/*" \
    -not -path "/var/lib/mysql/*" \
    -not -path "/var/lib/mariadb/*" \
    -not -path "/var/lib/postgresql/*" \
    -delete 2>/dev/null || true
done

# 常见压缩/备份包（>100M），全盘扫描但排除关键路径
find / -xdev -type f \( -name '*.zip' -o -name '*.tar.gz' -o -name '*.tgz' -o -name '*.bak' \) \
  -size +100M \
  -not -path "/www/server/panel/*" \
  -not -path "/www/wwwlogs/*" \
  -not -path "/var/lib/mysql/*" \
  -not -path "/var/lib/mariadb/*" \
  -not -path "/var/lib/postgresql/*" \
  -delete 2>/dev/null || true

# -------- 9) 旧内核：保留“正在运行 + 最新一个”，其余全清 ----------
log "清理旧内核（保留当前与最新）..."
if command -v dpkg >/dev/null 2>&1; then
  CURK="$(uname -r)"
  mapfile -t ks < <(dpkg -l | awk '/linux-image-[0-9]/{print $2}' | sort -V)
  keep=("linux-image-${CURK}")
  latest="$(printf "%s\n" "${ks[@]}" | grep -v "$CURK" | tail -n1 || true)"
  [ -n "${latest:-}" ] && keep+=("$latest")
  purge=()
  for k in "${ks[@]}"; do
    [[ " ${keep[*]} " == *" $k "* ]] || purge+=("$k")
  done
  ((${#purge[@]})) && apt-get -y purge "${purge[@]}" >/dev/null 2>&1 || true
fi

# -------- 10) 内存/CPU 相关：释放缓存 + 紧凑内存 + 重建 swap ----------
log "释放页缓存/目录项/inode..."
sync
echo 3 > /proc/sys/vm/drop_caches || true
# 紧凑内存（可用则触发）
[ -w /proc/sys/vm/compact_memory ] && echo 1 > /proc/sys/vm/compact_memory || true
# 有 swap 则重建，提高可用内存
if grep -q ' swap ' /proc/swaps 2>/dev/null; then
  log "重建 swap..."
  swapoff -a || true
  swapon -a  || true
fi

# -------- 11) 收尾与定时 ----------
log "===== 清理完成 ====="
df -h /
free -h

log "写入每日 03:00 定时任务..."
chmod +x /root/deep-clean.sh
( crontab -u root -l 2>/dev/null | grep -v 'deep-clean.sh' || true; echo "0 3 * * * /bin/bash /root/deep-clean.sh >/dev/null 2>&1" ) | crontab -u root -

log "✅ DONE."
