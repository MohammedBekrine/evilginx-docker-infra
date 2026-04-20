#!/bin/bash
# ============================================
# DNS Record Setup via Cloudflare API
# Creates A + NS records for Evilginx
# ============================================
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../.env"

CF_API="https://api.cloudflare.com/client/v4"
AUTH_HEADER="Authorization: Bearer ${CF_API_TOKEN}"

if [ -z "${CF_API_TOKEN}" ] || [ -z "${CF_ZONE_ID}" ]; then
    echo "[!] CF_API_TOKEN and CF_ZONE_ID must be set in .env"
    exit 1
fi

create_record() {
    local type="$1" name="$2" content="$3" proxied="${4:-false}"

    echo "[*] Creating ${type} record: ${name} -> ${content}"
    response=$(curl -s -X POST "${CF_API}/zones/${CF_ZONE_ID}/dns_records" \
        -H "${AUTH_HEADER}" \
        -H "Content-Type: application/json" \
        --data "{
            \"type\": \"${type}\",
            \"name\": \"${name}\",
            \"content\": \"${content}\",
            \"ttl\": 120,
            \"proxied\": ${proxied}
        }")

    success=$(echo "${response}" | python3 -c "import sys,json; print(json.load(sys.stdin).get('success', False))" 2>/dev/null)
    if [ "${success}" = "True" ]; then
        echo "[+] Created successfully"
    else
        echo "[!] Failed: ${response}"
    fi
}

echo "==========================================="
echo " Cloudflare DNS Setup"
echo " Domain: ${BASE_DOMAIN}"
echo " Server: ${SERVER_IP}"
echo "==========================================="

# A record for the evilginx server
create_record "A" "${BASE_DOMAIN}" "${SERVER_IP}"

# A record for the phishlet hostname
if [ -n "${PHISHLET_HOSTNAME}" ]; then
    create_record "A" "${PHISHLET_HOSTNAME}" "${SERVER_IP}"
fi

# NS delegation for evilginx subdomain handling
# Evilginx needs to be authoritative for its subdomains
if [[ "${PHISHLET_HOSTNAME}" == *".${BASE_DOMAIN}" ]]; then
    EVILGINX_NS_SUB="${PHISHLET_HOSTNAME%.${BASE_DOMAIN}}"
else
    EVILGINX_NS_SUB=""
fi
if [ -n "${EVILGINX_NS_SUB}" ]; then
    create_record "NS" "${EVILGINX_NS_SUB}.${BASE_DOMAIN}" "${BASE_DOMAIN}"
fi

echo ""
echo "[*] DNS setup complete. Allow a few minutes for propagation."
echo "[*] Verify with: dig +short ${PHISHLET_HOSTNAME}"
