#!/usr/bin/env bash
# ubuntu-setup.sh — One-shot Ubuntu environment setup
# 適用：Ubuntu 22.04 / 24.04
# 使用：sudo bash ubuntu-setup.sh

set -euo pipefail

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
info()  { echo -e "${GREEN}[INFO]${NC}  $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error() { echo -e "${RED}[ERR]${NC}   $*"; exit 1; }

[[ $EUID -ne 0 ]] && error "請用 sudo 執行：sudo bash ubuntu-setup.sh"

info "更新套件清單..."
apt-get update -qq && apt-get upgrade -y -qq

info "[1/9] 基礎工具..."
apt-get install -y -qq curl wget git unzip zip build-essential cmake pkg-config \
    ca-certificates gnupg lsb-release software-properties-common apt-transport-https tree jq rsync

info "[2/9] 終端工具..."
apt-get install -y -qq tmux btop htop ncdu mc fzf

info "[3/9] 網路工具..."
apt-get install -y -qq iperf3 nmap net-tools mtr dnsutils ncat traceroute

info "[4/9] Python..."
apt-get install -y -qq python3 python3-pip python3-venv python3-dev python3-full
# Ubuntu 24.04+ PEP 668：pipx 改用 apt 安裝
apt-get install -y -qq pipx
pipx ensurepath

info "[5/9] Node.js (nvm)..."
export NVM_DIR="/opt/nvm"
mkdir -p "$NVM_DIR"
curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh | \
    NVM_DIR="$NVM_DIR" bash > /dev/null 2>&1
source "$NVM_DIR/nvm.sh"
nvm install --lts --quiet && nvm alias default node
cat > /etc/profile.d/nvm.sh << 'EOF'
export NVM_DIR="/opt/nvm"
[ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"
EOF
chmod +x /etc/profile.d/nvm.sh

info "[6/9] VS Code..."
if ! command -v code &>/dev/null; then
    wget -qO /tmp/vscode.deb "https://code.visualstudio.com/sha/download?build=stable&os=linux-deb-x64"
    apt-get install -y /tmp/vscode.deb -qq && rm /tmp/vscode.deb
fi

info "[7/9] OpenCode..."
if ! command -v opencode &>/dev/null; then
    curl -fsSL https://opencode.ai/install | bash > /dev/null 2>&1 || \
        warn "OpenCode 安裝失敗，請手動：https://opencode.ai"
fi

info "[8/9] Docker..."
if ! command -v docker &>/dev/null; then
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | \
        gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    chmod a+r /etc/apt/keyrings/docker.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" \
        > /etc/apt/sources.list.d/docker.list
    apt-get update -qq
    apt-get install -y -qq docker-ce docker-ce-cli containerd.io \
        docker-buildx-plugin docker-compose-plugin
    usermod -aG docker "${SUDO_USER:-$USER}" || true
fi

info "[9/9] 安全 & 遠端..."
apt-get install -y -qq ufw fail2ban openssh-server
ufw allow ssh > /dev/null 2>&1 || true
warn "UFW 尚未啟用，確認 SSH 可連後：sudo ufw enable"

# 選用：xrdp（有桌面才裝）
if dpkg -l ubuntu-desktop &>/dev/null 2>&1 || dpkg -l xfce4 &>/dev/null 2>&1; then
    apt-get install -y -qq xrdp && systemctl enable xrdp --quiet
    usermod -aG ssl-cert xrdp
fi

# 選用：nvtop（有 NVIDIA 才裝）
lspci | grep -qi nvidia && apt-get install -y -qq nvtop || true

# ffmpeg
apt-get install -y -qq ffmpeg

apt-get autoremove -y -qq && apt-get autoclean -qq

echo -e "\n${GREEN}===== 安裝完成！=====${NC}\n"
for cmd in git python3 node npm code docker tmux btop ncdu fzf iperf3 nmap ffmpeg; do
    command -v $cmd &>/dev/null \
        && echo -e "  ${GREEN}✓${NC} $cmd — $(${cmd} --version 2>/dev/null | head -1)" \
        || echo -e "  ${YELLOW}?${NC} $cmd — 未安裝或需重新登入"
done
echo -e "\n注意：Docker 群組 & nvm 需重新登入後生效\n"
