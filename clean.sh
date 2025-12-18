#!/usr/bin/env bash
# ======================================================================
# 🌙 Nuro Deep Clean • Ultra-Min Server Trim (Debian/Ubuntu & RHEL系: Alma/Rocky/CentOS)
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
GREEN="$GRN"; YELLOW="$YEL"; RESET="$C0"
hr(){ printf "${GY}%s${C0}\n" "────────────────────────────────────────────────────────"; }
title(){ printf "\n${B}${BLU}[%s]${C0} %s\n" "$1" "$2"; hr; }
ok(){ printf "${GRN}✔${C0} %s\n" "$*"; }
warn(){ printf "${YEL}⚠${C0} %s\n" "$*"; }
err(){ printf "${RED}✘${C0} %s\n" "$*"; }
log(){ printf "${CYA}•${C0} %s\n" "$*"; }
trap 'err "出错：行 $LINENO"; exit 1' ERR

# 模式开关（默认都关）
FORCE_MEM_CLEAN=0        # 强制内存深度清理
FORCE_RESTART_SERVICES=0 # 重启所有非核心服务

# ====== 开始安全确认（支持自动模式 + 强制模式）======
if [[ -t 0 ]]; then
  echo -e "${GREEN}🧹 一键深度清理...${RESET}"
  echo -e "${YELLOW}⚠️  此操作将清理系统缓存与依赖，仅建议在节点机执行。${RESET}"
  echo -e "${RED}⚠️  非节点机执行可能影响系统或服务，请谨慎确认！${RESET}"
  read -rp "是否继续执行深度清理？[y/N]: " confirm
  if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
    echo -e "${RED}❌ 已取消清理操作。${RESET}"
    exit 0
  fi

  echo
  echo -e "${YELLOW}⚠️  可选：启用【强制模式】=${RESET}"
  echo -e "${YELLOW}    1）更激进的内存深度清理（多次 drop_caches 等）${RESET}"
  echo -e "${YELLOW}    2）重启所有非核心 systemd 服务（站点/数据库等统统重启）${RESET}"
  echo -e "${RED}⚠️  敢选“是”就默认你这台机没有重要业务，请自行承担风险。${RESET}"
  read -rp "是否启用强制模式（强制内存 + 重启所有非核心服务）？[y/N]: " force_mode

  if [[ "$force_mode" =~ ^[Yy]$ ]]; then
    FORCE_MEM_CLEAN=1
    FORCE_RESTART_SERVICES=1
    echo -e "${GREEN}✅ 已开启【强制模式】（内存深度清理 + 重启所有非核心服务）。${RESET}"
  else
    FORCE_MEM_CLEAN=0
    FORCE_RESTART_SERVICES=0
    echo -e "${YELLOW}ℹ️ 使用普通模式：不重启服务，内存清理相对温和。${RESET}"
  fi
else
  FORCE_MEM_CLEAN=0
  FORCE_RESTART_SERVICES=0
  echo -e "${YELLOW}⚠️ 检测到非交互环境（如 crontab），自动以【普通模式】执行（不强制内存、不重启服务）...${RESET}"
fi

# ====== 保护路径（绝不触碰）======
EXCLUDES=(
  "/www/server/panel" "/www/wwwlogs" "/www/wwwroot"
  "/www/server/nginx" "/www/server/apache" "/www/server/openresty"
  "/www/server/mysql" "/var/lib/mysql" "/var/lib/mariadb" "/var/lib/postgresql"
  "/www/server/php" "/etc/php" "/var/lib/php/sessions"
)
is_excluded(){ local p="$1"; for e in "${EXCLUDES[@]}"; do [[ "$p" == "$e"* ]] && return 0; done; return 1; }

# ====== 工具与平台识别 ======
PKG="unknown"
if command -v apt-get >/dev/null 2>&1; then
  PKG="apt"
elif command -v dnf >/dev/null 2>&1; then
  PKG="dnf"
elif command -v yum >/dev/null 2>&1; then
  PKG="yum"
fi

has_cmd(){ command -v "$1" >/dev/null 2>&1; }

# 低优先级执行（ionice 不存在就退化为 nice）
NI(){
  if has_cmd ionice; then
    nice -n 19 ionice -c3 bash -c "$*"
  else
    nice -n 19 bash -c "$*"
  fi
}

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
      *)
        # 其它系统：跳过
        true
        ;;
    esac
  done
}

# ====== 自动检测依赖并安装（仅 apt/dnf/yum）======
pkg_install(){
  local pkgs=("$@")
  ((${#pkgs[@]})) || return 0
  case "$PKG" in
    apt)
      export DEBIAN_FRONTEND=noninteractive
      apt-get -y update >/dev/null 2>&1 || true
      apt-get -y install "${pkgs[@]}" >/dev/null 2>&1 || true
      ;;
    dnf)
      dnf -y install "${pkgs[@]}" >/dev/null 2>&1 || true
      ;;
    yum)
      yum -y install "${pkgs[@]}" >/dev/null 2>&1 || true
      ;;
    *)
      # 非 apt/dnf/yum：无法统一安装，跳过
      true
      ;;
  esac
}

ensure_cmd(){
  # ensure_cmd <cmd> <apt_pkg> <rpm_pkg>
  local cmd="$1" apt_pkg="${2:-}" rpm_pkg="${3:-}"
  if has_cmd "$cmd"; then return 0; fi
  log "检测到缺少命令：$cmd，尝试自动安装..."
  case "$PKG" in
    apt) [[ -n "$apt_pkg" ]] && pkg_install "$apt_pkg" ;;
    dnf|yum) [[ -n "$rpm_pkg" ]] && pkg_install "$rpm_pkg" ;;
    *) true ;;
  esac
  has_cmd "$cmd" || warn "仍缺少：$cmd（可能是极简系统/容器/仓库不可用），将自动跳过相关步骤"
}

ensure_cron(){
  if has_cmd crontab; then return 0; fi
  log "未发现 crontab，尝试安装定时任务组件..."
  case "$PKG" in
    apt) pkg_install cron ;;
    dnf|yum) pkg_install cronie ;;
    *) true ;;
  esac
  if has_cmd crontab; then
    if has_cmd systemctl; then
      systemctl enable --now cron  >/dev/null 2>&1 || true
      systemctl enable --now crond >/dev/null 2>&1 || true
    fi
    ok "定时任务组件已就绪（crontab 可用）"
  else
    warn "无法安装/启用 cron（crontab 仍不可用），将跳过自动任务设置"
  fi
}

# systemd-detect-virt 缺失就按“未知/非虚机”处理，避免误删 firmware
is_vm(){
  if has_cmd systemd-detect-virt; then
    systemd-detect-virt --quiet
  else
    return 1
  fi
}

# 关键小工具尝试补齐（装不了也不影响主流程）
ensure_cmd ionice util-linux util-linux
ensure_cmd sysctl procps procps-ng
ensure_cmd systemd-detect-virt systemd systemd

# ====== 概况 ======
title "🌍 系统概况" "系统信息与资源概览"
uname -a | sed 's/^/  /'
log "磁盘占用（根分区）："; df -h / 2>/dev/null | sed 's/^/  /' || true
log "内存占用："; free -h 2>/dev/null | sed 's/^/  /' || true
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
ensure_cmd journalctl systemd systemd

if has_cmd journalctl; then
  journalctl --rotate || true
  journalctl --vacuum-time=1d --vacuum-size=64M >/dev/null 2>&1 || true
else
  warn "未检测到 journalctl，跳过 journald 日志裁剪"
fi

NI "find /var/log -type f \( -name '*.log' -o -name '*.old' -o -name '*.gz' -o -name '*.1' \) \
  -not -path '/www/server/panel/logs/*' -not -path '/www/wwwlogs/*' -exec truncate -s 0 {} + 2>/dev/null || true"

: > /var/log/wtmp  || true
: > /var/log/btmp  || true
: > /var/log/lastlog || true
: > /var/log/faillog || true
ok "日志清理完成"

# ====== 临时/缓存（更深）======
title "🧹 缓存清理" "清理 /tmp /var/tmp 等"
NI "find /tmp -xdev -type f -atime +1 -not -name 'sess_*' -delete 2>/dev/null || true"
NI "find /var/tmp -xdev -type f -atime +1 -delete 2>/dev/null || true"
NI "find /tmp -xdev -type f -size +20M -not -name 'sess_*' -delete 2>/dev/null || true"
NI "find /var/tmp -xdev -type f -size +20M -delete 2>/dev/null || true"
NI "find /var/cache -xdev -type f -mtime +1 -delete 2>/dev/null || true"
rm -rf /var/crash/* /var/lib/systemd/coredump/* 2>/dev/null || true
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
else
  warn "未知包管理器：跳过包缓存/历史清理"
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
else
  warn "未知包管理器：跳过组件裁剪（卸包）"
fi
ok "组件裁剪完成"

# ====== Snap 全清（兜底）======
title "🧨 Snap 移除" "彻底移除 snapd 生态"
if command -v snap >/dev/null 2>&1; then
  snap list 2>/dev/null | sed '1d' | awk '{print $1}' | while read -r app; do
    [[ -n "$app" ]] && snap remove "$app" >/dev/null 2>&1 || true
  done
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
    *) true ;;
  esac
  rm -rf /lib/firmware/* 2>/dev/null || true
  ok "已在虚机裁剪 firmware"
else
  warn "检测为物理机或未知虚拟化（或缺少检测工具），保留 firmware 以免驱动缺失"
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
  mapfile -t RMK < <(rpm -q kernel-core kernel 2>/dev/null | grep -vE "$CURK_ESC" | sort -V | head -n -1 || true)
  ((${#RMK[@]})) && (dnf -y remove "${RMK[@]}" >/dev/null 2>&1 || yum -y remove "${RMK[@]}" >/dev/null 2>&1 || true)
else
  warn "未知包管理器：跳过内核清理"
fi
ok "内核清理完成"

# ====== 内存/CPU 优化（普通模式 + 强制模式）======
title "⚡ 内存优化" "回收缓存并紧凑内存"
LOAD1=$(awk '{print int($1)}' /proc/loadavg 2>/dev/null || echo 0)
MEM_AVAIL_KB=$(awk '/MemAvailable/{print $2}' /proc/meminfo 2>/dev/null || echo 0)
MEM_TOTAL_KB=$(awk '/MemTotal/{print $2}' /proc/meminfo 2>/dev/null || echo 1)
PCT=$(( MEM_AVAIL_KB*100 / MEM_TOTAL_KB ))

log "当前负载：Load1=${LOAD1}，可用内存约 ${PCT}%"
if (( LOAD1 >= 8 )) && [[ "${FORCE_MEM_CLEAN:-0}" -eq 0 ]]; then
  warn "当前负载过高（>=8），且未启用强制模式，为避免系统瞬间卡死，暂时跳过内存回收"
else
  if [[ "${FORCE_MEM_CLEAN:-0}" -eq 1 ]]; then
    log "已启用【强制内存深度清理】模式：更激进地回收缓存和整理内存，可能短暂卡顿..."
  else
    log "使用普通内存清理模式：在当前负载下安全回收缓存"
  fi

  log "同步磁盘并丢弃页缓存/目录项/索引节点..."
  sync || true

  if [[ "${FORCE_MEM_CLEAN:-0}" -eq 1 ]]; then
    has_cmd sysctl && sysctl -w vm.vfs_cache_pressure=200 >/dev/null 2>&1 || true
    echo 3 > /proc/sys/vm/drop_caches 2>/dev/null || echo 1 > /proc/sys/vm/drop_caches 2>/dev/null || true
    sleep 1
    echo 3 > /proc/sys/vm/drop_caches 2>/dev/null || true
    sleep 1
    echo 3 > /proc/sys/vm/drop_caches 2>/dev/null || true
    has_cmd sysctl && sysctl -w vm.vfs_cache_pressure=100 >/dev/null 2>&1 || true
  else
    echo 3 > /proc/sys/vm/drop_caches 2>/dev/null || echo 1 > /proc/sys/vm/drop_caches 2>/dev/null || true
  fi

  if [[ -w /proc/sys/vm/compact_memory ]]; then
    echo 1 > /proc/sys/vm/compact_memory 2>/dev/null || true
  fi

  has_cmd sysctl && sysctl -w vm.swappiness=10 >/dev/null 2>&1 || true
  ok "内存/CPU 回收完成（模式：$([[ "${FORCE_MEM_CLEAN:-0}" -eq 1 ]] && echo 强制 || echo 普通)）"
fi

# ====== 可选：重启所有非核心服务 ======
if [[ "${FORCE_RESTART_SERVICES:-0}" -eq 1 ]]; then
  title "🔃 服务重启" "重启所有非核心 systemd 服务以最大化释放内存"
  if ! command -v systemctl >/dev/null 2>&1; then
    warn "系统无 systemctl，无法自动重启服务，已跳过此步骤。"
  else
    CORE_SERVICES=(
      systemd systemd-journald systemd-logind systemd-udevd systemd-networkd systemd-resolved
      dbus sshd ssh networkd NetworkManager networking rsyslog cron crond polkit
    )
    log "获取系统所有正在运行或已启用的服务 ..."
    SERVICES=$(systemctl list-units --type=service --state=running,enabled --no-pager --no-legend \
      | awk '{print $1}' | sed 's/\.service$//')

    for svc in $SERVICES; do
      [[ -z "$svc" ]] && continue
      skip=0
      for core in "${CORE_SERVICES[@]}"; do
        if [[ "$svc" == "$core"* ]]; then skip=1; break; fi
      done
      if [[ "$skip" -eq 1 ]]; then
        log "跳过核心服务：$svc"
        continue
      fi

      log "重启服务：$svc"
      if systemctl restart "$svc" 2>/dev/null; then
        ok "服务已重启：$svc"
      else
        warn "重启失败：$svc（已跳过）"
      fi
    done
  fi
else
  title "🔃 服务重启" "未启用服务重启选项，跳过"
  log "如需释放更多内存，下次可启用【强制模式】重启所有非核心服务。"
fi

# ====== Swap 策略（内存≥2G 禁用；<2G 单一 /swapfile）======
title "💾 Swap 管理" "≥2G禁用；<2G 单一 /swapfile"

calc_target_mib(){
  local mem_kb mib target
  mem_kb="$(grep -E '^MemTotal:' /proc/meminfo | tr -s ' ' | cut -d' ' -f2 2>/dev/null || echo 0)"
  mib=$(( mem_kb/1024 ))
  target=$(( mib/2 ))
  (( target<256 )) && target=256
  (( target>2048 )) && target=2048
  echo "$target"
}

active_swaps(){ swapon --show=NAME --noheadings 2>/dev/null | sed '/^$/d' || true; }
active_count(){ active_swaps | wc -l | tr -d ' ' || echo 0; }

normalize_fstab_to_single(){
  sed -i '\|/swapfile-[0-9]\+|d' /etc/fstab 2>/dev/null || true
  sed -i '\|/swapfile |d' /etc/fstab 2>/dev/null || true
  sed -i '\|/dev/zram|d' /etc/fstab 2>/dev/null || true
  grep -q '^/swapfile ' /etc/fstab 2>/dev/null || echo "/swapfile none swap sw 0 0" >> /etc/fstab
  ok "fstab 已规范为单一 /swapfile"
}

# 探测：是否允许 swapon（很多 NAT/容器会禁止）
SWAP_SUPPORTED=1
probe_swap_support(){
  local tmp="/swapfile.__probe__"
  # 必须是 root 且能写 /swapfile
  [[ "$(id -u)" -eq 0 ]] || return 1
  # 创建一个最小的 probe swapfile
  rm -f "$tmp" 2>/dev/null || true
  if ! fallocate -l 16M "$tmp" 2>/dev/null; then
    dd if=/dev/zero of="$tmp" bs=1M count=16 status=none conv=fsync 2>/dev/null || { rm -f "$tmp" 2>/dev/null || true; return 1; }
  fi
  chmod 600 "$tmp" 2>/dev/null || true
  mkswap "$tmp" >/dev/null 2>&1 || { rm -f "$tmp" 2>/dev/null || true; return 1; }

  # 关键：尝试 swapon，如果不允许则返回 1
  if swapon "$tmp" >/dev/null 2>&1; then
    swapoff "$tmp" >/dev/null 2>&1 || true
    rm -f "$tmp" 2>/dev/null || true
    return 0
  else
    rm -f "$tmp" 2>/dev/null || true
    return 1
  fi
}

if ! probe_swap_support; then
  SWAP_SUPPORTED=0
  warn "检测到宿主机禁止 swapon/swapoff（常见于 NAT/容器/Virt 限制），已跳过 Swap 管理，避免脚本中断"
  log "当前活动 swap："; ( swapon --show || echo "  (none)" ) 2>/dev/null | sed 's/^/  /' || true
else
  create_single_swapfile(){
    local target path fs
    target="$(calc_target_mib)"
    path="/swapfile"
    fs="$(stat -f -c %T / 2>/dev/null || echo "")"

    swapoff "$path" >/dev/null 2>&1 || true
    rm -f "$path" 2>/dev/null || true

    [[ "$fs" == "btrfs" ]] && { touch "$path"; chattr +C "$path" 2>/dev/null || true; }

    if ! fallocate -l ${target}M "$path" 2>/dev/null; then
      dd if=/dev/zero of="$path" bs=1M count=${target} status=none conv=fsync 2>/dev/null || true
    fi
    chmod 600 "$path" 2>/dev/null || true
    mkswap "$path" >/dev/null 2>&1 || { warn "mkswap 失败，跳过 swap 创建"; rm -f "$path" 2>/dev/null || true; return 0; }

    if swapon "$path" >/dev/null 2>&1; then
      ok "已创建并启用主 swap：$path (${target}MiB)"
    else
      warn "swapon 被宿主机拒绝（Operation not permitted），已跳过 swap 启用"
      rm -f "$path" 2>/dev/null || true
      return 0
    fi
  }

  single_path_or_empty(){
    local n p
    n="$(active_count)"
    if [[ "$n" == "1" ]]; then p="$(active_swaps | head -n1)"; echo "$p"; else echo ""; fi
  }

  MEM_MB="$(awk '/MemTotal/{print int($2/1024)}' /proc/meminfo 2>/dev/null || echo 0)"
  if [[ "$MEM_MB" -ge 2048 ]]; then
    warn "物理内存 ${MEM_MB}MiB ≥ 2048MiB：禁用并移除所有 Swap（若宿主机允许）"
    for _ in 1 2 3; do
      LIST="$(active_swaps)"; [[ -z "$LIST" ]] && break
      while read -r dev; do
        [[ -z "$dev" ]] && continue
        swapoff "$dev" >/dev/null 2>&1 || true
        case "$dev" in /dev/*) : ;; *) rm -f "$dev" 2>/dev/null || true ;; esac
      done <<< "$LIST"
      sleep 1
    done
    rm -f /swapfile /swapfile-* /swap.emerg 2>/dev/null || true
    sed -i '\|/swapfile-[0-9]\+|d' /etc/fstab 2>/dev/null || true
    sed -i '\|/swapfile |d' /etc/fstab 2>/dev/null || true
    sed -i '\|/dev/zram|d'        /etc/fstab 2>/dev/null || true
    ok "Swap 处理完成（内存≥2G：尝试禁用/移除）"
  else
    CNT="$(active_count)"
    if [[ "$CNT" == "0" ]]; then
      log "未检测到活动 swap，创建单一 /swapfile ..."
      create_single_swapfile
      normalize_fstab_to_single
    elif [[ "$CNT" == "1" ]]; then
      P="$(single_path_or_empty)"
      ok "已存在单一 swap：$P（保持不变）"
      normalize_fstab_to_single
    else
      warn "检测到多个 swap（${CNT} 个），将尝试关闭全部并重建为单一 /swapfile"
      for _ in 1 2 3; do
        LIST="$(active_swaps)"; [[ -z "$LIST" ]] && break
        while read -r dev; do
          [[ -z "$dev" ]] && continue
          swapoff "$dev" >/dev/null 2>&1 || true
          case "$dev" in /dev/*) : ;; *) rm -f "$dev" 2>/dev/null || true ;; esac
        done <<< "$LIST"
        sleep 1
      done
      rm -f /swapfile /swapfile-* /swap.emerg 2>/dev/null || true
      create_single_swapfile
      normalize_fstab_to_single
    fi
  fi

  log "当前活动 swap："; ( swapon --show || echo "  (none)" ) 2>/dev/null | sed 's/^/  /' || true
fi

# ====== 磁盘 TRIM ======
title "🪶 磁盘优化" "执行 fstrim 提升性能"
ensure_cmd fstrim util-linux util-linux
if has_cmd fstrim; then
  NI "fstrim -av >/dev/null 2>&1 || true"
  ok "fstrim 完成"
else
  warn "未检测到 fstrim，已跳过"
fi

# ====== 汇总 & 定时 ======
title "📊 汇总报告" "展示清理后资源状态"
df -h / 2>/dev/null | sed 's/^/  /' || true
free -h 2>/dev/null | sed 's/^/  /' || true
ok "极简深度清理完成 ✅"

title "⏰ 自动任务" "每日凌晨 03:00 自动运行"
chmod +x /root/deep-clean.sh

ensure_cron
if has_cmd crontab; then
  ( crontab -u root -l 2>/dev/null | grep -v 'deep-clean.sh' || true
    echo "0 3 * * * /bin/bash /root/deep-clean.sh >/dev/null 2>&1"
  ) | crontab -u root -
  ok "已设置每日 03:00 自动清理"
else
  warn "crontab 不可用：已跳过自动任务设置（可手动安装 cron/cronie 后再运行一次脚本）"
fi
EOF

chmod +x "$SCRIPT_PATH"
bash "$SCRIPT_PATH"
