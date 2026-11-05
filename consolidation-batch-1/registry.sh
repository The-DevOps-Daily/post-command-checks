#!/usr/bin/env bash
# Push to a local registry that needs a login, as shown in part 3 of the
# Introduction to Docker guide. Run on a throwaway machine.
set -uo pipefail

run() { echo; echo "\$ $*"; eval "$@" 2>&1; echo "[exit $?]"; }

WORK=$(mktemp -d)
cd "$WORK"
trap 'docker rm -f auth-registry >/dev/null 2>&1; docker logout localhost:5001 >/dev/null 2>&1; rm -rf "$WORK"' EXIT

REGISTRY_PASSWORD=s3cret
mkdir auth
docker run --rm --entrypoint htpasswd httpd:2.4 -Bbn ci-bot "$REGISTRY_PASSWORD" > auth/htpasswd 2>/dev/null
docker run -d --name auth-registry -p 127.0.0.1:5001:5000 -v "$PWD/auth":/auth:ro \
  -e REGISTRY_AUTH=htpasswd -e REGISTRY_AUTH_HTPASSWD_REALM=registry \
  -e REGISTRY_AUTH_HTPASSWD_PATH=/auth/htpasswd registry:3 >/dev/null
docker pull -q nginx:1.30 >/dev/null
docker tag nginx:1.30 my-nginx:1.0
sleep 2

run docker version --format "'engine {{.Server.Version}}'"
run docker tag my-nginx:1.0 localhost:5001/team/my-nginx:1.0
run docker push localhost:5001/team/my-nginx:1.0
run "echo \"\$REGISTRY_PASSWORD\" | docker login localhost:5001 -u ci-bot --password-stdin"
run docker push -q localhost:5001/team/my-nginx:1.0
run "curl -s -u ci-bot:\"\$REGISTRY_PASSWORD\" http://localhost:5001/v2/team/my-nginx/tags/list"
run curl -s http://localhost:5001/v2/team/my-nginx/tags/list
run docker logout localhost:5001
