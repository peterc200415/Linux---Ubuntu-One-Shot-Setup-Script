# Linux - Ubuntu One-Shot Setup Script

Ubuntu 22.04 / 24.04 一鍵初始化 & 硬體測試腳本。

## 使用方式

```bash
git clone https://github.com/peterc200415/Linux---Ubuntu-One-Shot-Setup-Script.git ~/scripts
cd ~/scripts

# 初始化環境
sudo bash ubuntu-setup.sh

# 硬體測試
sudo bash hw-test.sh
```

## ubuntu-setup.sh 安裝清單

| 類別 | 軟體 |
|------|------|
| 基礎 | git, curl, wget, build-essential, cmake, jq, rsync |
| 終端 | tmux, btop, htop, ncdu, mc, fzf |
| 網路 | iperf3, nmap, net-tools, mtr, dnsutils, ncat |
| Python | python3, pip3, venv, pipx |
| Node.js | nvm + Node LTS |
| 編輯器 | VS Code |
| AI 工具 | OpenCode |
| 容器 | Docker CE + Compose Plugin |
| 安全 | ufw, fail2ban, openssh-server |
| 選用 | xrdp（桌面）、nvtop（NVIDIA）、ffmpeg |

## hw-test.sh 測試項目

| 項目 | 工具 |
|------|------|
| 系統資訊 | lscpu, dmidecode, lspci, lsblk |
| CPU 基準 + 壓力 | sysbench, stress-ng |
| RAM | memtester |
| 磁碟 SMART | smartctl |
| 磁碟速度 | fio（循序讀寫 + 隨機 4K）|
| 溫度 | lm-sensors |
| GPU | nvidia-smi |
| 網路 | speedtest-cli |
