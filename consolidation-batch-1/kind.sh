#!/usr/bin/env bash
# Kubernetes commands behind the sections that consolidation batch 1 added:
# a namespace stuck in Terminating, Service port defaults, and a failing
# init container. Installs kind and kubectl; run on a throwaway machine.
set -uo pipefail

run() { echo; echo "\$ $*"; eval "$@" 2>&1; echo "[exit $?]"; }
note() { echo; echo "# $*"; }

KIND_VERSION=v0.33.0
KUBECTL_VERSION=v1.37.1
curl -sSLo /tmp/kind "https://kind.sigs.k8s.io/dl/$KIND_VERSION/kind-linux-amd64"
curl -sSLo /tmp/kubectl "https://dl.k8s.io/release/$KUBECTL_VERSION/bin/linux/amd64/kubectl"
sudo install -m 0755 /tmp/kind /usr/local/bin/kind
sudo install -m 0755 /tmp/kubectl /usr/local/bin/kubectl
trap 'kind delete cluster --name batch1 >/dev/null 2>&1' EXIT

run kind version
run kind create cluster --name batch1 --wait 120s
run kubectl version

note "1. a namespace stuck in Terminating"
run kubectl create namespace demo
run kubectl -n demo create configmap app-config --from-literal=mode=prod
run "kubectl -n demo patch configmap app-config --type=merge -p '{\"metadata\":{\"finalizers\":[\"example.com/cleanup\"]}}'"
run kubectl delete namespace demo --wait=false
sleep 10
run kubectl get namespace demo
run "kubectl get namespace demo -o jsonpath='{range .status.conditions[*]}{.type}={.status}: {.message}{\"\n\"}{end}'"
run "kubectl api-resources --verbs=list --namespaced -o name | xargs -n 1 kubectl get --show-kind --ignore-not-found -n demo"
run kubectl delete namespace demo --force --grace-period=0
run kubectl get namespace demo
run "kubectl -n demo patch configmap app-config --type=json -p '[{\"op\":\"remove\",\"path\":\"/metadata/finalizers\"}]'"
run kubectl wait --for=delete namespace/demo --timeout=60s
run kubectl get namespace demo
run "kubectl get apiservices | awk 'NR == 1 || \$3 != \"True\"'"

note "the finalize subresource, and what it leaves behind"
run kubectl create namespace demo2
run kubectl -n demo2 create configmap app-config --from-literal=mode=prod
run "kubectl -n demo2 patch configmap app-config --type=merge -p '{\"metadata\":{\"finalizers\":[\"example.com/cleanup\"]}}'"
run kubectl delete namespace demo2 --wait=false
sleep 10
run "kubectl get namespace demo2 -o json | jq '.spec.finalizers = []' | kubectl replace --raw /api/v1/namespaces/demo2/finalize -f - | jq -r '.status.phase'"
run kubectl wait --for=delete namespace/demo2 --timeout=60s
run kubectl create namespace demo2
run kubectl -n demo2 get configmap app-config -o jsonpath="'{.metadata.finalizers}'"
run "kubectl -n demo2 patch configmap app-config --type=json -p '[{\"op\":\"remove\",\"path\":\"/metadata/finalizers\"}]'"
run kubectl delete namespace demo2

note "2. Service ports"
run kubectl create deployment web --image=nginx:1.30 --port=80
run kubectl rollout status deployment/web --timeout=120s
cat > svc.yaml <<'EOF'
apiVersion: v1
kind: Service
metadata:
  name: web
spec:
  selector:
    app: web
  ports:
    - port: 80 # no targetPort
EOF
run kubectl apply -f svc.yaml
run "kubectl get service web -o jsonpath='port={.spec.ports[0].port} targetPort={.spec.ports[0].targetPort}{\"\n\"}'"
cat > svc-lb.yaml <<'EOF'
apiVersion: v1
kind: Service
metadata:
  name: web-lb
spec:
  type: LoadBalancer
  selector:
    app: web
  ports:
    - port: 80
      targetPort: 80
---
apiVersion: v1
kind: Service
metadata:
  name: web-lb-no-nodeport
spec:
  type: LoadBalancer
  allocateLoadBalancerNodePorts: false
  selector:
    app: web
  ports:
    - port: 80
      targetPort: 80
EOF
run kubectl apply -f svc-lb.yaml
run kubectl get services web web-lb web-lb-no-nodeport
run "kubectl run probe --image=curlimages/curl:8.23.0 --restart=Never --rm -i --quiet -- curl -s -o /dev/null -w '%{http_code}\n' http://web"
run kubectl delete -f svc.yaml -f svc-lb.yaml
run kubectl delete deployment web

note "3. a failing init container"
cat > init.yaml <<'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: init-fails
spec:
  initContainers:
    - name: wait-for-db
      image: busybox:1.38.0
      command: ["sh", "-c", "echo 'db:5432 not reachable'; exit 1"]
  containers:
    - name: app
      image: nginx:1.30
EOF
run kubectl apply -f init.yaml
sleep 40
run kubectl get pod init-fails
run kubectl logs init-fails
run kubectl logs init-fails -c wait-for-db
run "kubectl get pod init-fails -o jsonpath='{.status.initContainerStatuses[0].lastState.terminated.exitCode}{\"\n\"}'"
run kubectl delete pod init-fails --wait=false
