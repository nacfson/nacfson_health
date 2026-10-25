#!/usr/bin/env bash
# Runtime smoke test for the health-frontend image under the same constraints
# as nacfson_pipeline's Deployment (deploy/projects/health/workloads/
# frontend-deployment.yaml):
#   - runAsUser/runAsGroup 10001, readOnlyRootFilesystem, capabilities drop ALL,
#     allowPrivilegeEscalation false
#   - writable emptyDirs only at /tmp, /var/cache/nginx, /var/log/nginx
#   - containerPort 8080 (Service targetPort, probes)
#   - backend reachable as Service `health-backend:8080`
#
# Usage: apps/health-web/frontend/smoke-test.sh   (needs Docker)
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IMAGE="health-frontend:smoke"
NET="health-smoke-$$"
FE="health-fe-smoke-$$"
BE="health-be-smoke-$$"
PORT=18080

cleanup() {
  docker rm -f "$FE" "$BE" > /dev/null 2>&1 || true
  docker network rm "$NET" > /dev/null 2>&1 || true
}
trap cleanup EXIT

fail() {
  echo "::error::$1"
  echo "--- frontend container logs ---"
  docker logs "$FE" 2>&1 || true
  exit 1
}

docker build -q -t "$IMAGE" "$HERE" > /dev/null
docker network create "$NET" > /dev/null

# Stub backend: answers /healthz with "ok" under the Service name nginx proxies to.
docker run -d --name "$BE" --network "$NET" --network-alias health-backend \
  busybox:1.36 sh -c 'mkdir -p /www && echo ok > /www/healthz && exec httpd -f -p 8080 -h /www' > /dev/null

docker run -d --name "$FE" --network "$NET" \
  --user 10001:10001 --read-only --cap-drop ALL --security-opt no-new-privileges \
  --tmpfs /tmp:mode=1777 --tmpfs /var/cache/nginx:mode=1777 --tmpfs /var/log/nginx:mode=1777 \
  -p "127.0.0.1:${PORT}:8080" "$IMAGE" > /dev/null

for _ in $(seq 1 30); do
  if [ "$(docker inspect -f '{{.State.Running}}' "$FE")" != "true" ]; then
    fail "frontend container exited during startup"
  fi
  if curl -fsS -o /dev/null "http://127.0.0.1:${PORT}/"; then
    break
  fi
  sleep 1
done

curl -fsS "http://127.0.0.1:${PORT}/" | grep -qi '<html' \
  || fail "GET / on 8080 did not return the SPA shell (liveness probe)"
[ "$(curl -fsS "http://127.0.0.1:${PORT}/healthz")" = "ok" ] \
  || fail "GET /healthz on 8080 was not proxied to health-backend (readiness probe)"

echo "frontend smoke test passed"
