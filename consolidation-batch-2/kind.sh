#!/usr/bin/env bash
# Kubernetes commands behind the Secret decoding section that consolidation
# batch 2 added to the Kubernetes guide. Installs kind and kubectl; run on a
# throwaway machine.
set -uo pipefail

run() { echo; echo "\$ $*"; eval "$@" 2>&1; echo "[exit $?]"; }
note() { echo; echo "# $*"; }

KIND_VERSION=v0.33.0
KUBECTL_VERSION=v1.37.1
curl -sSLo /tmp/kind "https://kind.sigs.k8s.io/dl/$KIND_VERSION/kind-linux-amd64"
curl -sSLo /tmp/kubectl "https://dl.k8s.io/release/$KUBECTL_VERSION/bin/linux/amd64/kubectl"
sudo install -m 0755 /tmp/kind /usr/local/bin/kind
sudo install -m 0755 /tmp/kubectl /usr/local/bin/kubectl
WORK=$(mktemp -d)
cd "$WORK"
trap 'kind delete cluster --name batch2 >/dev/null 2>&1; rm -rf "$WORK"' EXIT

run kind version
run kind create cluster --name batch2 --wait 120s
run kubectl version

note "decode one key, then all keys"
run "kubectl create secret generic db-credentials --from-literal=username=app --from-literal=password='s3cr3t-Pa55'"
run "kubectl get secret db-credentials -o jsonpath='{.data.password}' | base64 -d; echo"
run "kubectl get secret db-credentials -o go-template='{{range \$k, \$v := .data}}{{\$k}}={{\$v | base64decode}}{{\"\\n\"}}{{end}}'"
run "kubectl get secret db-credentials -o json | jq -r '.data | map_values(@base64d)'"

note "the trailing newline from echo"
run "echo 's3cr3t-Pa55' > password.txt && kubectl create secret generic db-file --from-file=password=password.txt"
run "kubectl get secret db-file -o jsonpath='{.data.password}'; echo"
run "kubectl get secret db-file -o jsonpath='{.data.password}' | base64 -d | od -c"
run "echo 's3cr3t-Pa55' | base64; printf '%s' 's3cr3t-Pa55' | base64"
run "printf '%s' 's3cr3t-Pa55' > password.txt && kubectl create secret generic db-file2 --from-file=password=password.txt"
run "kubectl get secret db-file2 -o jsonpath='{.data.password}' | base64 -d | od -c"

note "stringData is stored as data"
cat > secret.yaml <<'EOF'
apiVersion: v1
kind: Secret
metadata:
  name: api-token
type: Opaque
stringData:
  token: tok-123
EOF
run kubectl apply -f secret.yaml
run "kubectl get secret api-token -o jsonpath='{.data}'; echo"
