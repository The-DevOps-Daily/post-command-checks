#!/usr/bin/env bash
# What docker logs shows after the json-file log of a running container is
# truncated, and what brings it back. Run on a throwaway machine.
set -uo pipefail

run() { echo; echo "\$ $*"; eval "$@" 2>&1; echo "[exit $?]"; }
note() { echo; echo "# $*"; }
logpath() { docker inspect -f '{{.LogPath}}' "$1"; }
trap 'docker rm -f logs-demo logs-capped >/dev/null 2>&1' EXIT

run docker version --format "'engine {{.Server.Version}}'"
run docker run -d --name logs-demo alpine:3.22 sh -c "'i=0; while true; do i=\$((i+1)); echo line \$i; sleep 0.01; done'"
sleep 5
run "docker logs logs-demo | wc -l"
run "sudo stat -c 'size=%s bytes, blocks=%b' \"\$(logpath logs-demo)\""
run "sudo truncate -s 0 \"\$(logpath logs-demo)\""
sleep 3
run "sudo stat -c 'size=%s bytes, blocks=%b' \"\$(logpath logs-demo)\""
run "sudo head -c 120 \"\$(logpath logs-demo)\" | od -c | head -3"
run "docker logs logs-demo | wc -l"
run docker logs --tail 2 logs-demo
run "docker logs --since 2s logs-demo | tail -2"
note "restart the container"
run docker restart logs-demo
sleep 2
run "docker logs logs-demo | wc -l"
run docker logs --tail 2 logs-demo

note "a capped json-file log rotates instead"
run docker run -d --name logs-capped --log-opt max-size=1m --log-opt max-file=2 alpine:3.22 sh -c "'i=0; while true; do i=\$((i+1)); echo line \$i padding-padding-padding-padding-padding-padding; done'"
sleep 15
run "sudo ls -l \$(dirname \"\$(logpath logs-capped)\") | grep json"
run docker logs --tail 1 logs-capped
