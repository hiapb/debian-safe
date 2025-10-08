#!/usr/bin/env bash
# ======================================================================
# Nuro Deep Clean • Safe-Deep (Clean Output · Intelligent Swap · BT Safe)
# ======================================================================

set -e
SCRIPT_PATH="/root/deep-clean.sh"
echo "Writing script to ${SCRIPT_PATH} ..."

cat > "$SCRIPT_PATH" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

# ----------------------------- UI -----------------------------
line(){ printf '%s\n' '----------------------------------------------------------------'; }
sec(){ printf '\n== %s ==\n' "$1"; line; }
ok(){  printf 'OK: %s\n' "$*"; }
warn(){ printf 'WARN: %s\n' "$*"; }
fail(){ printf 'FAIL: %s\n' "$*"; }
trap 'fail "error at line $LINENO"; exit 1' ERR

# ---------------------- Strong Protection ---------------------
EXCLUDES=(
  "/www/server/panel" "/www/wwwlogs" "/www/wwwroot"
  "/www/server/nginx" "/www/server/apache" "/www/server/openresty"
  "/www/server/mysql" "/var/lib/mysql" "/var/lib/mariadb" "/var/lib/postgresql"
  "/www/server/php" "/etc/php" "/var/lib/php/sessions"
)
is_excluded(){ local p="$1"; for e in "${EXCLUDES[@]}"; do [[ "$p" == "$e"* ]] && return 0; done; return 1; }

# ------------------------ Quick Status ------------------------
sec "System Status (Before)"
uname -a
echo
echo "[Disk (/)]"
df -h /
echo
echo "[Memory]"
free -h
echo
echo "[Swap]"
{ swapon --show || true; } | sed 's/^/  /' || true
line

# -------------------- APT Locks (safe) -----------------------
sec "APT Locks"
pkill -9 -f 'apt|apt-get|dpkg|unattended-upgrade' 2>/dev/null || true
rm -f /var/lib/dpkg/lock* /var/cache/apt/archives/lock || true
dpkg --configure -a >/dev/null 2>&1 || true
ok "APT/dpkg locks handled"

# --------------------- Logs (keep 1 day) ---------------------
sec "Logs (keep 1 day; preserve structure)"
journalctl --rotate || true
journalctl --vacuum-time=1d --vacuum-size=64M >/dev/null 2>&1 || true
find /var/log -type f \
  -not -path "/www/server/panel/logs/*" -not -path "/www/wwwlogs/*" \
  -exec truncate -s 0 {} \; 2>/dev/null || true
: > /var/log/wtmp  || true
: > /var/log/btmp  || true
: > /var/log/lastlog || true
: > /var/log/faillog || true
ok "Logs cleaned"

# ---------------- Temp & Caches (safe) -----------------------
sec "Temp & Caches"
find /tmp -xdev -type f -atime +1 -not -name 'sess_*' -delete 2>/dev/null || true
find /var/tmp -xdev -type f -atime +1 -delete 2>/dev/null || true
find /tmp     -xdev -type f -size +50M -not -name 'sess_*' -delete 2>/dev/null || true
find /var/tmp -xdev -type f -size +50M -delete 2>/dev/null || true
find /var/cache -xdev -type f -mtime +1 -delete 2>/dev/null || true
rm -rf /var/crash/* /var/lib/systemd/coredump/* 2>/dev/null || true
ok "Temp & caches cleaned"

# -------------------- Package Caches -------------------------
sec "Package Caches (APT/Snap/Lang)"
if command -v apt-get >/dev/null 2>&1; then
  apt-get -y autoremove  >/dev/null 2>&1 || true
  apt-get -y autoclean   >/dev/null 2>&1 || true
  apt-get -y clean       >/dev/null 2>&1 || true
  dpkg -l | awk '/^rc/{print $2}' | xargs -r dpkg -P >/dev/null 2>&1 || true
fi
if command -v snap >/dev/null 2>&1; then
  snap list --all | awk '/disabled/{print $1, $3}' | xargs -r -n2 snap remove || true
fi
command -v pip >/dev/null      && pip cache purge >/dev/null 2>&1 || true
command -v npm >/dev/null      && npm cache clean --force >/devnull 2>&1 || true
command -v yarn >/dev/null     && yarn cache clean >/dev/null 2>&1 || true
command -v composer >/dev/null && composer clear-cache >/dev/null 2>&1 || true
command -v gem >/dev/null      && gem cleanup -q >/dev/null 2>&1 || true
ok "Package caches cleaned"

# --------------------- Containers Clean ----------------------
sec "Containers (Docker/containerd)"
if command -v docker >/dev/null 2>&1; then
  docker builder prune -af >/dev/null 2>&1 || true
  docker image   prune -af --filter 'until=168h' >/dev/null 2>&1 || true
  docker container prune -f --filter 'until=24h' >/dev/null 2>&1 || true
  docker volume  prune -f >/dev/null 2>&1 || true
  docker network prune -f >/dev/null 2>&1 || true
  docker system  prune -af --volumes >/dev/null 2>&1 || true
fi
command -v ctr >/dev/null 2>&1 && ctr -n k8s.io images prune >/dev/null 2>&1 || true
ok "Containers cleaned"

# ------------- Backups & All Downloads (wipe) ---------------
sec "Backups & User Downloads (wipe all)"
[[ -d /www/server/backup ]] && rm -rf /www/server/backup/* 2>/dev/null || true
[[ -d /root/Downloads    ]] && rm -rf /root/Downloads/* 2>/dev/null || true
for d in /home/*/Downloads; do [[ -d "$d" ]] && rm -rf "$d"/* 2>/dev/null || true; done
# common archives in home dirs
for base in /root /home/*; do
  [[ -d "$base" ]] || continue
  find "$base" -type f \( -name "*.zip" -o -name "*.tar.gz" -o -name "*.tgz" -o -name "*.rar" -o -name "*.7z" -o -name "*.bak" \) -delete 2>/dev/null || true
done
ok "Backups & Downloads wiped"

# --------------- Large files (safe paths) -------------------
sec "Large Files Sweep (>100MB, safe paths)"
SAFE_BASES=(/tmp /var/tmp /var/cache /var/backups /root /home /www/server/backup)
for base in "${SAFE_BASES[@]}"; do
  [[ -d "$base" ]] || continue
  while IFS= read -r -d '' f; do
    is_excluded "$f" && continue
    rm -f "$f" 2>/dev/null || true
  done < <(find "$base" -xdev -type f -size +100M -print0 2>/dev/null)
done
ok "Large files removed"

# --------------------- Old Kernels ---------------------------
sec "Old Kernels (keep current + latest)"
if command -v dpkg >/dev/null 2>&1; then
  CURK="$(uname -r)"
  mapfile -t KS < <(dpkg -l | awk '/linux-image-[0-9]/{print $2}' | sort -V)
  KEEP=("linux-image-${CURK}")
  LATEST="$(printf "%s\n" "${KS[@]}" | grep -v "$CURK" | tail -n1 || true)"
  [[ -n "${LATEST:-}" ]] && KEEP+=("$LATEST")
  PURGE=(); for k in "${KS[@]}"; do [[ " ${KEEP[*]} " == *" $k "* ]] || PURGE+=("$k"); done
  ((${#PURGE[@]})) && apt-get -y purge "${PURGE[@]}" >/dev/null 2>&1 || true
fi
ok "Kernel cleanup done"

# ----------------- Memory/CPU (safe mode) -------------------
sec "Memory/CPU (safe)"
# Only do light cache drop when load low and MemAvailable >=30%
LOAD1_INT=$(awk '{printf "%d",$1}' /proc/loadavg)
MEM_AVAIL_KB=$(awk '/MemAvailable/{print $2}' /proc/meminfo)
MEM_TOTAL_KB=$(awk '/MemTotal/{print $2}' /proc/meminfo)
MEM_AVAIL_PCT=$(( MEM_AVAIL_KB*100 / MEM_TOTAL_KB ))
if (( LOAD1_INT <= 2 && MEM_AVAIL_PCT >= 30 )); then
  sync
  echo 1 > /proc/sys/vm/drop_caches || true
  [[ -w /proc/sys/vm/compact_memory ]] && echo 1 > /proc/sys/vm/compact_memory || true
  ok "Light cache drop done (Load1=${LOAD1_INT}, MemAvail=${MEM_AVAIL_PCT}%)"
else
  warn "Skipped (Load1=${LOAD1_INT}, MemAvail=${MEM_AVAIL_PCT}%)"
fi

# ---------------- Intelligent Swap (SAFE) -------------------
sec "Swap (intelligent; non-disruptive)"
# If swap exists, keep it (no swapoff). If not, create new file swap.
has_active_swap(){ grep -q ' swap ' /proc/swaps 2>/dev/null; }
calc_target_mib(){
  local mem_mib avail_mib target maxsafe
  mem_mib=$(awk '/MemTotal/ {printf "%.0f",$2/1024}' /proc/meminfo)        # MiB
  target=$(( mem_mib / 2 ))                                                # half RAM
  (( target < 256 ))  && target=256
  (( target > 2048 )) && target=2048
  avail_mib=$(df -Pm / | awk 'NR==2{print $4}')                             # MiB
  maxsafe=$(( avail_mib * 75 / 100 ))                                       # keep >=25% free
  (( target > maxsafe )) && target=$maxsafe
  echo "$target"
}
mk_swapfile(){
  local path="$1" size="$2"
  [[ -z "$size" || "$size" -lt 128 ]] && { warn "Insufficient disk to create swap"; return 1; }
  local fs; fs=$(stat -f -c %T / 2>/dev/null || echo "")
  if [[ "$fs" == "btrfs" ]]; then
    touch "$path"
    chattr +C "$path" 2>/dev/null || true
  fi
  if ! fallocate -l ${size}M "$path" 2>/dev/null; then
    dd if=/dev/zero of="$path" bs=1M count=${size} status=none conv=fsync
  fi
  chmod 600 "$path"
  mkswap "$path" >/dev/null
  swapon "$path"
  sed -i '\|/swapfile|d' /etc/fstab 2>/dev/null || true
  echo "$path none swap sw 0 0" >> /etc/fstab
  ok "Swap enabled: $path (${size}MiB)"
}

if has_active_swap; then
  ok "Swap already active; leaving as-is"
else
  TARGET=$(calc_target_mib)
  if [[ -n "$TARGET" && "$TARGET" -ge 128 ]]; then
    if ! mk_swapfile "/swapfile" "$TARGET"; then
      TS=$(date +%s)
      mk_swapfile "/swapfile-${TS}" "$TARGET" || warn "Failed to add file swap; consider zram"
    fi
  else
    warn "Disk too low to create swap; skipping"
  fi
fi

# ---------------------- Disk TRIM ----------------------------
sec "Disk Optimize (TRIM if available)"
if command -v fstrim >/dev/null 2>&1; then
  fstrim -av >/dev/null 2>&1 || true
  ok "TRIM done"
else
  warn "fstrim not available"
fi

# ---------------------- Final Summary -----------------------
sec "System Status (After)"
echo "[Disk (/)]"; df -h /
echo
echo "[Memory]"; free -h
echo
echo "[Swap]"; { swapon --show || true; } | sed 's/^/  /' || true
ok "Deep clean finished"

# ----------------------- Cron daily -------------------------
sec "Cron"
chmod +x /root/deep-clean.sh
( crontab -u root -l 2>/dev/null | grep -v 'deep-clean.sh' || true; echo "0 3 * * * /bin/bash /root/deep-clean.sh >/dev/null 2>&1" ) | crontab -u root -
ok "Scheduled daily at 03:00"
EOF

chmod +x "$SCRIPT_PATH"
bash "$SCRIPT_PATH"
