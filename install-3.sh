#!/usr/bin/env bash
set -euo pipefail

REPO="https://github.com/y4sh-x/Legacy-vps-deploy-bot.git"
BRANCH="main"
APP_DIR="/opt/legacy-vps-manager"
SERVICE="legacy-vps-manager"
PYTHON_BIN="python3"

if [[ $EUID -ne 0 ]]; then
  echo "Run this installer as root:"
  echo "sudo bash install.sh"
  exit 1
fi

echo "=============================================="
echo "      Legacy Vps Manager V1 Installer"
echo "              Developer: y4sh.x"
echo "=============================================="

command -v apt-get >/dev/null 2>&1 || {
  echo "This installer currently supports Debian/Ubuntu systems."
  exit 1
}

echo "[1/7] Installing system dependencies..."
apt-get update -y
apt-get install -y git curl ca-certificates "$PYTHON_BIN" python3-venv python3-pip

echo "[2/7] Downloading latest version..."
if [[ -d "$APP_DIR/.git" ]]; then
  git -C "$APP_DIR" fetch --depth=1 origin "$BRANCH"
  git -C "$APP_DIR" reset --hard "origin/$BRANCH"
  git -C "$APP_DIR" clean -fd
else
  rm -rf "$APP_DIR"
  git clone --depth=1 --branch "$BRANCH" "$REPO" "$APP_DIR"
fi

cd "$APP_DIR"

echo "[3/7] Creating Python environment..."
"$PYTHON_BIN" -m venv .venv
.venv/bin/python -m pip install --upgrade pip
.venv/bin/pip install -r requirements.txt

echo
echo "Bot configuration"
echo "-----------------"
read -r -p "Discord Bot Token: " BOT_TOKEN
echo
read -r -p "Main Admin Discord User ID: " ADMIN_ID

if [[ -z "$BOT_TOKEN" || -z "$ADMIN_ID" ]]; then
  echo "Bot token and Admin ID are required."
  exit 1
fi

if ! [[ "$ADMIN_ID" =~ ^[0-9]{17,20}$ ]]; then
  echo "Invalid Discord User ID."
  exit 1
fi

umask 077
cat > "$APP_DIR/.env" <<EOF
DISCORD_TOKEN=$BOT_TOKEN
MAIN_ADMIN_ID=$ADMIN_ID
EOF

echo "[4/7] Installing configuration..."
chmod 600 "$APP_DIR/.env"

echo "[5/7] Installing system service..."
cat > "/etc/systemd/system/$SERVICE.service" <<EOF
[Unit]
Description=Legacy Vps Manager V1
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
WorkingDirectory=$APP_DIR
EnvironmentFile=$APP_DIR/.env
ExecStart=$APP_DIR/.venv/bin/python $APP_DIR/bot.py
Restart=always
RestartSec=5
User=root

[Install]
WantedBy=multi-user.target
EOF

echo "[6/7] Starting Legacy Vps Manager..."
systemctl daemon-reload
systemctl enable --now "$SERVICE"

echo "[7/7] Verifying..."
if systemctl is-active --quiet "$SERVICE"; then
  echo
  echo "Installation complete."
  echo "Service: $SERVICE"
  echo "Directory: $APP_DIR"
  echo "Logs: journalctl -u $SERVICE -f"
else
  echo "The service did not start successfully."
  echo "Check: journalctl -u $SERVICE -n 100 --no-pager"
  exit 1
fi
