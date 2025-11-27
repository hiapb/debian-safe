#!/usr/bin/env bash
# ======================================================================
# 🌙 Nuro Deep Clean • Ultra-Min Server Trim (Debian/Ubuntu & AlmaLinux)
# 目标：在不影响 BT/站点/DB/PHP/SSH 的前提下，尽可能“系统极简 + 深度清理”
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
# 兼容你想用的颜色变量名
GREEN="$GRN"; YELLOW="$YEL"; RESET="$C0"

hr(){ printf "${GY}%s${C0}\n" "────────────────────────────────────────────────────────"; }
title(){ printf "\n${B}${BLU}[%s]${C0} %s\n" "$1" "$2"; hr; }
ok(){ printf "${GRN}✔${C0} %s\n" "$*"; }
warn(){ printf "${YEL}⚠${C0} %s\n" "$*"; }
err(){ printf "${RED}✘${C0} %s\n" "$*"; }
log(){ printf "${CYA}•${C0} %s\n" "$*"; }
trap 'err "出错：行 $LINENO"; exit 1' ERR

# ====== 开始安全确认（支持自动模式）======
if [[ -t 0 ]]; then
  # 有终端：说明是人手动执行，弹确认
  echo -e "${GREEN}🧹 一键深度清理...${RESET}"
  echo -e "${YELLOW}⚠️  此操作将清理系统缓存与依赖，仅建议在节点机执行。${RESET}"
  echo -e "${RED}⚠️  非节点机执行可能影响系统或服务，请谨慎确认！${RESET}"
  read -rp "是否继续执行深度清理？[y/N]: " confirm

  if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
    echo -e "${RED}❌ 已取消清理操作。${RESET}"
    exit 0
  fi
else
  # 没有终端：大概率是 crontab/自动任务，自动放行
  echo -e "${YELLOW}⚠️ 检测到非交互环境（如 crontab），自动跳过确认并执行深度清理...${RESET}"
fi


# ====== 保护路径（绝不触碰）======
EXCLUDES=(
  "/www/server/panel" "/www/wwwlogs" "/www/wwwroot"
  "/www/server/nginx" "/www/server/apache" "/www/server/openresty"
  "/www/server/mysql" "/var/lib/mysql" "/var/lib/mariadb" "/var/lib/postgresql"
  "/www/server/php" "/etc/php" "/var/lib/php/sessions"
)
is_excluded(){ local p="$1"; for e in "${EXCLUDES[@]}"; do [[ "$p" == "$e"* ]] && return 0; done; return 1; }

# ====== 工具与平台识别（稳妥版：不用算术判断）======
PKG="unknown"
if command -v apt-get >/dev/null 2>&1; then
  PKG="apt"
elif command -v dnf >/dev/null 2>&1; then
  PKG="dnf"
elif command -v yum >/dev/null 2>&1; then
  PKG="yum"
fi

is_vm(){ command -v systemd-detect-virt >/dev/null 2>&1 && systemd-detect-virt --quiet; }  # 0=虚机
NI(){ nice -n 19 ionice -c3 bash -c "$*"; }  # 低优先级执行

# 包是否存在（按系分流）
dpkg_has(){ dpkg -s "$1" >/dev/null 2>&1; }
rpm_has(){ rpm -q "$1" >/dev/null 2>&1; }

# 安全卸载（适配 apt/dnf/yum）
pkg_purge(){
  for p in "$@"; do
    case "$PKG" in
      apt)
        dpkg_has "$p" && apt-get -y purge "$p" >/dev/null 2>&1 || true
        ;;
      dnf|yum)
        rpm_has "$p" && (dnf -y remove "$p" >/dev/null 2>&1 || yum -y remove "$p" >/dev/null 2>&1) || true
        ;;
    esac
  done
}

# ====== 概况 ======
title "🌍 系统概况" "系统信息与资源概览"
uname -a | sed 's/^/  /'
log "磁盘占用（根分区）："; df -h / | sed 's/^/  /'
log "内存占用："; free -h | sed 's/^/  /'
ok "概况完成"

# ====== APT/Dpkg 锁处理（仅 Deb/Ub）======
if command -v apt-get >/dev/null 2>&1; then
  title "🔒 进程清理" "释放 APT/Dpkg 锁"
  pkill -9 -f 'apt|apt-get|dpkg|unattended-upgrade' 2>/dev/null || true
  rm -f /var/lib/dpkg/lock* /var/cache/apt/archives/lock || true
  dpkg --configure -a >/dev/null 2>&1 || true
  ok "apt/dpkg 锁处理完成"
fi

# ====== 日志清理（保 1 天，保结构）======
title "🧾 日志清理" "清空旧日志 保留结构"
journalctl --rotate || true
journalctl --vacuum-time=1d --vacuum-size=64M >/dev/null 2>&1 || true
NI "find /var/log -type f \( -name '*.log' -o -name '*.old' -o -name '*.gz' -o -name '*.1' \) \
  -not -path '/www/server/panel/logs/*' -not -path '/www/wwwlogs/*' -exec truncate -s 0 {} + 2>/dev/null || true"
: > /var/log/wtmp  || true; : > /var/log/btmp  || true; : > /var/log/lastlog || true; : > /var/log/faillog || true
ok "日志清理完成"

# ====== 临时/缓存（更深）======
title "🧹 缓存清理" "清理 /tmp /var/tmp 等"
NI "find /tmp -xdev -type f -atime +1 -not -name 'sess_*' -delete 2>/dev/null || true"
NI "find /var/tmp -xdev -type f -atime +1 -delete 2>/dev/null || true"
NI "find /tmp -xdev -type f -size +20M -not -name 'sess_*' -delete 2>/dev/null || true"
NI "find /var/tmp -xdev -type f -size +20M -delete 2>/dev/null || true"
NI "find /var/cache -xdev -type f -mtime +1 -delete 2>/dev/null || true"
rm -rf /var/crash/* /var/lib/systemd/coredump/* 2>/dev/null || true
# Nginx/fastcgi 临时缓存
rm -rf /var/lib/nginx/tmp/* /var/lib/nginx/body/* /var/lib/nginx/proxy/* 2>/dev/null || true
rm -rf /var/tmp/nginx/* /var/cache/nginx/* 2>/dev/null || true
ok "临时/缓存清理完成"

# ====== 包缓存 & 历史清理（跨发行版）======
title "📦 包缓存" "APT/DNF 历史与缓存深度清理"
if [ "$PKG" = "apt" ]; then
  systemctl stop apt-daily.service apt-daily.timer apt-daily-upgrade.service apt-daily-upgrade.timer >/dev/null 2>&1 || true
  apt-get -y autoremove --purge  >/dev/null 2>&1 || true
  apt-get -y autoclean           >/dev/null 2>&1 || true
  apt-get -y clean               >/dev/null 2>&1 || true
  dpkg -l 2>/dev/null | awk '/^rc/{print $2}' | xargs -r dpkg -P >/dev/null 2>&1 || true
  rm -rf /var/lib/apt/lists/* /var/cache/apt/archives/* /var/cache/apt/archives/partial 2>/dev/null || true
  CURK="$(uname -r)"
  dpkg -l | awk '/^ii\s+linux-(headers|modules-extra)-/{print $2}' | grep -v "$CURK" \
    | xargs -r apt-get -y purge >/dev/null 2>&1 || true
elif [ "$PKG" = "dnf" ] || [ "$PKG" = "yum" ]; then
  (dnf -y autoremove >/dev/null 2>&1 || yum -y autoremove >/dev/null 2>&1 || true)
  (dnf -y clean all >/dev/null 2>&1 || yum -y clean all >/dev/null 2>&1 || true)
  rm -rf /var/cache/dnf/* /var/cache/yum/* 2>/dev/null || true
  pkg_purge dracut-config-rescue >/dev/null 2>&1 || true
fi
ok "包缓存/历史清理完成"

# ====== 组件裁剪：跨发行版“非必需”组件 ======
title "✂️ 组件裁剪" "移除非必需工具包（服务器极简）"
if [ "$PKG" = "apt" ]; then
  pkg_purge snapd cloud-init apport whoopsie popularity-contest \
            landscape-client ubuntu-advantage-tools update-notifier unattended-upgrades
  pkg_purge cockpit cockpit-ws cockpit-system \
            avahi-daemon cups* modemmanager network-manager* plymouth* fwupd* \
            printer-driver-* xserver-xorg* x11-* wayland* *-doc
elif [ "$PKG" = "dnf" ] || [ "$PKG" = "yum" ]; then
  pkg_purge cloud-init subscription-manager insights-client \
            cockpit cockpit-ws cockpit-system \
            abrt* sos* avahi* cups* modemmanager NetworkManager* plymouth* fwupd* \
            man-db man-pages groff-base texinfo
fi
ok "组件裁剪完成"

# ====== Snap 全清（兜底）======
title "🧨 Snap 移除" "彻底移除 snapd 生态"
if command -v snap >/dev/null 2>&1; then
  snap list 2>/dev/null | sed '1d' | awk '{print $1}' | while read -r app; do snap remove "$app" >/dev/null 2>&1 || true; done
fi
systemctl stop snapd.service snapd.socket 2>/dev/null || true
umount /snap 2>/dev/null || true
pkg_purge snapd
rm -rf /snap /var/snap /var/lib/snapd /var/cache/snapd 2>/dev/null || true
ok "Snap 生态清理完成"

# ====== 文档/本地化/开发静态库 瘦身 ======
title "🧽 系统瘦身" "文档/本地化/静态库/pyc"
rm -rf /usr/share/man/* /usr/share/info/* /usr/share/doc/* 2>/dev/null || true
if [[ -d /usr/share/locale ]]; then
  find /usr/share/locale -mindepth 1 -maxdepth 1 -type d \
    | grep -Ev '^(.*\/)?(en|zh)' | xargs -r rm -rf 2>/dev/null || true
fi
if [[ -d /usr/lib/locale ]]; then
  ls /usr/lib/locale 2>/dev/null | grep -Ev '^(en|zh)' \
    | xargs -r -I{} rm -rf "/usr/lib/locale/{}" 2>/dev/null || true
fi
NI "find / -xdev -type d -name '__pycache__' -prune -exec rm -rf {} + 2>/dev/null || true"
NI "find / -xdev -type f -name '*.pyc' -delete 2>/dev/null || true"
NI "find /usr/lib /usr/lib64 /lib /lib64 -type f \( -name '*.a' -o -name '*.la' \) -delete 2>/dev/null || true"
ok "系统瘦身完成"

# ====== 云/固件裁剪（仅云虚机移除 firmware）======
title "☁️ 虚机裁剪" "虚机移除 linux-firmware（物理机保留）"
if is_vm; then
  case "$PKG" in
    apt|dnf|yum) pkg_purge linux-firmware ;;
  esac
  rm -rf /lib/firmware/* 2>/dev/null || true
  ok "已在虚机裁剪 firmware"
else
  warn "检测为物理机或未知虚拟化，保留 firmware 以免驱动缺失"
fi

# ====== 备份 & 用户下载清理 ======
title "🗄️ 备份清理" "移除系统与用户备份/下载"
[[ -d /www/server/backup ]] && NI "rm -rf /www/server/backup/* 2>/dev/null || true"
[[ -d /root/Downloads    ]] && NI "rm -rf /root/Downloads/* 2>/dev/null || true"
for d in /home/*/Downloads; do [[ -d "$d" ]] && NI "rm -rf '$d'/* 2>/dev/null || true"; done
for base in /root /home/*; do
  [[ -d "$base" ]] || continue
  NI "find '$base' -type f \( -name '*.zip' -o -name '*.tar' -o -name '*.tar.gz' -o -name '*.tgz' -o -name '*.rar' -o -name '*.7z' -o -name '*.bak' \) -delete 2>/dev/null || true"
done
ok "备份与用户下载清空完成"

# ====== 大文件补充（安全路径 >50MB）======
title "🪣 大文件清理" "安全目录下清除 >50MB"
SAFE_BASES=(/tmp /var/tmp /var/cache /var/backups /root /home /www/server/backup)
for base in "${SAFE_BASES[@]}"; do
  [[ -d "$base" ]] || continue
  while IFS= read -r -d '' f; do
    is_excluded "$f" && continue
    NI "rm -f '$f' 2>/dev/null || true"
  done < <(find "$base" -xdev -type f -size +50M -print0 2>/dev/null)
done
ok "大文件补充清理完成"

# ====== 旧内核（保留当前+最新）======
title "🧰 内核清理" "仅保留当前与最新版本"
if [ "$PKG" = "apt" ]; then
  CURK="$(uname -r)"
  mapfile -t KS < <(dpkg -l | awk '/linux-image-[0-9]/{print $2}' | sort -V)
  KEEP=("linux-image-${CURK}")
  LATEST="$(printf "%s\n" "${KS[@]}" | grep -v "$CURK" | tail -n1 || true)"
  [[ -n "${LATEST:-}" ]] && KEEP+=("$LATEST")
  PURGE=(); for k in "${KS[@]}"; do [[ " ${KEEP[*]} " == *" $k "* ]] || PURGE+=("$k"); done
  ((${#PURGE[@]})) && NI "apt-get -y purge ${PURGE[*]} >/dev/null 2>&1 || true"
elif [ "$PKG" = "dnf" ] || [ "$PKG" = "yum" ]; then
  CURK_ESC="$(uname -r | sed 's/\./\\./g')"
  mapfile -t RMK < <(rpm -q kernel-core kernel | grep -vE "$CURK_ESC" | sort -V | head -n -1 || true)
  ((${#RMK[@]})) && (dnf -y remove "${RMK[@]}" >/dev/null 2>&1 || yum -y remove "${RMK[@]}" >/dev/null 2>&1 || true)
fi
ok "内核清理完成"

# ====== 内存/CPU 优化（更激进版）======
title "⚡ 内存优化" "强制回收缓存并紧凑内存"
LOAD1=$(awk '{print int($1)}' /proc/loadavg)
MEM_AVAIL_KB=$(awk '/MemAvailable/{print $2}' /proc/meminfo)
MEM_TOTAL_KB=$(awk '/MemTotal/{print $2}' /proc/meminfo)
PCT=$(( MEM_AVAIL_KB*100 / MEM_TOTAL_KB ))

log "当前负载：Load1=${LOAD1}，可用内存约 ${PCT}%"
if (( LOAD1 >= 8 )); then
  warn "当前负载过高（>=8），为避免系统瞬间卡死，暂时跳过内存强制回收"
else
  log "同步磁盘并强制丢弃页缓存/目录项/索引节点..."
  sync
  # 多次尝试，尽可能把能回收的都回收
  echo 3 > /proc/sys/vm/drop_caches 2>/dev/null || echo 1 > /proc/sys/vm/drop_caches 2>/dev/null || true
  sleep 1
  echo 3 > /proc/sys/vm/drop_caches 2>/dev/null || true

  # 内存紧凑，减少碎片
  if [[ -w /proc/sys/vm/compact_memory ]]; then
    echo 1 > /proc/sys/vm/compact_memory 2>/dev/null || true
  fi

  # 降低 swap 使用倾向
  sysctl -w vm.swappiness=10 >/dev/null 2>&1 || true

  ok "内存/CPU 回收完成（已强制 drop_caches & compact_memory）"
fi

# ====== Swap 策略（内存≥2G 禁用；<2G 单一 /swapfile）======
title "💾 Swap 管理" "≥2G禁用；<2G 单一 /swapfile"
calc_target_mib(){ local mem_kb mib target; mem_kb="$(grep -E '^MemTotal:' /proc/meminfo | tr -s ' ' | cut -d' ' -f2)"; mib=$(( mem_kb/1024 )); target=$(( mib/2 )); (( target<256 ))&&target=256; (( target>2048 ))&&target=2048; echo "$target"; }
active_swaps(){ swapon --show=NAME --noheadings 2>/dev/null | sed '/^$/d'; }
active_count(){ active_swaps | wc -l | tr -d ' '; }
normalize_fstab_to_single(){ sed -i '\|/swapfile-[0-9]\+|d' /etc/fstab 2>/dev/null || true; sed -i '\|/swapfile |d' /etc/fstab 2>/dev/null || true; sed -i '\|/dev/zram|d' /etc/fstab 2>/dev/null || true; grep -q '^/swapfile ' /etc/fstab 2>/dev/null || echo "/swapfile none swap sw 0 0" >> /etc/fstab; ok "fstab 已规范为单一 /swapfile"; }
create_single_swapfile(){ local target path fs; target="$(calc_target_mib)"; path="/swapfile"; fs="$(stat -f -c %T / 2>/dev/null || echo "")"; swapoff "$path" 2>/dev/null || true; rm -f "$path" 2>/dev/null || true; [[ "$fs" == "btrfs" ]] && { touch "$path"; chattr +C "$path" 2>/dev/null || true; }; if ! fallocate -l ${target}M "$path" 2>/dev/null; then dd if=/dev/zero of="$path" bs=1M count=${target} status=none conv=fsync; fi; chmod 600 "$path"; mkswap "$path" >/dev/null; swapon "$path"; ok "已创建并启用主 swap：$path (${target}MiB)"; }
single_path_or_empty(){ local n p; n="$(active_count)"; if [[ "$n" == "1" ]]; then p="$(active_swaps | head -n1)"; echo "$p"; else echo ""; fi; }

MEM_MB="$(awk '/MemTotal/{print int($2/1024)}' /proc/meminfo)"
if [[ "$MEM_MB" -ge 2048 ]]; then
  warn "物理内存 ${MEM_MB}MiB ≥ 2048MiB：禁用并移除所有 Swap"
  for _ in 1 2 3; do
    LIST="$(active_swaps)"; [[ -z "$LIST" ]] && break
    while read -r dev; do [[ -z "$dev" ]] && continue; swapoff "$dev" 2>/dev/null || true; case "$dev" in /dev/*) : ;; *) rm -f "$dev" 2>/dev/null || true ;; esac; done <<< "$LIST"
    sleep 1
  done
  rm -f /swapfile /swapfile-* /swap.emerg 2>/dev/null || true
  sed -i '\|/swapfile-[0-9]\+|d' /etc/fstab 2>/dev/null || true
  sed -i '\|/swapfile |d' /etc/fstab 2>/dev/null || true
  sed -i '\|/dev/zram|d'        /etc/fstab 2>/dev/null || true
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
    for _ in 1 2 3; do
      LIST="$(active_swaps)"; [[ -z "$LIST" ]] && break
      while read -r dev; do [[ -z "$dev" ]] && continue
        swapoff "$dev" 2>/dev/null || true
        case "$dev" in /dev/*) : ;; *) rm -f "$dev" 2>/dev/null || true ;; esac
      done <<< "$LIST"
      sleep 1
    done
    rm -f /swapfile /swapfile-* /swap.emerg 2>/dev/null || true
    create_single_swapfile; normalize_fstab_to_single
  fi
fi
log "当前活动 swap："; ( swapon --show || echo "  (none)" ) | sed 's/^/  /'

# ====== 磁盘 TRIM ======
title "🪶 磁盘优化" "执行 fstrim 提升性能"
if command -v fstrim >/dev/null 2>&1; then NI "fstrim -av >/dev/null 2>&1 || true"; ok "fstrim 完成"; else warn "未检测到 fstrim"; fi

# ====== 汇总 & 定时 ======
title "📊 汇总报告" "展示清理后资源状态"
df -h / | sed 's/^/  /'; free -h | sed 's/^/  /'
ok "极简深度清理完成 ✅"

title "⏰ 自动任务" "每日凌晨 03:00 自动运行"
chmod +x /root/deep-clean.sh
( crontab -u root -l 2>/dev/null | grep -v 'deep-clean.sh' || true; echo "0 3 * * * /bin/bash /root/deep-clean.sh >/dev/null 2>&1" ) | crontab -u root -
ok "已设置每日 03:00 自动清理"
EOF

chmod +x "$SCRIPT_PATH"
bash "$SCRIPT_PATH"
