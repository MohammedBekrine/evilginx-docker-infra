#!/bin/bash
# ============================================
# DNS Record Setup via Cloudflare API
# Creates A + NS records for Evilginx
# Skips records that already exist with correct values
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

record_exists() {
    local type="$1" name="$2" content="$3"

    result=$(curl -s -X GET "${CF_API}/zones/${CF_ZONE_ID}/dns_records?type=${type}&name=${name}&content=${content}" \
        -H "${AUTH_HEADER}" \
        -H "Content-Type: application/json")

    count=$(echo "${result}" | python3 -c "import sys,json; print(len(json.load(sys.stdin).get('result', [])))" 2>/dev/null)
    [ "${count}" -gt 0 ] 2>/dev/null
}

create_record() {
    local type="$1" name="$2" content="$3" proxied="${4:-false}"

    if record_exists "${type}" "${name}" "${content}"; then
        echo "[=] ${type} record already exists: ${name} -> ${content}, skipping"
        return
    fi

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

# A record for the base domain
create_record "A" "${BASE_DOMAIN}" "${SERVER_IP}"

# A record for the phishlet hostname (if different from base domain)
if [ -n "${PHISHLET_HOSTNAME}" ] && [ "${PHISHLET_HOSTNAME}" != "${BASE_DOMAIN}" ]; then
    create_record "A" "${PHISHLET_HOSTNAME}" "${SERVER_IP}"
fi

# Wildcard A record — phishlets create subdomains (login.HOSTNAME, portal.HOSTNAME, etc.)
# that all need to resolve to the server IP
create_record "A" "*.${PHISHLET_HOSTNAME:-${BASE_DOMAIN}}" "${SERVER_IP}"

# NS delegation for evilginx subdomain handling (only when phishlet hostname is a subdomain)
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
