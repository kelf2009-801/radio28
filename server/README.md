# Radio28 server — Docker deploy on the VPS.

## What's in the box
- `livekit`  — SFU media server (voice), ports 7880/7881 + UDP 50000-60000 + TURN
- `coturn`   — TURN server (NAT traversal for mobile networks), UDP 3478-3479
- `api`      — this FastAPI backend (registration, channels, moderation), port 8000

## Steps (run as root on Ubuntu 22.04/Debian 12)

```bash
# 1. Install Docker once
curl -fsSL https://get.docker.com | sh

# 2. Copy this folder to the server
#    (scp -r radio28/server root@IP:/opt/radio28 or git pull)

cd /opt/radio28/server

# 3. Generate secrets
LK_API_KEY=$(openssl rand -hex 8)
LK_API_SECRET=$(openssl rand -hex 24)
TURN_SECRET=$(openssl rand -hex 24)
SERVER_IP=<your-public-ip>

cat > .env <<EOF
LK_API_KEY=$LK_API_KEY
LK_API_SECRET=$LK_API_SECRET
TURN_SECRET=$TURN_SECRET
SERVER_IP=$SERVER_IP
LK_PUBLIC_URL=wss://$SERVER_IP:7880
EOF

# 4. Build livekit.yaml from template
envsubst < livekit.yaml.template > livekit.yaml
# (or just edit livekit.yaml manually: set api_key, api_secret, external_ip, TURN credentials)

# 5. Up
docker compose up -d

# 6. Check
docker compose ps
curl http://127.0.0.1:8000/health
```

## Firewall (ufw or hosting panel)
- TCP 7880  (LiveKit WS)
- TCP 8000  (API)
- UDP 3478  (TURN)
- UDP 5349  (TURN over TLS, optional)
- UDP 50000-60000 (WebRTC media)

## Android app
Settings → Server address: `http://<server-ip>:8000`
(For production: put nginx+certbot in front of 8000 and 7880, use wss://)

## API keys the app doesn't need
The app talks to the API only; the API talks to LiveKit internally. The app
never sees `LK_API_SECRET` — tokens are minted server-side per request.
