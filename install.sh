#!/usr/bin/env bash

# ============================================================
# GKVM PANEL V1 — INSTALLER
# ============================================================

set -Eeuo pipefail

APP_NAME="GKVM Panel"
SERVICE_NAME="gkvm-panel"
INSTALL_DIR="/opt/gkvm-panel"
REPO="mortaltgx01/gkvmpanel"
PORT="8080"

RED='\033[1;31m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
CYAN='\033[1;36m'
MAGENTA='\033[1;35m'
NC='\033[0m'

line() {
    echo -e "${MAGENTA}============================================================${NC}"
}

info() {
    echo -e "${CYAN}[INFO]${NC} $*"
}

ok() {
    echo -e "${GREEN}[OK]${NC} $*"
}

warn() {
    echo -e "${YELLOW}[WARNING]${NC} $*"
}

die() {
    echo -e "${RED}[ERROR]${NC} $*"
    exit 1
}

clear

echo -e "${CYAN}"
cat <<'EOF'

   ██████╗ ██╗  ██╗██╗   ██╗███╗   ███╗
  ██╔════╝ ██║ ██╔╝██║   ██║████╗ ████║
  ██║  ███╗█████╔╝ ██║   ██║██╔████╔██║
  ██║   ██║██╔═██╗ ██║   ██║██║╚██╔╝██║
  ╚██████╔╝██║  ██╗╚██████╔╝██║ ╚═╝ ██║
   ╚═════╝ ╚═╝  ╚═╝ ╚═════╝ ╚═╝     ╚═╝

              GKVM PANEL V1
                 INSTALLER

EOF
echo -e "${NC}"

line

# ============================================================
# ROOT CHECK
# ============================================================

if [[ "${EUID}" -ne 0 ]]; then
    die "Run this installer as root."
fi

ok "Root access detected."

# ============================================================
# OS DETECTION
# ============================================================

if [[ ! -f /etc/os-release ]]; then
    die "Unable to detect operating system."
fi

source /etc/os-release

info "OS           : ${PRETTY_NAME:-unknown}"
info "Architecture : $(uname -m)"
info "Kernel       : $(uname -r)"

line

# ============================================================
# DEPENDENCIES
# ============================================================

info "Checking dependencies..."

install_dependencies() {

    if command -v apt-get >/dev/null 2>&1; then

        export DEBIAN_FRONTEND=noninteractive

        apt-get update -y

        apt-get install -y \
            curl \
            wget \
            git \
            ca-certificates \
            sudo \
            lsof \
            procps \
            build-essential

    elif command -v dnf >/dev/null 2>&1; then

        dnf install -y \
            curl \
            wget \
            git \
            ca-certificates \
            sudo \
            lsof \
            procps-ng \
            gcc \
            gcc-c++ \
            make

    elif command -v yum >/dev/null 2>&1; then

        yum install -y \
            curl \
            wget \
            git \
            ca-certificates \
            sudo \
            lsof \
            procps \
            gcc \
            gcc-c++ \
            make

    elif command -v apk >/dev/null 2>&1; then

        apk add \
            curl \
            wget \
            git \
            ca-certificates \
            sudo \
            lsof \
            procps \
            gcc \
            g++ \
            make

    else
        die "Unsupported Linux distribution."
    fi
}

MISSING=()

for cmd in curl git sudo; do
    if ! command -v "${cmd}" >/dev/null 2>&1; then
        MISSING+=("${cmd}")
    fi
done

if (( ${#MISSING[@]} > 0 )); then
    info "Installing missing dependencies..."
    install_dependencies
fi

ok "System dependencies ready."

# ============================================================
# NODE.JS
# ============================================================

line

info "Checking Node.js..."

if command -v node >/dev/null 2>&1; then

    NODE_VERSION="$(node -v)"

    info "Node.js found: ${NODE_VERSION}"

else

    warn "Node.js is not installed."

    if command -v apt-get >/dev/null 2>&1; then

        curl -fsSL \
            https://deb.nodesource.com/setup_22.x \
            | bash -

        apt-get install -y nodejs

    elif command -v dnf >/dev/null 2>&1; then

        curl -fsSL \
            https://rpm.nodesource.com/setup_22.x \
            | bash -

        dnf install -y nodejs

    elif command -v yum >/dev/null 2>&1; then

        curl -fsSL \
            https://rpm.nodesource.com/setup_22.x \
            | bash -

        yum install -y nodejs

    else

        die "Unable to automatically install Node.js."

    fi

fi

if ! command -v npm >/dev/null 2>&1; then
    die "npm was not found after Node.js installation."
fi

ok "Node.js: $(node -v)"
ok "npm: $(npm -v)"

# ============================================================
# GITHUB ACCESS
# ============================================================

line

echo
echo -e "${CYAN}GKVM Panel Repository:${NC}"
echo "https://github.com/${REPO}"
echo

echo "A GitHub access token with repository read access is required."
echo
echo "Recommended token permissions:"
echo "  Repository access : Only selected repository"
echo "  Repository        : ${REPO##*/}"
echo "  Contents          : Read-only"
echo

read -r -s -p "GitHub access token: " GITHUB_TOKEN
echo

if [[ -z "${GITHUB_TOKEN}" ]]; then
    die "GitHub token cannot be empty."
fi

# ============================================================
# TEST REPOSITORY ACCESS
# ============================================================

info "Checking repository access..."

if ! curl \
    -fsS \
    -H "Authorization: Bearer ${GITHUB_TOKEN}" \
    -H "Accept: application/vnd.github+json" \
    "https://api.github.com/repos/${REPO}" \
    >/dev/null; then

    unset GITHUB_TOKEN

    die "Cannot access the repository. Check the GitHub token and repository permissions."

fi

ok "Repository access verified."

# ============================================================
# INSTALL DIRECTORY
# ============================================================

line

info "Preparing installation directory..."

if systemctl list-unit-files 2>/dev/null |
    grep -q "^${SERVICE_NAME}\.service"; then

    info "Stopping existing GKVM Panel service..."

    systemctl stop "${SERVICE_NAME}" \
        >/dev/null 2>&1 || true

fi

mkdir -p "$(dirname "${INSTALL_DIR}")"

rm -rf "${INSTALL_DIR}"

mkdir -p "${INSTALL_DIR}"

# ============================================================
# GIT CREDENTIAL HANDLING
# ============================================================

TEMP_GIT_DIR="$(mktemp -d)"

cleanup() {

    rm -rf "${TEMP_GIT_DIR}" \
        2>/dev/null || true

    unset GITHUB_TOKEN \
        2>/dev/null || true

}

trap cleanup EXIT

cat > "${TEMP_GIT_DIR}/git-askpass.sh" <<EOF
#!/usr/bin/env bash

case "\$1" in

    *Username*)
        echo "x-access-token"
        ;;

    *Password*)
        echo "${GITHUB_TOKEN}"
        ;;

    *)
        echo
        ;;

esac
EOF

chmod 700 "${TEMP_GIT_DIR}/git-askpass.sh"

export GIT_ASKPASS="${TEMP_GIT_DIR}/git-askpass.sh"
export GIT_TERMINAL_PROMPT=0

# ============================================================
# DOWNLOAD PANEL
# ============================================================

info "Downloading GKVM Panel..."

git clone \
    --depth 1 \
    "https://github.com/${REPO}.git" \
    "${INSTALL_DIR}"

unset GIT_ASKPASS
unset GIT_TERMINAL_PROMPT
unset GITHUB_TOKEN

rm -rf "${TEMP_GIT_DIR}"

ok "GKVM Panel downloaded."

# ============================================================
# PANEL CHECK
# ============================================================

cd "${INSTALL_DIR}"

if [[ ! -f "package.json" ]]; then
    die "package.json was not found."
fi

if [[ ! -f "app.js" ]]; then
    warn "app.js was not found."
fi

# ============================================================
# NPM INSTALL
# ============================================================

line

info "Installing Node.js packages..."

if [[ -f package-lock.json ]]; then

    npm ci --omit=dev

else

    npm install --omit=dev

fi

ok "Node.js packages installed."

# ============================================================
# PERMISSIONS
# ============================================================

info "Applying permissions..."

chown -R root:root "${INSTALL_DIR}"

find "${INSTALL_DIR}" \
    -type d \
    -exec chmod 755 {} \;

find "${INSTALL_DIR}" \
    -type f \
    -exec chmod 644 {} \;

ok "Permissions configured."

# ============================================================
# SYSTEMD
# ============================================================

line

if command -v systemctl >/dev/null 2>&1 &&
   [[ -d /run/systemd/system ]]; then

    info "Creating systemd service..."

    cat > "/etc/systemd/system/${SERVICE_NAME}.service" <<EOF
[Unit]
Description=GKVM Panel V1
After=network-online.target
Wants=network-online.target

[Service]
Type=simple

WorkingDirectory=${INSTALL_DIR}

Environment=NODE_ENV=production
Environment=PORT=${PORT}

ExecStart=/usr/bin/npm start

Restart=always
RestartSec=5

User=root
Group=root

LimitNOFILE=1048576

StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

    chmod 644 \
        "/etc/systemd/system/${SERVICE_NAME}.service"

    systemctl daemon-reload

    systemctl enable \
        "${SERVICE_NAME}" \
        >/dev/null 2>&1

    info "Starting GKVM Panel..."

    systemctl restart "${SERVICE_NAME}"

    sleep 5

    if systemctl is-active \
        --quiet "${SERVICE_NAME}"; then

        ok "GKVM Panel service is ONLINE."

    else

        echo

        systemctl status \
            "${SERVICE_NAME}" \
            --no-pager \
            --full || true

        echo

        echo "Recent logs:"

        journalctl \
            -u "${SERVICE_NAME}" \
            -n 50 \
            --no-pager || true

        die "GKVM Panel failed to start."

    fi

else

    warn "systemd is unavailable."

    info "Starting GKVM Panel manually..."

    nohup npm start \
        >/var/log/gkvm-panel.log \
        2>&1 &

    sleep 5

    if pgrep -f "node.*app.js" \
        >/dev/null 2>&1; then

        ok "GKVM Panel started."

    else

        die "GKVM Panel failed to start. Check /var/log/gkvm-panel.log"

    fi

fi

# ============================================================
# FIREWALL
# ============================================================

line

info "Checking firewall..."

if command -v ufw >/dev/null 2>&1; then

    ufw allow "${PORT}/tcp" \
        >/dev/null 2>&1 || true

    ok "UFW checked."

fi

if command -v firewall-cmd >/dev/null 2>&1; then

    firewall-cmd \
        --permanent \
        --add-port="${PORT}/tcp" \
        >/dev/null 2>&1 || true

    firewall-cmd \
        --reload \
        >/dev/null 2>&1 || true

    ok "firewalld checked."

fi

# ============================================================
# SERVER IP
# ============================================================

PUBLIC_IP="$(
    curl -4 \
        -fsS \
        --max-time 10 \
        https://api.ipify.org \
        2>/dev/null || true
)"

if [[ -z "${PUBLIC_IP}" ]]; then

    PUBLIC_IP="$(
        hostname -I \
        2>/dev/null |
        awk '{print $1}' ||
        true
    )"

fi

if [[ -z "${PUBLIC_IP}" ]]; then
    PUBLIC_IP="YOUR_SERVER_IP"
fi

# ============================================================
# FINAL SCREEN
# ============================================================

line

echo
echo -e "${GREEN}"

cat <<EOF

╔════════════════════════════════════════════════════════════╗
║                  GKVM PANEL V1                            ║
║               INSTALLATION COMPLETE                       ║
╚════════════════════════════════════════════════════════════╝

  STATUS              : ONLINE

  PANEL URL           : http://${PUBLIC_IP}:${PORT}

  INSTALL DIRECTORY   : ${INSTALL_DIR}

  SERVICE             : ${SERVICE_NAME}

  REPOSITORY          : ${REPO}

──────────────────────────────────────────────────────────────

  SERVICE COMMANDS

  Start:
    systemctl start ${SERVICE_NAME}

  Stop:
    systemctl stop ${SERVICE_NAME}

  Restart:
    systemctl restart ${SERVICE_NAME}

  Status:
    systemctl status ${SERVICE_NAME}

──────────────────────────────────────────────────────────────

  LIVE LOGS

    journalctl -u ${SERVICE_NAME} -f

──────────────────────────────────────────────────────────────

  GKVM PANEL V1 IS READY

EOF

echo -e "${NC}"

line

echo
ok "Installation completed successfully."
echo
