#!/usr/bin/env bash
# ======================================================================
# 🌙 Nuro Deep Clean • Safe-Deep+
# 深度清理 CPU/内存/硬盘；不影响宝塔/站点/数据库/PHP 与 SSH
# ======================================================================

set -e
SCRIPT_PATH="/root/deep-clean.sh"
echo "📝 写入/覆盖 $SCRIPT_PATH ..."

cat > "$SCRIPT_PATH" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

# ====== 美观输出 ======
C0="\033[0m"; B="\033[1m"; BLU="\033[38;5;33m"; GRN="\033[38;5;40m"; YEL="\033[38;5;178m"; RED="\033[38;5;196m"; CYA="\033[36m"; GY="\033[90m"
hr(){ printf "${GY}%s${C0}\n" "────────────────────────────────────────────────────────"; }
title(){ printf "\n${B}${BLU}[%s]${C0} %s\n" "$1" "$2"; hr; }
ok(){ printf "${GRN}✔${C0} %s\n" "$*"; }
warn(){ printf "${YEL}⚠${C0} %s\n" "$*"; }
err(){ printf "${RED}✘${C0} %s\n" "$*"; }
log(){ printf "${CYA}•${C0} %s\n" "$*"; }
trap 'err "出错：行 $LINENO"; exit 1' ERR

# ====== 强保护路径（绝不触碰）======
EXCLUDES=(
  "/www/server/panel" "/www/wwwlogs" "/www/wwwroot"
  "/www/server/nginx" "/www/server/apache" "/www/server/openresty"
  "/www/server/mysql" "/var/lib/mysql" "/var/lib/mariadb" "/var/lib/postgresql"
  "/www/server/php" "/etc/php" "/var/lib/php/sessions"
)
is_excluded(){ local p="$1"; for e in "${EXCLUDES[@]}"; do [[ "$p" == "$e"* ]] && return 0; done; return 1; }

# ====== 降优先级执行（避免卡顿）======
NI(){ nice -n 19 ionice -c3 bash -c "$*"; }

# ====== 概况 ======
title "🌍 系统概况" "系统信息与资源概览"
uname -a | sed 's/^/  /'
log "磁盘占用（根分区）："; df -h / | sed 's/^/  /'
log "内存占用："; free -h | sed 's/^/  /'
ok "概况完成"

# ====== 进程与锁（只处理 APT）======
title "🔒 进程清理" "释放 APT/Dpkg 锁"
pkill -9 -f 'apt|apt-get|dpkg|unattended-upgrade' 2>/dev/null || true
rm -f /var/lib/dpkg/lock* /var/cache/apt/archives/lock || true
dpkg --configure -a >/dev/null 2>&1 || true
ok "apt/dpkg 锁处理完成"

# ====== 日志（保 1 天，保结构）======
title "🧾 日志清理" "清空旧日志 保留结构"
journalctl --rotate || true
journalctl --vacuum-time=1d --vacuum-size=64M >/dev/null 2>&1 || true
# 深度+：连轮转压缩的 *.gz/*.old 一并清
NI "find /var/log -type f \\( -name '*.log' -o -name '*.old' -o -name '*.gz' -o -name '*.1' \\) \
  -not -path '/www/server/panel/logs/*' -not -path '/www/wwwlogs/*' -exec truncate -s 0 {} + 2>/dev/null || true"
: > /var/log/wtmp  || true
: > /var/log/btmp  || true
: > /var/log/lastlog || true
: > /var/log/faillog || true
ok "日志清理完成"

# ====== 临时/缓存（排除 PHP 会话）======
title "🧹 缓存清理" "清理 /tmp /var/tmp 等"
NI "find /tmp -xdev -type f -atime +1 -not -name 'sess_*' -delete 2>/dev/null || true"
NI "find /var/tmp -xdev -type f -atime +1 -delete 2>/dev/null || true"
NI "find /tmp -xdev -type f -size +20M -not -name 'sess_*' -delete 2>/dev/null || true"   # 深度+：阈值 50M -> 20M
NI "find /var/tmp -xdev -type f -size +20M -delete 2>/dev/null || true"
NI "find /var/cache -xdev -type f -mtime +1 -delete 2>/dev/null || true"
rm -rf /var/crash/* /var/lib/systemd/coredump/* 2>/dev/null || true
# 深度+：Nginx/fastcgi 临时
rm -rf /var/lib/nginx/tmp/* /var/lib/nginx/body/* /var/lib/nginx/proxy/* 2>/dev/null || true
rm -rf /var/tmp/nginx/* /var/cache/nginx/* 2>/dev/null || true
ok "临时/缓存清理完成"

# ====== 包管理缓存（深度+）======
title "📦 包缓存" "APT / Snap / 语言缓存"
if command -v apt-get >/dev/null 2>&1; then
  systemctl stop apt-daily.service apt-daily.timer apt-daily-upgrade.service apt-daily-upgrade.timer >/dev/null 2>&1 || true
  dpkg --configure -a >/dev/null 2>&1 || true
  apt-get -y autoremove --purge >/dev/null 2>&1 || true
  apt-get -y autoclean >/dev/null 2>&1 || true
  apt-get -y clean >/dev/null 2>&1 || true
  # 清理 rc 残留
  dpkg -l 2>/dev/null | awk '/^rc/{print $2}' | xargs -r dpkg -P >/dev/null 2>&1 || true
  # 深度+：清空 lists/archives 目录
  rm -rf /var/lib/apt/lists/* /var/cache/apt/archives/* /var/cache/apt/archives/partial 2>/dev/null || true
  # 深度+：移除非当前的 headers / modules-extra
  CURK="$(uname -r)"
  dpkg -l | awk '/^ii\s+linux-headers-|^ii\s+linux-modules-extra-/{print $2}' | grep -v "$CURK" | xargs -r apt-get -y purge >/dev/null 2>&1 || true
fi
# Snap：仅删除 disabled 修订
if command -v snap >/dev/null 2>&1; then
  snap list --all 2>/dev/null | sed '1d' | while read -r name ver rev trk pub notes; do
    [ "$notes" = "disabled" ] && [ -n "$rev" ] && snap remove "$name" --revision="$rev" >/dev/null 2>&1 || true
  done
  rm -f /var/lib/snapd/snaps/*.old /var/lib/snapd/snaps/*.partial 2>/dev/null || true
fi
# 语言缓存（尽量不阻塞）
command -v pip >/dev/null      && pip cache purge >/dev/null 2>&1 || true
command -v npm >/dev/null      && npm cache clean --force >/dev/null 2>&1 || true
command -v yarn >/dev/null     && yarn cache clean >/dev/null 2>&1 || true
command -v pnpm >/dev/null     && pnpm store prune >/dev/null 2>&1 || true
command -v composer >/dev/null && composer clear-cache >/dev/null 2>&1 || true
command -v gem >/dev/null      && gem cleanup -q >/dev/null 2>&1 || true
ok "包管理缓存清理完成"

# ====== 备份 & 用户 Downloads —— 全量删除（不限大小）======
title "🗄️ 备份清理" "移除系统与用户备份"
[[ -d /www/server/backup ]] && NI "rm -rf /www/server/backup/* 2>/dev/null || true"
[[ -d /root/Downloads    ]] && NI "rm -rf /root/Downloads/* 2>/dev/null || true"
for d in /home/*/Downloads; do [[ -d "$d" ]] && NI "rm -rf '$d'/* 2>/dev/null || true"; done
# 家目录常见压缩/备份包
for base in /root /home/*; do
  [[ -d "$base" ]] || continue
  NI "find '$base' -type f \\( -name '*.zip' -o -name '*.tar' -o -name '*.tar.gz' -o -name '*.tgz' -o -name '*.rar' -o -name '*.7z' -o -name '*.bak' \\) -delete 2>/dev/null || true"
done
ok "备份与用户下载清空完成"

# ====== 大文件补充（安全路径 >100MB）======
title "🪣 大文件清理" "安全目录下清除 >100MB"
SAFE_BASES=(/tmp /var/tmp /var/cache /var/backups /root /home /www/server/backup)
for base in "${SAFE_BASES[@]}"; do
  [[ -d "$base" ]] || continue
  while IFS= read -r -d '' f; do
    is_excluded "$f" && continue
    NI "rm -f '$f' 2>/dev/null || true"
  done < <(find "$base" -xdev -type f -size +100M -print0 2>/dev/null)
done
ok "大文件补充清理完成"

# ====== 旧内核（保留当前+最新）======
title "🧰 内核清理" "仅保留当前与最新版本"
if command -v dpkg >/dev/null 2>&1; then
  CURK="$(uname -r)"
  mapfile -t KS < <(dpkg -l | awk '/linux-image-[0-9]/{print $2}' | sort -V)
  KEEP=("linux-image-${CURK}")
  LATEST="$(printf "%s\n" "${KS[@]}" | grep -v "$CURK" | tail -n1 || true)"
  [[ -n "${LATEST:-}" ]] && KEEP+=("$LATEST")
  PURGE=(); for k in "${KS[@]}"; do [[ " ${KEEP[*]} " == *" $k "* ]] || PURGE+=("$k"); done
  ((${#PURGE[@]})) && NI "apt-get -y purge ${PURGE[*]} >/dev/null 2>&1 || true"
fi
ok "内核清理完成"

# ====== 体系文件瘦身（深度+，谨慎但安全）======
title "🧽 系统瘦身" "移除 man/doc/多余语言 与 pyc"
# 仅在不是容器基础镜像且磁盘足够时做
if [[ -d /usr/share/man && -d /usr/share/doc && -d /usr/share/locale ]]; then
  # 保留 en* / zh* 的 locale，其他移除（不影响服务运行，仅影响多语言消息）
  find /usr/share/locale -mindepth 1 -maxdepth 1 -type d \
    ! -name 'en*' ! -name 'zh*' -exec rm -rf {} + 2>/dev/null || true
  # 移除 manpages & 文档（节省数百 MB）
  rm -rf /usr/share/man/* /usr/share/doc/* 2>/dev/null || true
fi
# 移除 pyc/__pycache__（可再生）
NI "find / -xdev -type d -name __pycache__ -prune -exec rm -rf {} + 2>/dev/null || true"
NI "find / -xdev -type f -name '*.pyc' -delete 2>/dev/null || true"
ok "系统瘦身完成"

# ====== 内存/CPU 优化（稳态/深度）======
title "⚡ 内存优化" "轻量回收 内存更流畅"
LOAD1=$(awk '{print int($1)}' /proc/loadavg)
MEM_AVAIL_KB=$(awk '/MemAvailable/{print $2}' /proc/meminfo)
MEM_TOTAL_KB=$(awk '/MemTotal/{print $2}' /proc/meminfo)
PCT=$(( MEM_AVAIL_KB*100 / MEM_TOTAL_KB ))
if (( LOAD1 <= 2 && PCT >= 30 )); then
  log "条件满足(Load1=${LOAD1}, MemAvail=${PCT}%)，执行回收"
  sync
  # 深度+：更激进地回收（3 = pagecache+dentries+inodes），低负载才用
  echo 3 > /proc/sys/vm/drop_caches || echo 1 > /proc/sys/vm/drop_caches || true
  [[ -w /proc/sys/vm/compact_memory ]] && echo 1 > /proc/sys/vm/compact_memory || true
  sysctl -w vm.swappiness=10 >/dev/null 2>&1 || true
  ok "内存/CPU 回收完成"
else
  warn "跳过回收（Load1=${LOAD1}, MemAvail=${PCT}%），避免卡顿/断连"
fi

# ===== Swap 管理（<2G 保留；>=2G 移除） =====
title "💾 Swap 管理" "智能检测并保持单一 Swap"
calc_target_mib(){ local mem_kb mib target; mem_kb="$(grep -E '^MemTotal:' /proc/meminfo | tr -s ' ' | cut -d' ' -f2)"; mib=$(( mem_kb/1024 )); target=$(( mib/2 )); (( target<256 ))&&target=256; (( target>2048 ))&&target=2048; echo "$target"; }
active_swaps(){ swapon --show=NAME --noheadings 2>/dev/null | sed '/^$/d'; }
active_count(){ active_swaps | wc -l | tr -d ' '; }
enable_emergency_swap(){ EMERG_DEV=""; local size=256; if modprobe zram 2>/dev/null && [[ -e /sys/class/zram-control/hot_add ]]; then local id dev; id="$(cat /sys/class/zram-control/hot_add)"; dev="/dev/zram${id}"; echo "${size}M" > "/sys/block/zram${id}/disksize"; mkswap "$dev" >/dev/null 2>&1 && swapon -p 200 "$dev" && EMERG_DEV="$dev"; fi; if [[ -z "${EMERG_DEV:-}" ]]; then if fallocate -l ${size}M /swap.emerg 2>/dev/null || dd if=/dev/zero of=/swap.emerg bs=1M count=${size} status=none; then chmod 600 /swap.emerg; mkswap /swap.emerg >/dev/null 2>&1 && swapon -p 150 /swap.emerg && EMERG_DEV="/swap.emerg"; fi; fi; [[ -n "${EMERG_DEV:-}" ]] && ok "已启用应急 swap: $EMERG_DEV (256MiB)" || warn "应急 swap 启用失败"; }
disable_emergency_swap(){ if [[ -n "${EMERG_DEV:-}" ]]; then swapoff "$EMERG_DEV" 2>/dev/null || true; [[ -f "$EMERG_DEV" ]] && rm -f "$EMERG_DEV" 2>/dev/null || true; ok "已关闭应急 swap: $EMERG_DEV"; EMERG_DEV=""; fi; }
normalize_fstab_to_single(){ sed -i '\|/swapfile-[0-9]\+|d' /etc/fstab 2>/dev/null || true; sed -i '\|/swapfile |d' /etc/fstab 2>/dev/null || true; sed -i '\|/dev/zram|d' /etc/fstab 2>/dev/null || true; grep -q '^/swapfile ' /etc/fstab 2>/dev/null || echo "/swapfile none swap sw 0 0" >> /etc/fstab; ok "fstab 已规范为单一 /swapfile"; }
create_single_swapfile(){ local target path fs; target="$(calc_target_mib)"; path="/swapfile"; fs="$(stat -f -c %T / 2>/dev/null || echo "")"; swapoff "$path" 2>/dev/null || true; rm -f "$path" 2>/dev/null || true; [[ "$fs" == "btrfs" ]] && { touch "$path"; chattr +C "$path" 2>/dev/null || true; }; if ! fallocate -l ${target}M "$path" 2>/dev/null; then dd if=/dev/zero of="$path" bs=1M count=${target} status=none conv=fsync; fi; chmod 600 "$path"; mkswap "$path" >/dev/null; swapon "$path"; ok "已创建并启用主 swap：$path (${target}MiB)"; }
single_path_or_empty(){ local n p; n="$(active_count)"; if [[ "$n" == "1" ]]; then p="$(active_swaps | head -n1)"; echo "$p"; else echo ""; fi; }

MEM_MB="$(awk '/MemTotal/{print int($2/1024)}' /proc/meminfo)"
if [[ "$MEM_MB" -ge 2048 ]]; then
  warn "物理内存 ${MEM_MB}MiB ≥ 2048MiB：按策略禁用并移除所有 Swap"
  for _ in 1 2 3; do
    LIST="$(active_swaps)"; [[ -z "$LIST" ]] && break
    while read -r dev; do [[ -z "$dev" ]] && continue; swapoff "$dev" 2>/dev/null || true; case "$dev" in /dev/*) : ;; *) rm -f "$dev" 2>/dev/null || true ;; esac; done <<< "$LIST"
    sleep 1
  done
  rm -f /swapfile /swapfile-* /swap.emerg 2>/dev/null || true
  sed -i '\|/swapfile-[0-9]\+|d' /etc/fstab 2>/dev/null || true
  sed -i '\|/swapfile |d' /etc/fstab 2>/dev/null || true
  sed -i '\|/dev/zram|d' /etc/fstab 2>/dev/null || true
  ok "已禁用并移除 Swap（内存≥2G）"
else
  CNT="$(active_count)"
  if [[ "$CNT" == "0" ]]; then
    log "未检测到活动 swap，创建单一 /swapfile ..."
    create_single_swapfile; normalize_fstab_to_single
  elif [[ "$CNT" == "1" ]]; then
    P="$(single_path_or_empty)"; ok "已存在单一 swap：$P（保持不变）"; normalize_fstab_to_single
  else
    warn "检测到多个 swap（${CNT} 个），将关闭全部并重建为单一 /swapfile"
    enable_emergency_swap
    for _ in 1 2 3; do
      LIST="$(active_swaps)"; [[ -z "$LIST" ]] && break
      while read -r dev; do [[ -z "$dev" ]] && continue; [[ -n "${EMERG_DEV:-}" && "$dev" == "$EMERG_DEV" ]] && continue
        swapoff "$dev" 2>/dev/null || true
        case "$dev" in /dev/*) : ;; *) rm -f "$dev" 2>/dev/null || true ;; esac
      done <<< "$LIST"
      sleep 1
    done
    rm -f /swapfile /swapfile-* /swap.emerg 2>/dev/null || true
    create_single_swapfile; normalize_fstab_to_single; disable_emergency_swap
  fi
fi
log "当前活动 swap："; ( swapon --show || echo "  (none)" ) | sed 's/^/  /'

# ====== 磁盘 TRIM ======
title "🪶 磁盘优化" "执行 fstrim 提升性能"
if command -v fstrim >/dev/null 2>&1; then NI "fstrim -av >/dev/null 2>&1 || true"; ok "fstrim 完成"; else warn "未检测到 fstrim"; fi

# ====== 汇总 & 定时 ======
title "📊 汇总报告" "展示清理后资源状态"
df -h / | sed 's/^/  /'; free -h | sed 's/^/  /'
ok "深度清理完成 ✅"

title "⏰ 自动任务" "每日凌晨 03:00 自动运行"
chmod +x /root/deep-clean.sh
( crontab -u root -l 2>/dev/null | grep -v 'deep-clean.sh' || true; echo "0 3 * * * /bin/bash /root/deep-clean.sh >/dev/null 2>&1" ) | crontab -u root -
ok "已设置每日 03:00 自动清理"
EOF

chmod +x "$SCRIPT_PATH"
bash "$SCRIPT_PATH"
