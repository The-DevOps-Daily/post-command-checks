#!/usr/bin/env bash
# Does `docker compose up -d --build` always recreate the container when the
# image changed? Checked with the runner's Compose (bake builder by default),
# the same Compose with COMPOSE_BAKE=false, and the latest Compose release.
set -uo pipefail

check() {
  local label=$1
  local WORK; WORK=$(mktemp -d); cd "$WORK"
  printf 'FROM python:3.13-alpine\nWORKDIR /app\nCOPY app.py .\nCMD ["python", "-u", "app.py"]\n' > Dockerfile
  printf 'import http.server\nMSG = "v1"\nclass H(http.server.BaseHTTPRequestHandler):\n    def do_GET(self):\n        self.send_response(200); self.end_headers(); self.wfile.write(MSG.encode() + b"\\n")\n    def log_message(self, *a): pass\nhttp.server.HTTPServer(("", 8000), H).serve_forever()\n' > app.py
  printf 'name: rc\nservices:\n  web:\n    build: .\n    ports:\n      - "8000:8000"\n' > compose.yaml
  state() {
    local c; c=$(docker compose ps -q web)
    sleep 2
    printf '  %-34s serves=%-3s container=%s container_image=%s tag_image=%s label=%s\n' "$1" \
      "$(curl -s --retry 10 --retry-connrefused --retry-delay 1 localhost:8000)" "${c:0:12}" \
      "$(docker inspect -f '{{.Image}}' "$c" | cut -c8-19)" \
      "$(docker image inspect -f '{{.Id}}' rc-web | cut -c8-19)" \
      "$(docker inspect -f '{{index .Config.Labels "com.docker.compose.image"}}' "$c" | cut -c8-19)"
  }
  echo "== $label: $(docker compose version --short)"
  docker compose up -d --quiet-pull >/dev/null 2>&1;            state "up -d (first)"
  docker compose up -d 2>&1 | grep -E 'web-1' | tail -1 | sed 's/^/    /'; state "up -d (nothing changed)"
  sed -i 's/v1/v2/' app.py
  docker compose up -d --build 2>&1 | grep -E 'web-1' | tail -1 | sed 's/^/    /'; state "edit, up -d --build"
  sed -i 's/v2/v3/' app.py
  docker compose up -d --build 2>&1 | grep -E 'web-1' | tail -1 | sed 's/^/    /'; state "edit, up -d --build"
  docker compose up -d 2>&1 | grep -E 'web-1' | tail -1 | sed 's/^/    /'; state "up -d (nothing changed)"
  sed -i 's/v3/v4/' app.py
  docker compose build -q 2>&1 | tail -1; docker compose up -d 2>&1 | grep -E 'web-1' | tail -1 | sed 's/^/    /'; state "edit, build, then up -d"
  docker compose down --rmi local >/dev/null 2>&1
  cd /; rm -rf "$WORK"
}

check "runner default"
COMPOSE_BAKE=false check "COMPOSE_BAKE=false"

LATEST=$(curl -s https://api.github.com/repos/docker/compose/releases/latest | sed -n 's/.*"tag_name": "\(v[^"]*\)".*/\1/p')
mkdir -p ~/.docker/cli-plugins
curl -sSL -o ~/.docker/cli-plugins/docker-compose "https://github.com/docker/compose/releases/download/$LATEST/docker-compose-linux-x86_64"
chmod +x ~/.docker/cli-plugins/docker-compose
check "latest release $LATEST"
COMPOSE_BAKE=false check "latest release $LATEST, COMPOSE_BAKE=false"
