#!/usr/bin/env bash
# GKVM PANEL V1.0 - production VPS installer
set -Eeuo pipefail

RED='\e[1;31m'; GREEN='\e[1;32m'; YELLOW='\e[1;33m'; CYAN='\e[1;36m'; MAGENTA='\e[1;35m'; NC='\e[0m'
APP_NAME="GKVM Panel V1.0"
SERVICE_NAME="${SERVICE_NAME:-gkvm}"
INSTALL_DIR="${INSTALL_DIR:-/opt/gkvm}"
PANEL_PORT="${PORT:-8080}"
SERVICE_USER="${SERVICE_USER:-gkvm}"
NODE_MAJOR="${NODE_MAJOR:-20}"
SOURCE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="/var/log/gkvm.log"
SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"

die(){ echo -e "${RED}[ERROR]${NC} $*"; exit 1; }
info(){ echo -e "${CYAN}[INFO]${NC} $*"; }
ok(){ echo -e "${GREEN}[OK]${NC} $*"; }
warn(){ echo -e "${YELLOW}[WARN]${NC} $*"; }
line(){ echo -e "${MAGENTA}============================================================${NC}"; }

[[ $EUID -eq 0 ]] || die "Run as root: sudo bash install.sh"
command -v systemctl >/dev/null 2>&1 || die "systemd is required."
[[ -f /etc/os-release ]] || die "Cannot detect OS."
source /etc/os-release
ARCH="$(uname -m)"
case "$ARCH" in x86_64|amd64|aarch64|arm64) ;; *) die "Unsupported architecture: $ARCH";; esac

echo -e "${CYAN}"
cat <<'EOF'
   ██████╗ ██╗  ██╗██╗   ██╗███╗   ███╗
  ██╔════╝ ██║ ██╔╝██║   ██║████╗ ████║
  ██║  ███╗█████╔╝ ██║   ██║██╔████╔██║
  ██║   ██║██╔═██╗ ╚██╗ ██╔╝██║╚██╔╝██║
  ╚██████╔╝██║  ██╗ ╚████╔╝ ██║ ╚═╝ ██║
   ╚═════╝ ╚═╝  ╚═╝  ╚═══╝  ╚═╝     ╚═╝
                 GKVM PANEL V1.0
EOF
echo -e "${NC}"; line
info "OS: ${PRETTY_NAME:-$ID} | Arch: $ARCH | Port: $PANEL_PORT"

install_debian(){
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -y
  apt-get install -y curl ca-certificates gnupg build-essential python3 sqlite3 libsqlite3-dev \
    qemu-system-x86 qemu-utils cloud-image-utils genisoimage xorriso bridge-utils \
    net-tools unzip git rsync lsof procps iproute2 sudo
}
install_rpm(){
  local pm
  pm="$(command -v dnf || command -v yum || true)"
  [[ -n "$pm" ]] || die "No dnf/yum package manager found."
  "$pm" -y install curl ca-certificates gcc gcc-c++ make python3 sqlite sqlite-devel \
    qemu-system-x86-core qemu-img genisoimage xorriso bridge-utils net-tools unzip git rsync lsof procps-ng iproute sudo \
    || "$pm" -y install curl ca-certificates gcc gcc-c++ make python3 sqlite sqlite-devel qemu-img git rsync unzip sudo
}
case "${ID}" in
  ubuntu|debian) install_debian ;;
  rhel|centos|rocky|almalinux|fedora) install_rpm ;;
  *) warn "Untested distro ${ID}; attempting existing package manager."; command -v apt-get >/dev/null && install_debian || command -v dnf >/dev/null && install_rpm || die "Unsupported package manager." ;;
esac
ok "System dependencies installed."

if ! command -v node >/dev/null 2>&1 || [[ "$(node -p 'process.versions.node.split(".")[0]')" -lt "$NODE_MAJOR" ]]; then
  if command -v apt-get >/dev/null 2>&1; then
    curl -fsSL "https://deb.nodesource.com/setup_${NODE_MAJOR}.x" | bash -
    apt-get install -y nodejs
  elif command -v dnf >/dev/null 2>&1; then
    curl -fsSL "https://rpm.nodesource.com/setup_${NODE_MAJOR}.x" | bash -
    dnf install -y nodejs
  elif command -v yum >/dev/null 2>&1; then
    curl -fsSL "https://rpm.nodesource.com/setup_${NODE_MAJOR}.x" | bash -
    yum install -y nodejs
  else die "Node.js ${NODE_MAJOR}+ is required."; fi
fi
ok "Node $(node -v), npm $(npm -v)"

[[ -d /dev/kvm ]] && [[ -r /dev/kvm ]] && warn "/dev/kvm detected." || warn "/dev/kvm is unavailable; QEMU may use software emulation."
if ! id -u "$SERVICE_USER" >/dev/null 2>&1; then
  useradd --system --create-home --shell /usr/sbin/nologin "$SERVICE_USER"
fi
getent group kvm >/dev/null 2>&1 && usermod -aG kvm "$SERVICE_USER" || true

if ss -ltn 2>/dev/null | grep -q ":${PANEL_PORT} "; then die "Port ${PANEL_PORT} is already in use."; fi

mkdir -p "$INSTALL_DIR"
systemctl stop "$SERVICE_NAME" >/dev/null 2>&1 || true
rsync -a --delete \
  --exclude node_modules --exclude data --exclude .env --exclude '*.log' \
  --exclude .git "${SOURCE_DIR}/" "${INSTALL_DIR}/"
mkdir -p "${INSTALL_DIR}/data"
ok "Application installed at ${INSTALL_DIR}"

ENV_FILE="${INSTALL_DIR}/.env"
if [[ ! -f "$ENV_FILE" ]]; then
  SESSION_SECRET="$(node -e "console.log(require('crypto').randomBytes(32).toString('hex'))")"
  cat > "$ENV_FILE" <<EOF
PORT=${PANEL_PORT}
VNM_DATA_DIR=${INSTALL_DIR}/data
PANEL_NAME=GKVM Panel
PANEL_VERSION=V1.0
DEFAULT_LOGO_URL=https://i.imgur.com/4p7wdYK.png
NODE_ENV=production
SESSION_SECRET=${SESSION_SECRET}
LICENSE_SERVER_URL=https://arinjay01.pythonanywhere.com
LICENSE_PRODUCT=GVM-PANEL
LICENSE_GRACE_PERIOD=86400
DEFAULT_ADMIN_USERNAME=admin@gkvm.gtx
DEFAULT_ADMIN_PASSWORD=Admin@gtx
EOF
  ok "Created .env"
else
  warn "Existing .env preserved."
fi

cd "$INSTALL_DIR"
npm ci --omit=dev --foreground-scripts
ok "Node dependencies installed."

chown -R "${SERVICE_USER}:${SERVICE_USER}" "$INSTALL_DIR"
chmod 600 "$ENV_FILE"
find "$INSTALL_DIR" -type d -exec chmod 755 {} +
find "$INSTALL_DIR" -type f -name '*.sh' -exec chmod 755 {} +
touch "$LOG_FILE"; chown "${SERVICE_USER}:${SERVICE_USER}" "$LOG_FILE"; chmod 640 "$LOG_FILE"

# Open panel port where a local firewall is enabled.
if command -v ufw >/dev/null 2>&1; then ufw allow "${PANEL_PORT}/tcp" >/dev/null 2>&1 || true; fi
if command -v firewall-cmd >/dev/null 2>&1; then
  firewall-cmd --permanent --add-port="${PANEL_PORT}/tcp" >/dev/null 2>&1 || true
  firewall-cmd --reload >/dev/null 2>&1 || true
fi

NODE_BIN="$(command -v node)"
cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=GKVM Panel V1.0
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=${SERVICE_USER}
Group=${SERVICE_USER}
WorkingDirectory=${INSTALL_DIR}
EnvironmentFile=${ENV_FILE}
ExecStart=${NODE_BIN} ${INSTALL_DIR}/app.js
Restart=on-failure
RestartSec=5
LimitNOFILE=1048576
Environment=NODE_ENV=production
NoNewPrivileges=true
ProtectSystem=full
ReadWritePaths=${INSTALL_DIR}

[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl enable "$SERVICE_NAME" >/dev/null
systemctl restart "$SERVICE_NAME"
sleep 3
if ! systemctl is-active --quiet "$SERVICE_NAME"; then
  journalctl -u "$SERVICE_NAME" -n 80 --no-pager || true
  die "GKVM Panel failed to start."
fi

PUBLIC_IP="$(curl -4 -fsS --max-time 8 https://api.ipify.org 2>/dev/null || hostname -I 2>/dev/null | awk '{print $1}')"
PUBLIC_IP="${PUBLIC_IP:-YOUR_SERVER_IP}"
line
echo -e "${GREEN}"
cat <<EOF
GKVM PANEL V1.0 — INSTALLATION COMPLETE

Panel:       http://${PUBLIC_IP}:${PANEL_PORT}
Directory:   ${INSTALL_DIR}
Service:     ${SERVICE_NAME}
Logs:        journalctl -u ${SERVICE_NAME} -f

Login:
  Username:  admin@gkvm.gtx
  Password:  Admin@gtx

Commands:
  systemctl status ${SERVICE_NAME}
  systemctl restart ${SERVICE_NAME}
  systemctl stop ${SERVICE_NAME}
  systemctl start ${SERVICE_NAME}
EOF
echo -e "${NC}"
ok "Installation finished."
