#!/usr/bin/env bash
# The attach checks of consolidation batch 2, with a fresh container for each
# case. The first run (docker.sh) showed that killing `docker attach` also
# stopped the container; docker-rerun.sh had a bug in fresh() (the container
# name came after the image). Run on a throwaway machine.
set -uo pipefail

run() { echo; echo "\$ $*"; eval "$@" 2>&1; echo "[exit $?]"; }
note() { echo; echo "# $*"; }

cleanup() { docker ps -aq | xargs -r docker rm -f >/dev/null 2>&1; }
trap cleanup EXIT

run docker version --format "'client {{.Client.Version}}, engine {{.Server.Version}}'"

note "attach and detach"
docker pull -q alpine:3.22 >/dev/null
docker pull -q nginx:1.30 >/dev/null
fresh() { docker rm -f "$1" >/dev/null 2>&1; docker run -d --name "$1" "${@:2}" >/dev/null; sleep 1; }
state() { docker inspect -f '{{.State.Status}} exit={{.State.ExitCode}}' "$1"; }

note "a. a container started with -it: Ctrl+P Ctrl+Q detaches"
fresh shell -it alpine:3.22 sh
run "(sleep 2; printf '\\x10\\x11'; sleep 3) | timeout 8 script -qec 'docker attach shell' /dev/null; echo \"[attach exit \$?]\"; state shell"

note "b. typing exit in the attached shell ends the main process"
run "(sleep 2; printf 'exit\\r'; sleep 3) | timeout 8 script -qec 'docker attach shell' /dev/null; echo \"[attach exit \$?]\"; state shell"

note "c. custom detach keys"
fresh shell2 -it alpine:3.22 sh
run "(sleep 2; printf '\\x18'; sleep 3) | timeout 8 script -qec 'docker attach --detach-keys=ctrl-x shell2' /dev/null; echo \"[attach exit \$?]\"; state shell2"

note "d. no -it: Ctrl+P Ctrl+Q is not a detach sequence"
fresh web nginx:1.30
run "(sleep 2; printf '\\x10\\x11'; sleep 3) | timeout 6 script -qec 'docker attach --sig-proxy=false web' /dev/null; echo \"[attach exit \$?]\"; state web"

note "e. no -it, --sig-proxy=false: Ctrl+C leaves the container running"
fresh web nginx:1.30
run "(sleep 2; printf '\\x03'; sleep 3) | timeout 8 script -qec 'docker attach --sig-proxy=false web' /dev/null; echo \"[attach exit \$?]\"; sleep 1; state web"

note "f. no -it, default --sig-proxy=true: Ctrl+C stops the container"
fresh web nginx:1.30
run "(sleep 2; printf '\\x03'; sleep 3) | timeout 8 script -qec 'docker attach web' /dev/null; echo \"[attach exit \$?]\"; sleep 2; state web"
run "docker logs --tail 2 web"

note "g. killing the attach client (SIGTERM) with the default --sig-proxy=true"
fresh web nginx:1.30
run "timeout 4 docker attach web; echo \"[attach exit \$?]\"; sleep 2; state web"
fresh web nginx:1.30
run "timeout 4 docker attach --sig-proxy=false web; echo \"[attach exit \$?]\"; sleep 2; state web"

note "h. exec does not touch the main process"
fresh web nginx:1.30
run "docker exec web sh -c 'exit 3'; echo \"exec exit \$?\"; state web"
run "docker top web -o pid,args"
