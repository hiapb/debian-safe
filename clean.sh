#!/usr/bin/env bash
# =====================================================================
# Nuro Deep Clean — 1日保留 · 极限深度版（宝塔友好）
# 目标：日志/缓存/容器/包管理/构建产物/大文件/交换分区/页缓存/SSD TRIM
# 作者：hiapb + chatgpt
# =====================================================================

set -Eeuo pipefail
IFS=$'\n\t'

### ===== 固定为深度清理（保留1天） =====
KEEP_DAYS="${KEEP_DAYS:-1}"             # 日志、临时文件保留天数（固定默认 1）
LARGE_FILE_MIN="${LARGE_FILE_MIN:-50M}" # 大文件阈值（深度版默认 50M）
DRY_RUN="${DRY_RUN:-0}"                 # 1 只演练；0 真删除
AGGRESSIVE="${AGGRESSIVE:-1}"           # 1 开启极限清理项；0 关闭
KILL_TOP_CPU="${KILL_TOP_CPU:-0}"       # 1 处置高CPU后台进程（谨慎）；0 不处置
RESTART_LEAKY_SERVICES="${RESTART_LEAKY_SERVICES:-0}" # 1 重启占用已删文件的服务（释放空间）

CRON_TIME="${CRON_TIME:-0 3 * * *}"     # 每日 3:00
SCRIPT_PATH="/root/deep-clean.sh"
LOG_FILE="${LOG_FILE:-/var/log/deep-clean-report.log}"

SAFE_DIRS=(                               # 只在这些路径做大规模删
  "/tmp" "/var/tmp" "/var/cache" "/var/backups"
  "/root/.cache" "/home" "/www/server/backup" "/root/Downloads"
)
# 永久排除（保护）
EXCLUDE_PRUNES=(
  "/www/server/panel"
  "/www/wwwlogs"
  "/var/lib/mysql" "/var/lib/mariadb" "/var/lib/postgresql"
  "/var/lib/docker/volumes"
  "/var/snap"
)

ts(){ date "+%F %T"; }
say(){ echo -e "[$(ts)] $*"; }
run(){ if [[ "$DRY_RUN" = "1" ]]; then say "DRY-RUN: $*"; else eval "$@"; fi; }

require_root(){ [[ $EUID -eq 0 ]] || { echo "需要 root 权限"; exit 1; }; }
trap 'say "❌ 出错: 行 $LINENO"; exit 1' ERR

require_root
LANG=C
say "🧹 [Deep Clean] KEEP_DAYS=$KEEP_DAYS LARGE_FILE_MIN=$LARGE_FILE_MIN DRY_RUN=$DRY_RUN AGGRESSIVE=$AGGRESSIVE"

echo "===== 清理前系统信息 =====" | tee -a "$LOG_FILE"
uname -a | tee -a "$LOG_FILE"
df -h /  | tee -a "$LOG_FILE"
free -h  | tee -a "$LOG_FILE"
echo "--------------------------------------" | tee -a "$LOG_FILE"

# 方便复用：拼装 -prune 片段
prunes() {
  local expr=""
  for p in "${EXCLUDE_PRUNES[@]}"; do
    expr="${expr} -path '$p/*' -prune -o"
  done
  echo "$expr"
}

### 1) 系统日志：时间 + 尺寸双控（保留1天 + 压到50M）
say "🧾 清理系统日志..."
# /var/log 普通文件（避开宝塔/站点日志）
run "find /var/log \\( -path '/www/server/panel/logs/*' -o -path '/www/wwwlogs/*' \\) -prune -o \
  -type f \\( -name '*.log' -o -name '*.old' -o -name '*.gz' -o -name '*.1' \\) \
  -mtime +$KEEP_DAYS -exec truncate -s 0 {} + 2>/dev/null || true"
# systemd-journal
journalctl --rotate || true
journalctl --vacuum-time='1d' || true
journalctl --vacuum-size='50M' || true
# 登录类日志置空
: > /var/log/wtmp  || true
: > /var/log/btmp  || true
: > /var/log/lastlog || true
: > /var/log/faillog || true
# coredump & crash
run "rm -rf /var/lib/systemd/coredump/* /var/crash/* 2>/dev/null || true"

### 2) 临时目录 & tmpfiles（>1天）
say "🧼 清理 /tmp /var/tmp ..."
run "find /tmp -xdev -type f -atime +$KEEP_DAYS -delete 2>/dev/null || true"
run "find /var/tmp -xdev -type f -atime +$KEEP_DAYS -delete 2>/dev/null || true"
command -v systemd-tmpfiles >/dev/null 2>&1 && run "systemd-tmpfiles --clean"

### 3) 包管理缓存/孤包/残配置
if command -v apt-get >/dev/null 2>&1; then
  say "📦 APT 缓存/孤包/残配置..."
  run "apt-get -y autoremove >/dev/null 2>&1 || true"
  run "apt-get -y autoclean  >/dev/null 2>&1 || true"
  run "apt-get -y clean      >/dev/null 2>&1 || true"
  # 残留配置（rc 状态包）
  run "dpkg -l | awk '/^rc/{print \$2}' | xargs -r dpkg -P >/dev/null 2>&1 || true"
  # 列表 & 部分下载
  run "rm -rf /var/cache/apt/archives/*.deb /var/cache/apt/archives/partial/* /var/lib/apt/lists/* 2>/dev/null || true"
fi

# snap & flatpak
if command -v snap >/dev/null 2>&1; then
  say "🫧 snap 旧版本..."
  if [[ "$DRY_RUN" = "1" ]]; then
    snap list --all | awk '/disabled/{print \"DRY-RUN snap remove\",$1,$3}'
  else
    snap list --all | awk '/disabled/{print $1,$3}' | xargs -r -n2 snap remove || true
  fi
fi
if command -v flatpak >/dev/null 2>&1; then
  say "📦 flatpak 清理未使用 runtime..."
  run "flatpak uninstall --unused -y || true"
fi

### 4) 用户 & 开发缓存
say "👤 用户缓存/构建产物..."
run "rm -rf /root/.cache/* 2>/dev/null || true"
for udir in /home/*; do
  [[ -d \"$udir/.cache\" ]] && run \"rm -rf '$udir/.cache/'* 2>/dev/null || true\"
  # 回收垃圾桶
  [[ -d \"$udir/.local/share/Trash\" ]] && run \"rm -rf '$udir/.local/share/Trash/'* 2>/dev/null || true\"
done
# 语言/包管理器缓存
command -v pip >/dev/null 2>&1      && run "pip cache purge || true"
command -v npm >/dev/null 2>&1      && run "npm cache clean --force || true"
command -v yarn >/dev/null 2>&1     && run "yarn cache clean || true"
command -v composer >/dev/null 2>&1 && run "composer clear-cache || true"
command -v gem >/dev/null 2>&1      && run "gem cleanup -q || true"
[[ -d /root/.conda/pkgs ]]          && run "find /root/.conda/pkgs -type f -mtime +$KEEP_DAYS -delete || true"
# Python __pycache__、前端产物（dist/build）>1天
run "find / -xdev \\( -path '/proc/*' -o -path '/sys/*' -o -path '/dev/*' \\) -prune -o \
  -type d \\( -name '__pycache__' -o -name 'dist' -o -name 'build' -o -name '.turbo' -o -name '.next' \\) \
  -mtime +$KEEP_DAYS -exec rm -rf {} + 2>/dev/null || true"

### 5) Docker / 容器（重度）
if command -v docker >/dev/null 2>&1; then
  say "🐳 Docker 深度清理..."
  run "docker container prune -f --filter 'until=${KEEP_DAYS}d' >/dev/null 2>&1 || true"
  run "docker image prune -af --filter 'until=168h' >/dev/null 2>&1 || true"
  run "docker volume prune -f >/dev/null 2>&1 || true"
  run "docker network prune -f >/dev/null 2>&1 || true"
  run "docker builder prune -af --filter 'until=168h' >/dev/null 2>&1 || true"
  run "docker system prune -af --volumes >/dev/null 2>&1 || true"
fi
command -v ctr >/dev/null 2>&1     && run "ctr -n k8s.io images prune || true"
command -v podman >/dev/null 2>&1  && run "podman system prune -af || true"

### 6) 旧内核（保留当前+最新一个）
say "🧯 旧内核清理..."
if command -v dpkg >/dev/null 2>&1; then
  CURK=\"$(uname -r)\"
  mapfile -t kernels < <(dpkg -l | awk '/linux-image-[0-9]/{print $2}' | sort -V)
  keep=(\"linux-image-${CURK}\")
  latest=\"$(printf \"%s\n\" \"${kernels[@]}\" | grep -v \"$CURK\" | tail -n1 || true)\"
  [[ -n \"$latest\" ]] && keep+=(\"$latest\")
  purge=()
  for k in \"${kernels[@]}\"; do
    skip=0; for kk in \"${keep[@]}\"; do [[ \"$k\" == \"$kk\" ]] && skip=1; done
    [[ $skip -eq 0 ]] && purge+=(\"$k\")
  done
  ((${#purge[@]})) && run \"apt-get -y purge ${purge[*]} >/dev/null 2>&1 || true\" || say \"无可移除旧内核\"
fi

### 7) 备份/下载/大文件（白名单 + 极限项）
say "🗂️ 备份/下载/大文件..."
run "rm -rf /www/server/backup/* 2>/dev/null || true"
run "rm -rf /home/*/Downloads/* /root/Downloads/* 2>/dev/null || true"

# 大文件（只在 SAFE_DIRS；排除关键路径）
for base in "${SAFE_DIRS[@]}"; do
  [[ -d "$base" ]] || continue
  say "扫描大文件: $base (> $LARGE_FILE_MIN)"
  if [[ "$DRY_RUN" = "1" ]]; then
    find "$base" -xdev \( $(for e in "${EXCLUDE_PRUNES[@]}"; do printf -- "-path %q -prune -o " "$e/*"; done) -false \) -o \
      -type f -size +"$LARGE_FILE_MIN" -printf "DRY-RUN: %p (%k KB)\n"
  else
    find "$base" -xdev \( $(for e in "${EXCLUDE_PRUNES[@]}"; do printf -- "-path %q -prune -o " "$e/*"; done) -false \) -o \
      -type f -size +"$LARGE_FILE_MIN" -delete 2>/dev/null || true
  fi
done

# 压缩/备份包（全盘但排除关键路径）
run "find / -xdev \( -path '/proc/*' -o -path '/sys/*' -o -path '/dev/*' $(for e in "${EXCLUDE_PRUNES[@]}"; do printf " -o -path '%s/*'" "$e"; done) \) -prune -o \
  -type f \( -name '*.zip' -o -name '*.tar.gz' -o -name '*.tgz' -o -name '*.bak' \) -size +${LARGE_FILE_MIN} -delete 2>/dev/null || true"

### 8) 释放内存/交换/页缓存（CPU/内存“洗一遍”）
say "🧠 内存/缓存整理..."
# 清脏页
sync
# 严格清缓存（cache + dentries + inodes）
echo 3 > /proc/sys/vm/drop_caches || true
# 若在用 swap，复位一遍（更干净）
if awk '/SwapTotal/{t=$2}/SwapFree/{f=$2} END{exit (t-f)<1024*1024?1:0}' /proc/meminfo; then
  say "♻️ 重置 swap（swapoff→swapon）..."
  run "swapoff -a || true"
  run "swapon -a || true"
fi
# 内存压缩/合并（如果内核支持）
[[ -w /sys/kernel/mm/transparent_hugepage/enabled ]] && echo always > /sys/kernel/mm/transparent_hugepage/enabled || true
[[ -w /sys/kernel/mm/transparent_hugepage/defrag  ]] && echo always > /sys/kernel/mm/transparent_hugepage/defrag  || true

### 9) SSD 空间回收（TRIM）
if command -v fstrim >/dev/null 2>&1; then
  say "✂️  SSD TRIM..."
  run "fstrim -av || true"
fi

### 10) 可选：处置高CPU后台进程（默认关闭）
if [[ "$KILL_TOP_CPU" = "1" ]]; then
  say "🛑 处置高CPU进程（> 85%）..."
  # 允许名单（不杀）：sshd、systemd、dockerd、mysqld、postgres、nginx、bt(宝塔)
  SAFE_PATS='(sshd|systemd|dockerd|containerd|mysqld|postgres|nginx|bt|redis|php-fpm|journald)'
  mapfile -t HOT < <(ps -eo pid,pcpu,comm --sort=-pcpu | awk 'NR>1 && $2>85 {print $1":"$2":"$3}' | head -n 5)
  for row in "${HOT[@]}"; do
    pid="${row%%:*}"; rest="${row#*:}"; cpu="${rest%%:*}"; name="${row##*:}"
    if [[ "$name" =~ $SAFE_PATS ]]; then
      say "跳过 $name($pid) $cpu%"
    else
      say "kill -TERM $name($pid) $cpu%"
      run "kill -TERM $pid || true"
    fi
  done
fi

### 11) 可选：释放“已删除但仍被占用”的空间（默认关闭）
if [[ "$RESTART_LEAKY_SERVICES" = "1" ]]; then
  say "🔁 重启可能握着已删文件句柄的服务..."
  # 找出 (deleted) 句柄
  lsof +L1 2>/dev/null | awk 'NR>1 {print $1}' | sort -u | head -n 20 | while read -r svc; do
    case "$svc" in
      rsyslogd|journald|nginx|php-fpm|node|java|python|gunicorn|uwsgi)
        say "systemctl restart $svc"
        run "systemctl restart $svc || true"
        ;;
    esac
  done
fi

### 12) 结果
echo -e "\n===== 清理完成 =====" | tee -a "$LOG_FILE"
df -h / | tee -a "$LOG_FILE"
free -h | tee -a "$LOG_FILE"

### 13) 诊断：最大空间占用 Top（方便你复查）
{
  echo -e "\n--- Top 目录占用（根目录层） ---"
  du -xh --max-depth=1 / 2>/dev/null | sort -h | tail -n 20
  echo -e "\n--- /var 层 ---"
  du -xh --max-depth=1 /var 2>/dev/null | sort -h | tail -n 20
} | tee -a "$LOG_FILE"

### 14) 写入 cron（去重）
say "⏰ 安装每日 ${CRON_TIME} 定时任务..."
chmod +x "$SCRIPT_PATH"
CRON_JOB="${CRON_TIME} /bin/bash ${
