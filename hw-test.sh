#!/usr/bin/env bash
# hw-test.sh — Ubuntu 硬體健康診斷
# 使用：sudo bash hw-test.sh

set -euo pipefail
[[ $EUID -ne 0 ]] && { echo "請用 sudo 執行"; exit 1; }

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
LOG="/tmp/hw-test-$(date +%Y%m%d-%H%M).log"
CORES=$(nproc)

info() { echo -e "${GREEN}[INFO]${NC}  $*" | tee -a "$LOG"; }
warn() { echo -e "${YELLOW}[WARN]${NC}  $*" | tee -a "$LOG"; }

info "===== 硬體測試開始 $(date) ====="
info "記錄檔：$LOG  |  CPU 核心：${CORES}"
echo "" >> "$LOG"

# ── 安裝工具 ────────────────────────────────────────────
info "安裝測試工具..."
apt-get install -y -qq stress-ng sysbench memtester fio hdparm \
    smartmontools lm-sensors inxi speedtest-cli 2>/dev/null || true

# ── 1. 系統資訊 ─────────────────────────────────────────
info "=== [1/7] 系統資訊 ==="
{ lscpu | grep -E "Model name|Socket|Core|Thread|MHz|Cache"
  echo "---"
  dmidecode --type memory 2>/dev/null | grep -E "Size|Speed|Type:|Locator" | grep -v "No Module" || true
  echo "---"
  dmidecode --type baseboard 2>/dev/null | grep -E "Manufacturer|Product" || true
  echo "---"
  lspci | grep -E "VGA|3D|NVMe|SATA|Ethernet"
  echo "---"
  lsblk -o NAME,SIZE,TYPE,MOUNTPOINT,MODEL
} | tee -a "$LOG"
echo "" >> "$LOG"

# ── 2. CPU ──────────────────────────────────────────────
info "=== [2/7] CPU 基準測試 ==="
sysbench cpu --cpu-max-prime=10000 --threads="$CORES" run 2>&1 | \
    grep -E "events per second|total time|min|max|avg" | tee -a "$LOG"
info "CPU 壓力 60 秒..."
stress-ng --cpu "$CORES" --timeout 60 --metrics-brief 2>&1 | tail -5 | tee -a "$LOG"
echo "" >> "$LOG"

# ── 3. RAM ──────────────────────────────────────────────
info "=== [3/7] RAM 測試 ==="
AVAIL=$(free -m | awk '/^Mem:/{print int($7 * 0.6)}')
[[ $AVAIL -lt 256 ]] && AVAIL=256
info "測試容量：${AVAIL}MB"
memtester "${AVAIL}M" 1 2>&1 | grep -E "ok|FAILED" | tail -10 | tee -a "$LOG"
echo "" >> "$LOG"

# ── 4. 磁碟 SMART ───────────────────────────────────────
info "=== [4/7] 磁碟 SMART ==="
smartctl --scan 2>/dev/null | awk '{print $1}' | while read -r dev; do
    echo "  $dev: $(smartctl -H "$dev" 2>/dev/null | grep -E 'PASSED|FAILED|result' | tail -1)" | tee -a "$LOG"
    smartctl -A "$dev" 2>/dev/null | \
        grep -E "Reallocated_Sector|Pending_Sector|Uncorrectable|Power_On_Hours|Temperature_Celsius" | \
        awk '{printf "    %-35s %s\n", $2, $10}' | tee -a "$LOG" || true
done
echo "" >> "$LOG"

# ── 5. 磁碟速度 ─────────────────────────────────────────
info "=== [5/7] 磁碟速度 (fio) ==="
FIO_FILE="/tmp/fio_hwtest_$$"
echo "  循序讀取..." | tee -a "$LOG"
fio --name=r --rw=read  --direct=1 --bs=1M --size=512M --numjobs=1 --runtime=15 \
    --group_reporting --filename="$FIO_FILE" 2>&1 | grep "READ:" | tee -a "$LOG"
echo "  循序寫入..." | tee -a "$LOG"
fio --name=w --rw=write --direct=1 --bs=1M --size=512M --numjobs=1 --runtime=15 \
    --group_reporting --filename="$FIO_FILE" 2>&1 | grep "WRITE:" | tee -a "$LOG"
echo "  隨機 4K IOPS..." | tee -a "$LOG"
fio --name=rr --rw=randread --direct=1 --bs=4k --size=256M --numjobs=4 --runtime=15 \
    --group_reporting --filename="$FIO_FILE" 2>&1 | grep "READ:" | tee -a "$LOG"
rm -f "$FIO_FILE"
echo "" >> "$LOG"

# ── 6. 溫度 ────────────────────────────────────────────
info "=== [6/7] 溫度 ==="
command -v sensors &>/dev/null \
    && sensors 2>/dev/null | grep -E "Core|temp|fan|Tctl" | tee -a "$LOG" \
    || warn "執行 sensors-detect --auto 後重試"
echo "" >> "$LOG"

# ── 7. GPU & 網路 ───────────────────────────────────────
info "=== [7/7] GPU & 網路 ==="
command -v nvidia-smi &>/dev/null && \
    nvidia-smi --query-gpu=name,temperature.gpu,utilization.gpu,memory.used,memory.total \
        --format=csv,noheader | tee -a "$LOG" || true
ip -o link show | awk '{print "  "$2, $9}' | grep -v lo | tee -a "$LOG"
command -v speedtest-cli &>/dev/null && \
    speedtest-cli --simple 2>/dev/null | tee -a "$LOG" || warn "speedtest-cli 未安裝"
echo "" >> "$LOG"

# ── 結果 ────────────────────────────────────────────────
echo ""
echo -e "${GREEN}========== 測試完成 ==========${NC}"
echo "記錄檔：$LOG"
echo ""
if grep -qiE "FAILED|UNCOR" "$LOG" 2>/dev/null; then
    echo -e "  ${RED}⚠ 發現問題，請查看記錄${NC}"
    grep -iE "FAILED|UNCOR" "$LOG" | sed 's/^/  /'
else
    echo -e "  ${GREEN}✓ 未發現明顯異常${NC}"
fi
echo ""
echo "判讀標準："
echo "  CPU 壓測溫度 < 85°C | RAM 無 FAILED | SMART PASSED"
echo "  NVMe 讀取 > 2000 MB/s | SATA SSD > 400 MB/s | HDD > 100 MB/s"
