#!/bin/bash
# ============================================
# Full deployment: DNS + Build + Launch
# ============================================
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="${SCRIPT_DIR}/.."

cd "${PROJECT_DIR}"

# Check .env exists
if [ ! -f .env ]; then
    echo "[!] .env file not found. Copy .env.example to .env and fill in your values."
    exit 1
fi

source .env

echo "==========================================="
echo " Evilginx Deployment"
echo " Domain:   ${BASE_DOMAIN}"
echo " IP:       ${SERVER_IP}"
echo " Phishlet: ${PHISHLET_NAME}"
echo "==========================================="
echo ""

# Step 1: DNS setup (optional — skip if records already exist)
read -p "[?] Set up DNS records via Cloudflare? (y/N): " dns_choice
if [ "${dns_choice}" = "y" ] || [ "${dns_choice}" = "Y" ]; then
    bash "${SCRIPT_DIR}/dns-setup.sh"
    echo "[*] Waiting 30s for DNS propagation..."
    sleep 30
fi

# Step 2: Stop any existing containers
echo "[*] Cleaning up existing containers..."
docker compose down 2>/dev/null || true

# Step 3: Build and launch
echo "[*] Building and starting Evilginx..."
COMPOSE_PROFILES=""
read -p "[?] Include filtering redirector? (y/N): " redir_choice
if [ "${redir_choice}" = "y" ] || [ "${redir_choice}" = "Y" ]; then
    COMPOSE_PROFILES="--profile with-redirector"
fi

docker compose ${COMPOSE_PROFILES} up -d --build

echo ""
echo "[+] Deployment complete!"
echo "[*] Logs: docker compose logs -f evilginx"
echo "[*] Shell: docker exec -it evilginx /bin/bash"
echo "[*] Teardown: bash scripts/teardown.sh"
