#!/usr/bin/env bash
set -Eeuo pipefail

APP_DIR="${LEGACY_VPS_MANAGER_DIR:-/opt/legacy_vps_manager}"
SERVICE="${LEGACY_VPS_MANAGER_SERVICE:-legacy-vps-manager}"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

[[ ${EUID:-$(id -u)} -eq 0 ]] || { echo "Run with sudo: sudo bash install.sh"; exit 1; }
command -v apt-get >/dev/null || { echo "This installer supports Debian/Ubuntu hosts."; exit 1; }

export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y ca-certificates curl docker.io fuse3 iptables python3 python3-venv python3-pip tesseract-ocr
systemctl enable --now docker

docker info >/dev/null 2>&1 || { echo "Docker is not healthy."; exit 1; }
mkdir -p "$APP_DIR"
install -m 644 "$SCRIPT_DIR/bot.py" "$APP_DIR/bot.py"
install -m 644 "$SCRIPT_DIR/webssh.html" "$APP_DIR/webssh.html"
install -m 644 "$SCRIPT_DIR/requirements.txt" "$APP_DIR/requirements.txt"
install -m 644 "$SCRIPT_DIR/.env.example" "$APP_DIR/.env.example"

python3 -m venv "$APP_DIR/venv"
"$APP_DIR/venv/bin/pip" install --upgrade pip wheel
"$APP_DIR/venv/bin/pip" install -r "$APP_DIR/requirements.txt"

if [[ ! -f "$APP_DIR/.env" ]]; then
  cp "$APP_DIR/.env.example" "$APP_DIR/.env"
  chmod 600 "$APP_DIR/.env"
  echo
  echo "Created $APP_DIR/.env"
  echo "Set DISCORD_TOKEN before starting. Main admin is hard-coded in bot.py."
fi

cat > "/etc/systemd/system/${SERVICE}.service" <<UNIT
[Unit]
Description=Legacy Vps Manager V1 Docker VPS control plane
After=network-online.target docker.service
Wants=network-online.target
Requires=docker.service

[Service]
Type=simple
User=root
WorkingDirectory=$APP_DIR
EnvironmentFile=$APP_DIR/.env
ExecStart=$APP_DIR/venv/bin/python $APP_DIR/bot.py
Restart=always
RestartSec=5
TimeoutStopSec=30

[Install]
WantedBy=multi-user.target
UNIT

cat > /usr/local/bin/legacy-vps-manager <<CLI
#!/usr/bin/env bash
set -e
case "\${1:-status}" in
  status) systemctl status "$SERVICE" --no-pager ;;
  start|stop|restart) systemctl "\$1" "$SERVICE" ;;
  logs) journalctl -u "$SERVICE" -f ;;
  config) "\${EDITOR:-nano}" "$APP_DIR/.env" ;;
  doctor) docker info >/dev/null && "$APP_DIR/venv/bin/python" -m py_compile "$APP_DIR/bot.py" && echo "Legacy Vps Manager: OK" ;;
  containers) docker ps -a --filter label=managed-by=legacy_vps_manager ;;
  volumes) docker volume ls --filter label=managed-by=legacy_vps_manager ;;
  *) echo "Usage: legacy_vps_manager status|start|stop|restart|logs|config|doctor|containers|volumes"; exit 2 ;;
esac
CLI
chmod 755 /usr/local/bin/legacy-vps-manager
ln -sfn /usr/local/bin/legacy-vps-manager /usr/local/bin/legacy_vps_manager
systemctl daemon-reload
systemctl enable "$SERVICE"

if grep -q '^DISCORD_TOKEN=$' "$APP_DIR/.env"; then
  echo
  echo "Installation complete. Configure credentials, then start:"
  echo "  sudo legacy-vps-manager config"
  echo "  sudo legacy-vps-manager start"
else
  systemctl restart "$SERVICE"
  echo "Legacy Vps Manager installed and started. Run: sudo legacy-vps-manager logs"
fi
