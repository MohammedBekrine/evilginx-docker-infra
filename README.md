# Evilginx Docker Infrastructure

Automated Evilginx deployment for authorized red team engagements. **Written authorization required before use.**

---

## Requirements

- Docker Engine + Compose v2 plugin
- A registered domain with DNS managed by Cloudflare (or manual DNS for another provider)
- Cloudflare API token (`Zone:DNS:Edit`) and the target Zone ID
- Public VPS with ports 53/udp, 80/tcp, 443/tcp free and reachable (needed for ACME and phishlet traffic)
- `systemd-resolved` stopped if it holds port 53

---

## How it works

**Build.** Two-stage Dockerfile: stage 1 clones `kgretzky/evilginx2` and runs `make`; stage 2 copies the static binary into `alpine:3.19` (~30 MB). Upstream's shipped phishlets are baked into `/app/phishlets-default/`.

**Phishlets.** On container start, `entrypoint.sh` merges two sources into `/root/.evilginx/phishlets/`:
1. Defaults from `/app/phishlets-default/` (baked in — currently just `example.yaml`).
2. Customs from `/app/phishlets/`, bind-mounted from `./config/phishlets/` on the host. A custom with the same filename overrides a default.

Evilginx is launched with `-p /root/.evilginx/phishlets` so it sees the merged set.

**Compose topology.** Both services use `network_mode: host` so ports land directly on the VPS:
- `evilginx` — binds 53/udp + 80/tcp + 443/tcp; runs with TTY attached so the REPL stays alive. Attach with `docker attach evilginx` to drive it. Custom capabilities `NET_ADMIN` + `NET_BIND_SERVICE` for privileged port binding.
- `redirector` (profile `with-redirector`, optional) — Caddy on :8443. Terminates TLS with an internal CA cert matching `{$PHISHLET_HOSTNAME}`, filters scanner/bot user-agents to `REDIRECT_URL`, reverse-proxies the rest to `https://localhost:443` forwarding the original SNI. `auto_https disable_redirects` keeps Caddy off :80 so it doesn't collide with Evilginx.

**Config.** `entrypoint.sh` generates a `setup.cfg` from `.env` (`BASE_DOMAIN`, `SERVER_IP`, `PHISHLET_NAME`, `PHISHLET_HOSTNAME`, `LURE_REDIRECT_URL`, `LURE_PATH`), then uses `expect` to spawn Evilginx, wait for the REPL to be ready, feed each command automatically, and hand off to interactive mode. No manual pasting needed — `docker attach evilginx` drops you into an already-configured REPL.

**DNS.** `scripts/dns-setup.sh` calls the Cloudflare API to create:
- `A  BASE_DOMAIN          -> SERVER_IP`
- `A  PHISHLET_HOSTNAME    -> SERVER_IP`
- `NS <phishlet_sub>.BASE_DOMAIN -> BASE_DOMAIN` (delegates the phishlet subdomain so Evilginx can be authoritative for ACME)

`dns-teardown.sh` looks up matching records by name and deletes them by ID.

**Lifecycle scripts.**
- `scripts/deploy.sh` — prompt for DNS + redirector, then `docker compose up -d --build`.
- `scripts/teardown.sh` — `docker cp` the Evilginx data dir and `./logs/` into `./exports/<timestamp>/`, `docker compose down -v`, optionally remove DNS.

**Persistence.** Sessions, certs, and Evilginx's config live in the `evilginx-data` named volume (`/root/.evilginx` in-container). `./logs/` is bind-mounted for host-side log access. Both are excluded from the image via `.dockerignore`.

---

## Step-by-step: configure and deploy

### 1. Configure

```bash
cp .env.example .env
$EDITOR .env
```

Set at minimum:

| Variable | Example | Notes |
|---|---|---|
| `SERVER_IP` | `203.0.113.50` | Public IP of the VPS |
| `BASE_DOMAIN` | `example.com` | A domain you control, managed in Cloudflare |
| `PHISHLET_NAME` | `o365` | Must match a `.yaml` filename available in the container (see step 2) |
| `PHISHLET_HOSTNAME` | `login.example.com` | Subdomain of `BASE_DOMAIN` that targets will see |
| `LURE_REDIRECT_URL` | `https://www.office.com` | Where the target lands after credential capture |
| `REDIRECT_URL` | `https://www.microsoft.com` | Where scanners/unauth requests get redirected |
| `CF_API_TOKEN` | — | Cloudflare token with `Zone:DNS:Edit` on the zone |
| `CF_ZONE_ID` | — | Zone ID of `BASE_DOMAIN` |

### 2. Supply a phishlet

Only upstream's `example.yaml` ships by default and it's a template — it will not capture credentials. For a real engagement:

```bash
cp /path/to/o365.yaml config/phishlets/
```

Then set `PHISHLET_NAME=o365` in `.env`. Community phishlets live in repos like `simplerhacking/Evilginx3-Phishlets`.

### 3. Free port 53 if needed

```bash
sudo systemctl stop systemd-resolved
sudo systemctl disable systemd-resolved
```

### 4. Deploy

```bash
bash scripts/deploy.sh
```

The script prompts:
- "Set up DNS records via Cloudflare?" → **y** for the first deploy (creates the A/A/NS records). Wait ~30 s for propagation.
- "Include filtering redirector?" → **y** to front Evilginx with Caddy on :8443 (scanner/bot filtering). Skip if you don't need it.

Then it runs `docker compose up -d --build`.

### 5. Verify

The entrypoint auto-applies all `.env` settings (domain, IP, phishlet, lure) via `expect` — no manual pasting needed. Check the logs to confirm everything applied:

```bash
docker logs evilginx
```

Look for `[+] Auto-config applied` and verify the phishlet shows `enabled` in the table.

### 6. Grab the phishing URL

```bash
docker attach evilginx
lures get-url 0
```

That's the URL to deliver to the authorized targets. Detach without stopping: **Ctrl-P Ctrl-Q**.

### 7. Operate

```bash
docker logs -f evilginx          # live log
docker attach evilginx           # back into the REPL
# inside REPL:
#   sessions         — list captured sessions
#   sessions <id>    — tokens/cookies for a session
#   blacklist getall — view blacklisted IPs
```

### 8. Teardown (post-engagement)

```bash
bash scripts/teardown.sh
```

Exports `./logs/` and the Evilginx data volume (sessions, certs, db) to `./exports/<timestamp>/`, destroys containers + volume, and optionally removes the Cloudflare records.

---

## Layout

```
.env.example              # parameters (server IP, domain, phishlet, Cloudflare creds)
Dockerfile                # multi-stage build
docker-compose.yml        # evilginx + optional caddy redirector
config/phishlets/         # drop custom <name>.yaml here
redirector/Caddyfile      # filtering reverse proxy (profile: with-redirector)
scripts/
  deploy.sh / teardown.sh
  dns-setup.sh / dns-teardown.sh
  entrypoint.sh           # runs inside the container
```
