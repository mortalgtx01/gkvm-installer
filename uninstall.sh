#!/usr/bin/env bash
#
# VNM Panel - Uninstaller
#   sudo bash uninstall.sh
#
# Stops and removes the systemd service. By default the install directory
# (including the database and VM disk images) is left in place - pass
# --purge to delete everything.
#
set -euo pipefail

INSTALL_DIR="${INSTALL_DIR:-/opt/vnm-panel}"
SERVICE_NAME="${SERVICE_NAME:-vnm-panel}"
SERVICE_USER="${SERVICE_USER:-vnm}"
PURGE=0

for arg in "$@"; do
  case "$arg" in
    --purge) PURGE=1 ;;
  esac
done

if [[ "${EUID}" -ne 0 ]]; then
  echo "Please run as root (sudo bash uninstall.sh)"
  exit 1
fi

echo "==> Stopping and disabling ${SERVICE_NAME}"
systemctl stop "${SERVICE_NAME}" 2>/dev/null || true
systemctl disable "${SERVICE_NAME}" 2>/dev/null || true
rm -f "/etc/systemd/system/${SERVICE_NAME}.service"
systemctl daemon-reload

if [[ "${PURGE}" -eq 1 ]]; then
  echo "==> Purging ${INSTALL_DIR} (including VM disks/database) and service user"
  read -r -p "This deletes ALL VM disks and data in ${INSTALL_DIR}. Type 'yes' to confirm: " confirm
  if [[ "${confirm}" == "yes" ]]; then
    rm -rf "${INSTALL_DIR}"
    id -u "${SERVICE_USER}" >/dev/null 2>&1 && userdel "${SERVICE_USER}" 2>/dev/null || true
    echo "Removed."
  else
    echo "Purge cancelled - install directory left in place."
  fi
else
  echo "==> Service removed. Install directory left at ${INSTALL_DIR} (use --purge to delete it too)."
fi
