#!/bin/bash
# ============================================
# DNS Record Teardown via Cloudflare API
# Removes all records created for the engagement
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

delete_records_by_name() {
    local name="$1"

    echo "[*] Looking up records for: ${name}"
    records=$(curl -s -X GET "${CF_API}/zones/${CF_ZONE_ID}/dns_records?name=${name}" \
        -H "${AUTH_HEADER}" \
        -H "Content-Type: application/json")

    ids=$(echo "${records}" | python3 -c "
import sys, json
data = json.load(sys.stdin)
for r in data.get('result', []):
    print(r['id'])
" 2>/dev/null)

    if [ -z "${ids}" ]; then
        echo "[-] No records found for ${name}"
        return
    fi

    for id in ${ids}; do
        echo "[*] Deleting record ${id}..."
        curl -s -X DELETE "${CF_API}/zones/${CF_ZONE_ID}/dns_records/${id}" \
            -H "${AUTH_HEADER}" \
            -H "Content-Type: application/json" > /dev/null
        echo "[+] Deleted"
    done
}

echo "==========================================="
echo " Cloudflare DNS Teardown"
echo " Domain: ${BASE_DOMAIN}"
echo "==========================================="

delete_records_by_name "${BASE_DOMAIN}"

if [ -n "${PHISHLET_HOSTNAME}" ]; then
    delete_records_by_name "${PHISHLET_HOSTNAME}"
fi

echo ""
echo "[*] DNS teardown complete."
