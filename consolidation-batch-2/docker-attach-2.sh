#!/usr/bin/env bash
# Follow-up to docker-attach.sh, whose last case hung: with --sig-proxy=false,
# `docker attach` ignored SIGTERM from `timeout`, and the job was cancelled
# after 20 minutes. This run uses `timeout -s KILL` and checks the
# alternatives: docker logs -f with Ctrl+C, and docker exec. Run on a
# throwaway machine.
set -uo pipefail

run() { echo; echo "\$ $*"; eval "$@" 2>&1; echo "[exit $?]"; }
note() { echo; echo "# $*"; }

cleanup() { docker ps -aq | xargs -r docker rm -f >/dev/null 2>&1; }
trap cleanup EXIT

run docker version --format "'client {{.Client.Version}}, engine {{.Server.Version}}'"
docker pull -q nginx:1.30 >/dev/null
fresh() { docker rm -f "$1" >/dev/null 2>&1; docker run -d --name "$1" "${@:2}" >/dev/null; sleep 1; }
state() { docker inspect -f '{{.State.Status}} exit={{.State.ExitCode}}' "$1"; }

note "a. --sig-proxy=false: SIGTERM and SIGINT to the attach client"
fresh web nginx:1.30
run "timeout -s TERM -k 3 4 docker attach --sig-proxy=false web; echo \"[attach exit \$?]\"; state web"
run "timeout -s INT -k 3 4 docker attach --sig-proxy=false web; echo \"[attach exit \$?]\"; state web"

note "b. docker logs -f, then Ctrl+C"
fresh web nginx:1.30
run "(sleep 2; printf '\\x03'; sleep 3) | timeout -s KILL 8 script -qec 'docker logs -f --tail 1 web' /dev/null; echo \"[logs exit \$?]\"; state web"

note "c. exec does not touch the main process"
run "docker exec web sh -c 'exit 3'; echo \"exec exit \$?\"; state web"
