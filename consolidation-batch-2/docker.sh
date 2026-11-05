#!/usr/bin/env bash
# Docker commands behind the sections that consolidation batch 2 added to
# existing DevOps Daily posts and guide parts, plus the Python standard library
# interface listing. Run on a throwaway machine: it removes every container
# and image on it.
set -uo pipefail

run() { echo; echo "\$ $*"; eval "$@" 2>&1; echo "[exit $?]"; }
note() { echo; echo "# $*"; }

WORK=$(mktemp -d)
cd "$WORK"
cleanup() {
  docker ps -aq | xargs -r docker rm -f >/dev/null 2>&1
  rm -rf "$WORK"
}
trap cleanup EXIT

run docker version --format "'client {{.Client.Version}}, engine {{.Server.Version}}'"
run "docker info --format '{{.Driver}} {{json .DriverStatus}}'"

note "0. local IPv4 addresses with the Python standard library"
cat > ifaces.py <<'EOF'
import fcntl
import socket
import struct

SIOCGIFADDR = 0x8915  # Linux: get the IPv4 address of one interface

def ipv4_addresses():
    """Map interface name to IPv4 address, standard library only (Linux)."""
    result = {}
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as s:
        for _, name in socket.if_nameindex():
            try:
                packed = fcntl.ioctl(s.fileno(), SIOCGIFADDR,
                                     struct.pack("256s", name.encode()[:15]))
            except OSError:  # interface is down or has no IPv4 address
                continue
            result[name] = socket.inet_ntoa(packed[20:24])
    return result

for name, ip in ipv4_addresses().items():
    print(f"{name}: {ip}")
EOF
cat > route.py <<'EOF'
import socket

with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as s:
    s.connect(("192.0.2.1", 9))  # UDP connect sends no packet
    print(s.getsockname()[0])
EOF
run python3 --version
run "python3 -c 'import socket; print(socket.gethostbyname(socket.gethostname()))'"
run "grep -v '^#' /etc/hosts"
run python3 ifaces.py
run python3 route.py
run "ip -4 -br addr"
run "ip route get 192.0.2.1"

note "1. see what is inside an image"
run docker pull -q nginx:1.30
run docker pull -q hello-world
run docker pull -q alpine:3.22
run "docker image inspect -f 'Cmd={{json .Config.Cmd}} Entrypoint={{json .Config.Entrypoint}} WorkingDir={{.Config.WorkingDir}}' nginx:1.30"
run "docker run --rm hello-world sh"
run "cid=\$(docker create hello-world) && docker export \$cid | tar -t; docker rm \$cid"
run "cid=\$(docker create nginx:1.30) && docker cp \$cid:/etc/nginx/conf.d/default.conf . && head -4 default.conf; docker rm \$cid"
run "docker run --rm --entrypoint ls nginx:1.30 -la /etc/nginx"

note "2. delete all local images"
run docker tag alpine:3.22 myapp:dev
run docker run -d --name keep nginx:1.30
run docker create --name stopped hello-world
run docker image ls
run "docker images -q"
run "docker rmi \$(docker images -q)"
run docker image ls
run docker pull -q alpine:3.22
run docker tag alpine:3.22 myapp:dev
run docker image prune -a -f
run docker image ls
run "docker ps -aq | xargs -r docker rm -f"
run docker image prune -a -f
run docker image ls
run "docker rmi \$(docker images -q)"
run "docker images -q | xargs -r docker rmi"

note "3. exec vs attach, detach keys, Ctrl+C"
run docker pull -q alpine:3.22
run docker pull -q nginx:1.30
run docker run -dit --name shell alpine:3.22 sh
run "docker exec shell sh -c 'exit 3'; echo \"exec exit \$?\"; docker inspect -f '{{.State.Status}}' shell"
run "(sleep 2; printf '\\x10\\x11'; sleep 4) | timeout 10 script -qec 'docker attach shell' /dev/null; echo \"[attach exit \$?]\"; docker inspect -f '{{.State.Status}}' shell"
run "(sleep 2; printf 'exit\\r'; sleep 4) | timeout 10 script -qec 'docker attach shell' /dev/null; echo \"[attach exit \$?]\"; docker inspect -f '{{.State.Status}} exit={{.State.ExitCode}}' shell"
run docker run -d --name web nginx:1.30
run "(sleep 2; printf '\\x10\\x11'; sleep 4) | timeout 10 script -qec 'docker attach web' /dev/null; echo \"[attach exit \$?]\"; docker inspect -f '{{.State.Status}}' web"
run "(sleep 2; printf '\\x03'; sleep 4) | timeout 10 script -qec 'docker attach --sig-proxy=false web' /dev/null; echo \"[attach exit \$?]\"; docker inspect -f '{{.State.Status}}' web"
run "(sleep 2; printf '\\x03'; sleep 4) | timeout 10 script -qec 'docker attach web' /dev/null; echo \"[attach exit \$?]\"; sleep 2; docker inspect -f '{{.State.Status}} exit={{.State.ExitCode}}' web"
run "docker logs --tail 4 web"
run "docker rm -f shell web"

note "4. save and load, export and import"
run "docker image inspect -f '{{.Id}} {{json .RepoDigests}}' nginx:1.30"
run "docker save nginx:1.30 | wc -c"
run "docker save nginx:1.30 | gzip > nginx.tar.gz && ls -l nginx.tar.gz"
run docker rmi nginx:1.30
run docker load -i nginx.tar.gz
run "docker image inspect -f '{{.Id}} {{json .RepoDigests}}' nginx:1.30"
run "docker create --name exp nginx:1.30 && docker export exp | docker import - nginx-flat:1.30; docker rm exp"
run "docker image inspect -f 'Cmd={{json .Config.Cmd}} Entrypoint={{json .Config.Entrypoint}} ExposedPorts={{json .Config.ExposedPorts}}' nginx-flat:1.30"
run docker run --rm nginx-flat:1.30
run "docker history --format '{{.CreatedBy}}' nginx-flat:1.30"

note "5. publish many ports"
run "docker run -d --name multi -p 8080-8082:80-82 nginx:1.30 && docker port multi"
run docker run -d --name bad -p 8090-8092:80-81 nginx:1.30
run "docker run -d --name pick1 -p 9000-9005:80 nginx:1.30 && docker run -d --name pick2 -p 9000-9005:80 nginx:1.30 && docker port pick1 && docker port pick2"
run docker run -d --name same -p 8080:80 nginx:1.30
cat > Dockerfile <<'EOF'
FROM nginx:1.30
EXPOSE 8443 9229/tcp 5353/udp
EOF
run docker build -q -t multi-expose .
run "docker image inspect -f '{{json .Config.ExposedPorts}}' multi-expose"
run "docker run -d --name allports -P multi-expose && docker port allports"
