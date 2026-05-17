#!/usr/bin/env bash
# hw-test.sh - Ubuntu Hardware Diagnostic
# Usage: sudo bash hw-test.sh

set -euo pipefail
[[ $EUID -ne 0 ]] && { echo "Please run with sudo"; exit 1; }

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
LOG="/tmp/hw-test-$(date +%Y%m%d-%H%M).log"
CORES=$(nproc)

info() { echo -e "${GREEN}[INFO]${NC}  $*" | tee -a "$LOG"; }
warn() { echo -e "${YELLOW}[WARN]${NC}  $*" | tee -a "$LOG"; }

info "===== Hardware Test Start: $(date) ====="
info "Log: $LOG  |  CPU Cores: ${CORES}"
echo "" >> "$LOG"

info "Installing test tools..."
apt-get install -y -qq stress-ng sysbench memtester fio hdparm smartmontools lm-sensors inxi 2>/dev/null || true

info "=== [1/7] System Info ==="
{ echo "--- CPU ---"; lscpu | grep -E "Model name|Socket|Core|Thread|MHz|Cache"
  echo "--- RAM ---"; dmidecode --type memory 2>/dev/null | grep -E "Size|Speed|Type:|Locator" | grep -v "No Module" || true
  echo "--- Board ---"; dmidecode --type baseboard 2>/dev/null | grep -E "Manufacturer|Product" || true
  echo "--- PCI ---"; lspci | grep -E "VGA|3D|NVMe|SATA|Ethernet"
  echo "--- Disks ---"; lsblk -o NAME,SIZE,TYPE,MOUNTPOINT,MODEL
} | tee -a "$LOG"
echo "" >> "$LOG"

info "=== [2/7] CPU Benchmark (${CORES} cores) ==="
sysbench cpu --cpu-max-prime=10000 --threads="$CORES" run 2>&1 | grep -E "events per second|total time|min|max|avg" | tee -a "$LOG"
info "CPU stress 60s..."
stress-ng --cpu "$CORES" --timeout 60 --metrics-brief 2>&1 | tail -5 | tee -a "$LOG"
echo "" >> "$LOG"

info "=== [3/7] RAM Quick Test (256MB ~1-2min) ==="
warn "For full RAM test: use memtest86+ bootable USB"
memtester 256M 1 2>&1 | grep -E "ok|FAILED" | tail -10 | tee -a "$LOG"
echo "" >> "$LOG"

info "=== [4/7] Disk SMART Health ==="
smartctl --scan 2>/dev/null | awk '{print $1}' | while read -r dev; do
    echo "  $dev: $(smartctl -H "$dev" 2>/dev/null | grep -E 'PASSED|FAILED|result' | tail -1)" | tee -a "$LOG"
    smartctl -A "$dev" 2>/dev/null | grep -E "Reallocated_Sector|Pending_Sector|Uncorrectable|Power_On_Hours|Temperature_Celsius" | awk '{printf "    %-35s %s\n", $2, $10}' | tee -a "$LOG" || true
done
echo "" >> "$LOG"

info "=== [5/7] Disk Speed (fio) ==="
FIO_FILE="/tmp/fio_hwtest_$$"
echo "  Sequential Read..." | tee -a "$LOG"
fio --name=r --rw=read  --direct=1 --bs=1M --size=512M --numjobs=1 --runtime=15 --group_reporting --filename="$FIO_FILE" 2>&1 | grep "READ:" | tee -a "$LOG"
echo "  Sequential Write..." | tee -a "$LOG"
fio --name=w --rw=write --direct=1 --bs=1M --size=512M --numjobs=1 --runtime=15 --group_reporting --filename="$FIO_FILE" 2>&1 | grep "WRITE:" | tee -a "$LOG"
echo "  Random 4K IOPS..." | tee -a "$LOG"
fio --name=rr --rw=randread --direct=1 --bs=4k --size=256M --numjobs=4 --runtime=15 --group_reporting --filename="$FIO_FILE" 2>&1 | grep "READ:" | tee -a "$LOG"
rm -f "$FIO_FILE"
echo "" >> "$LOG"

info "=== [6/7] Temperature ==="
command -v sensors &>/dev/null && sensors 2>/dev/null | grep -E "Core|temp|fan|Tctl" | tee -a "$LOG" || warn "Run: sensors-detect --auto"
echo "" >> "$LOG"

info "=== [7/7] GPU & Network ==="
command -v nvidia-smi &>/dev/null && nvidia-smi --query-gpu=name,temperature.gpu,utilization.gpu,memory.used,memory.total --format=csv,noheader | tee -a "$LOG" || true
ip -o link show | awk '{print "  "$2, $9}' | grep -v lo | tee -a "$LOG"
echo "" >> "$LOG"

echo ""; echo -e "${GREEN}========== Test Complete ==========${NC}"; echo "Log: $LOG"; echo ""
# 排除 stress-ng "failed: 0"（0 代表沒問題）及 grep 自身輸出
ISSUES=$(grep -iE "FAILED|UNCOR" "$LOG" 2>/dev/null | grep -v "failed: 0" | grep -v "^$" || true)
if [[ -n "$ISSUES" ]]; then
    echo -e "  ${RED}Warning: Issues found${NC}"
    echo "$ISSUES" | sed 's/^/  /'
else
    echo -e "  ${GREEN}OK: No obvious issues${NC}"
fi
echo ""; echo "Reference: CPU<85C | RAM no FAILED | SMART PASSED | NVMe>2000 SATA>400 HDD>100 MB/s"