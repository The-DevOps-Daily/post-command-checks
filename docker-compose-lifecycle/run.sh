#!/usr/bin/env bash
# Records which Docker Compose command applies which kind of change:
# code, environment, image tag, same tag with a new image. Also covers
# shells, dependencies, and what `down` removes.
set -uo pipefail

run() { echo; echo "\$ $*"; eval "$@" 2>&1; echo "[exit $?]"; }
note() { echo; echo "# $*"; }
cid() { docker compose ps -q "$1" | cut -c1-12; }

# Pin the Compose release so the transcript is reproducible. The runner's own
# Compose (2.38.2) mislabels bake-built images; see build-recreate-check.sh.
COMPOSE_VERSION=v5.6.0
mkdir -p ~/.docker/cli-plugins
curl -sSL -o ~/.docker/cli-plugins/docker-compose \
  "https://github.com/docker/compose/releases/download/$COMPOSE_VERSION/docker-compose-linux-$(uname -m)"
chmod +x ~/.docker/cli-plugins/docker-compose

WORK=$(mktemp -d)
cd "$WORK"
trap 'docker compose down -v --remove-orphans >/dev/null 2>&1; docker rm -f cache-plain >/dev/null 2>&1; docker volume rm plain-data >/dev/null 2>&1; rm -rf "$WORK"' EXIT

cat > Dockerfile <<'EOF'
FROM python:3.13-alpine
WORKDIR /app
COPY app.py .
CMD ["python", "-u", "app.py"]
EOF

cat > app.py <<'EOF'
import http.server, os
MSG = "v1"
class H(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        body = f"{MSG} greeting={os.environ.get('GREETING', 'unset')}\n".encode()
        self.send_response(200); self.end_headers(); self.wfile.write(body)
    def log_message(self, *a): pass
http.server.HTTPServer(("", 8000), H).serve_forever()
EOF

cat > compose.yaml <<'EOF'
name: shop
services:
  web:
    build: .
    ports:
      - "8000:8000"
    environment:
      GREETING: hello
    depends_on:
      - cache
  cache:
    image: redis:7.2-alpine
    volumes:
      - cache-data:/data
volumes:
  cache-data:
EOF

wait_web() { for _ in $(seq 1 30); do curl -sf localhost:8000 >/dev/null && return 0; sleep 1; done; return 1; }

note "versions"
run docker version --format "'Docker {{.Server.Version}}'"
run docker compose version

note "first start: builds web, pulls cache"
run docker compose up -d --quiet-pull
wait_web
run curl -s localhost:8000
run docker compose ps --format "'table {{.Service}}\t{{.Image}}\t{{.Status}}'"

note "1. code change: edit app.py, then try restart, up -d, up -d --build"
run "sed -i 's/MSG = \"v1\"/MSG = \"v2\"/' app.py"
BEFORE=$(cid web)
run docker compose restart web
wait_web
run curl -s localhost:8000
echo "web container before: $BEFORE  after restart: $(cid web)"
run docker compose up -d
wait_web
run curl -s localhost:8000
run docker compose up -d --build web
wait_web
run curl -s localhost:8000
echo "web container before: $BEFORE  after up --build: $(cid web)"

note "2. environment change in compose.yaml: restart vs up -d"
run "sed -i 's/GREETING: hello/GREETING: hi/' compose.yaml"
run docker compose restart web
wait_web
run curl -s localhost:8000
run docker compose up -d
wait_web
run curl -s localhost:8000

note "3. nothing changed: up -d leaves it, --force-recreate replaces it"
BEFORE=$(cid web)
run docker compose up -d
echo "web container before: $BEFORE  after up -d: $(cid web)"
run docker compose up -d --force-recreate web
wait_web
echo "web container before: $BEFORE  after --force-recreate: $(cid web)"

note "4. dependencies: up web starts a stopped cache, --no-deps does not"
run docker compose stop cache web
run docker compose up -d web
run docker compose ps --format "'table {{.Service}}\t{{.Status}}'"
run docker compose stop cache web
run docker compose up -d --no-deps web
run docker compose ps -a --format "'table {{.Service}}\t{{.Status}}'"
run docker compose up -d

note "5. build cache: normal build vs --no-cache"
run "docker compose build web 2>&1 | grep -E 'CACHED|DONE|exporting' | head -8"
run "docker compose build --no-cache web 2>&1 | grep -E 'CACHED|DONE|exporting' | head -8"

note "6. image upgrade with a new tag: data in the named volume survives"
run docker compose exec -T cache redis-cli SET orders 42
run docker compose exec -T cache redis-server --version
CACHE_BEFORE=$(cid cache); WEB_BEFORE=$(cid web)
run "sed -i 's/redis:7.2-alpine/redis:7.4-alpine/' compose.yaml"
run docker compose up -d --quiet-pull
sleep 2
run docker compose exec -T cache redis-server --version
run docker compose exec -T cache redis-cli GET orders
echo "cache container before: $CACHE_BEFORE  after: $(cid cache)"
echo "web container before: $WEB_BEFORE  after: $(cid web)"

note "6b. rolling back after the new version wrote its data"
run "sed -i 's/redis:7.4-alpine/redis:7.2-alpine/' compose.yaml"
run docker compose up -d --quiet-pull
sleep 3
run docker compose ps -a --format "'table {{.Service}}\t{{.Image}}\t{{.Status}}'"
run "docker compose logs cache 2>&1 | grep -iE 'rdb|fatal|error' | head -3"
run "sed -i 's/redis:7.2-alpine/redis:7.4-alpine/' compose.yaml"
run docker compose up -d
sleep 2
run docker compose exec -T cache redis-cli GET orders

note "7. same tag, new image: up -d recreates only when the tag points at a new image"
note "simulated: a local tag that we re-point, as a registry push to the same tag would"
run docker tag redis:7.4-alpine shop/cache:stable
run "sed -i 's#redis:7.4-alpine#shop/cache:stable#' compose.yaml"
run docker compose up -d
sleep 2
run docker compose exec -T cache redis-server --version
run docker pull -q redis:8.0-alpine
run docker tag redis:8.0-alpine shop/cache:stable
note "the tag now points at 8.0, the running container still runs 7.4"
run docker compose exec -T cache redis-server --version
run docker compose up -d
sleep 2
run docker compose exec -T cache redis-server --version
run docker compose exec -T cache redis-cli GET orders
note "a real pull of a tag that has not changed"
run "sed -i 's#shop/cache:stable#redis:8.0-alpine#' compose.yaml"
run docker compose up -d
run docker compose pull cache
run docker compose up -d

note "8. plain docker run: pull, stop, rm, run with the same volume"
run docker run -d --name cache-plain -v plain-data:/data redis:7.2-alpine
sleep 2
run docker exec cache-plain redis-cli SET orders 42
run docker pull -q redis:7.4-alpine
run docker stop cache-plain
run docker rm cache-plain
run docker run -d --name cache-plain -v plain-data:/data redis:7.4-alpine
sleep 2
run docker exec cache-plain redis-server --version
run docker exec cache-plain redis-cli GET orders

note "9. shells"
run docker compose exec -T web sh -c "'hostname; id -un; ls /app'"
run docker compose exec -T web bash
run docker compose stop web
run docker compose exec -T web sh
run docker compose run --rm -T web sh -c "'echo new container: \$(hostname); cat /app/app.py | head -2'"
run docker compose up -d

note "10. a container that crashes on start: exec cannot reach it, run --entrypoint can"
run "sed -i 's/import http.server, os/import http.server, os, missing_module/' app.py"
run docker compose up -d --build web
sleep 3
run docker compose ps -a --format "'table {{.Service}}\t{{.Status}}'"
run docker compose exec -T web sh
run docker compose logs --tail 3 web
run docker compose run --rm -T --no-deps --entrypoint sh web -c "'head -1 /app/app.py'"
run "sed -i 's/, missing_module//' app.py"
run docker compose up -d --build web

note "11. down keeps named volumes, down -v removes them"
run docker compose down
run docker volume ls --filter name=shop_cache-data --format "'{{.Name}}'"
run docker compose up -d
sleep 2
run docker compose exec -T cache redis-cli GET orders
run docker compose down -v
run docker volume ls --filter name=shop_cache-data --format "'{{.Name}}'"
