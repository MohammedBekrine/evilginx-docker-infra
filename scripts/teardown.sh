#!/bin/bash
# ============================================
# Full teardown: Export logs + Destroy + DNS cleanup
# ============================================
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="${SCRIPT_DIR}/.."

cd "${PROJECT_DIR}"
source .env

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
EXPORT_DIR="${PROJECT_DIR}/exports/${TIMESTAMP}"

echo "==========================================="
echo " Evilginx Teardown"
echo " Domain: ${BASE_DOMAIN}"
echo "==========================================="

# Step 1: Export logs and captured data
echo "[*] Exporting logs and data..."
mkdir -p "${EXPORT_DIR}"

# Copy logs
cp -r logs/ "${EXPORT_DIR}/logs" 2>/dev/null || echo "[-] No logs to export"

# Copy evilginx data (sessions, certs, etc.)
docker cp evilginx:/root/.evilginx "${EXPORT_DIR}/evilginx-data" 2>/dev/null || echo "[-] Could not export evilginx data"

echo "[+] Data exported to: ${EXPORT_DIR}"

# Step 2: Destroy containers and volumes
echo "[*] Stopping and removing containers..."
docker compose --profile with-redirector down -v 2>/dev/null || true
docker compose down -v 2>/dev/null || true

# Step 3: DNS teardown (optional)
read -p "[?] Remove DNS records from Cloudflare? (y/N): " dns_choice
if [ "${dns_choice}" = "y" ] || [ "${dns_choice}" = "Y" ]; then
    bash "${SCRIPT_DIR}/dns-teardown.sh"
fi

echo ""
echo "[+] Teardown complete."
echo "[+] Exported data: ${EXPORT_DIR}"
