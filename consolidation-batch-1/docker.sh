#!/usr/bin/env bash
# Docker commands behind the sections that consolidation batch 1 added to
# existing DevOps Daily posts and guide parts. Run on a throwaway machine.
set -uo pipefail

run() { echo; echo "\$ $*"; eval "$@" 2>&1; echo "[exit $?]"; }
note() { echo; echo "# $*"; }

WORK=$(mktemp -d)
cd "$WORK"
cleanup() {
  docker rm -f web api client cfg logs-demo registry auth-registry sh-plain sh-exec >/dev/null 2>&1
  docker compose -p batch1 down -v --remove-orphans >/dev/null 2>&1
  docker network rm batch1-net >/dev/null 2>&1
  docker volume rm named-data >/dev/null 2>&1
  sudo rm -rf "$WORK"
}
trap cleanup EXIT

run docker version --format "'client {{.Client.Version}}, engine {{.Server.Version}}'"
run docker compose version

note "1. EXPOSE, -p and -P"
run docker pull -q nginx:1.30
run "docker image inspect -f '{{json .Config.ExposedPorts}}' nginx:1.30"
run docker run -d --name web -P nginx:1.30
run docker port web
run docker rm -f web

note "a port that no image EXPOSEs is still reachable on a shared network"
run docker network create batch1-net
run docker run -d --name api --network batch1-net python:3.13-alpine python -m http.server 9000
run "docker image inspect -f '{{json .Config.ExposedPorts}}' python:3.13-alpine"
sleep 2
run docker run --rm --network batch1-net curlimages/curl:8.23.0 -s -o /dev/null -w "'%{http_code}\n'" http://api:9000/
run docker rm -f api

note "2. a single-file bind mount"
echo "mode=v1" > app.conf
run docker run -d --name cfg -v "\"$PWD/app.conf\":/etc/app.conf:ro" alpine:3.22 sleep 300
run docker exec cfg cat /etc/app.conf
run ls -i app.conf
run "echo 'debug=false' >> app.conf"
run docker exec cfg cat /etc/app.conf
run "sed -i 's/v1/v2/' app.conf"
run ls -i app.conf
run cat app.conf
run docker exec cfg cat /etc/app.conf
run docker restart cfg
run docker exec cfg cat /etc/app.conf
run docker rm -f cfg

note "a missing source file"
run docker run --rm -v "\"$PWD/missing.conf\":/etc/missing.conf" alpine:3.22 ls -ld /etc/missing.conf
run ls -ld missing.conf
run docker run --rm --mount "type=bind,src=$PWD/typo.conf,dst=/etc/typo.conf" alpine:3.22 true

note "3. more than one command at start, with and without exec"
mkdir plain exec
cat > plain/Dockerfile <<'EOF'
FROM nginx:1.30
CMD ["sh", "-c", "echo setup done && nginx -g 'daemon off;'"]
EOF
cat > exec/Dockerfile <<'EOF'
FROM nginx:1.30
CMD ["sh", "-c", "echo setup done && exec nginx -g 'daemon off;'"]
EOF
run docker build -q -t sh-plain plain
run docker build -q -t sh-exec exec
run docker run -d --name sh-plain sh-plain
run docker run -d --name sh-exec sh-exec
sleep 2
run "docker exec sh-plain cat /proc/1/cmdline | tr '\0' ' '; echo"
run "docker exec sh-exec cat /proc/1/cmdline | tr '\0' ' '; echo"
run "s=\$(date +%s); docker stop sh-plain >/dev/null; echo \"sh-plain stopped in \$(( \$(date +%s) - s ))s, exit code \$(docker inspect -f '{{.State.ExitCode}}' sh-plain)\""
run "s=\$(date +%s); docker stop sh-exec >/dev/null; echo \"sh-exec stopped in \$(( \$(date +%s) - s ))s, exit code \$(docker inspect -f '{{.State.ExitCode}}' sh-exec)\""
run docker rm -f sh-plain sh-exec

note "4. Compose: build from a Dockerfile, a one-off migrate service, a command override"
mkdir app
cat > app/Dockerfile <<'EOF'
FROM python:3.13-alpine
WORKDIR /app
CMD ["python", "-m", "http.server", "8000"]
EOF
cat > compose.yaml <<'EOF'
services:
  migrate:
    image: alpine:3.22
    command: sh -c "echo applying migrations && sleep 2 && echo migrations done"
  app:
    build: ./app
    image: batch1-app:1.0
    command: sh -c "echo warming cache && exec python -m http.server 8000"
    depends_on:
      migrate:
        condition: service_completed_successfully
    ports:
      - "127.0.0.1:8000:8000"
EOF
run docker compose -p batch1 build
run docker compose -p batch1 up -d
run "docker compose -p batch1 ps -a --format 'table {{.Service}}\t{{.Status}}'"
run docker compose -p batch1 logs --no-color migrate app
run "docker image ls batch1-app --format '{{.Repository}}:{{.Tag}}'"
run docker compose -p batch1 down
note "the old top-level version key"
printf 'version: "3.8"\nservices:\n  one:\n    image: alpine:3.22\n' > old-compose.yaml
run docker compose -f old-compose.yaml config -q

note "5. clear a json-file log"
run docker run -d --name logs-demo alpine:3.22 sh -c "'i=0; while true; do i=\$((i+1)); echo line \$i; sleep 0.01; done'"
sleep 5
run "docker inspect -f '{{.HostConfig.LogConfig.Type}}' logs-demo"
run "LOG=\$(docker inspect -f '{{.LogPath}}' logs-demo); echo \$LOG"
run "sudo du -h \"\$(docker inspect -f '{{.LogPath}}' logs-demo)\""
run "sudo truncate -s 0 \"\$(docker inspect -f '{{.LogPath}}' logs-demo)\""
sleep 1
run "sudo du -h \"\$(docker inspect -f '{{.LogPath}}' logs-demo)\""
run docker logs --tail 2 logs-demo
note "deleting the file instead"
run "sudo rm \"\$(docker inspect -f '{{.LogPath}}' logs-demo)\""
sleep 1
run docker logs --tail 2 logs-demo
run "sudo ls -l /proc/\$(pidof dockerd)/fd | grep -c 'json.log (deleted)'"
run docker rm -f logs-demo

note "6. disk space"
run "docker info -f '{{.DockerRootDir}}'"
run "df -h \"\$(docker info -f '{{.DockerRootDir}}')\""
run docker system df
run docker volume create named-data
run docker run --name anon -v /data alpine:3.22 true
run docker rm anon
run "docker volume ls --format '{{.Name}}' | awk '{ print (length(\$0) == 64 ? \"(anonymous) \" : \"\") \$0 }'"
run docker system prune -f --volumes
run "docker volume ls --format '{{.Name}}' | grep -c . ; docker volume ls --format '{{.Name}}' | grep named-data"
run docker builder prune -f

note "7. push to a private registry"
run docker run -d --name registry -p 127.0.0.1:5000:5000 registry:3
sleep 2
run docker tag batch1-app:1.0 localhost:5000/team/hello-api:1.0
run docker push -q localhost:5000/team/hello-api:1.0
run curl -s http://localhost:5000/v2/_catalog
run curl -s http://localhost:5000/v2/team/hello-api/tags/list
note "a name without the registry host goes to Docker Hub"
run docker tag batch1-app:1.0 team/hello-api:1.0
run docker push team/hello-api:1.0
note "a registry with a password"
mkdir auth
docker run --rm --entrypoint htpasswd httpd:2.4 -Bbn ci-bot s3cret > auth/htpasswd 2>/dev/null
run docker run -d --name auth-registry -p 127.0.0.1:5001:5000 -v "\"$PWD/auth\":/auth:ro" -e REGISTRY_AUTH=htpasswd -e REGISTRY_AUTH_HTPASSWD_REALM=registry -e REGISTRY_AUTH_HTPASSWD_PATH=/auth/htpasswd registry:3
sleep 2
run docker tag batch1-app:1.0 localhost:5001/team/hello-api:1.0
run docker push localhost:5001/team/hello-api:1.0
run "echo s3cret | docker login localhost:5001 -u ci-bot --password-stdin"
run docker push -q localhost:5001/team/hello-api:1.0
run "jq '.auths | keys' ~/.docker/config.json; jq -r '.auths[\"localhost:5001\"].auth' ~/.docker/config.json | base64 -d; echo"
run docker logout localhost:5001
