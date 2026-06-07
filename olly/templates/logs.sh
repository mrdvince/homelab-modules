#!/usr/bin/env bash
set -euo pipefail

set -a
. /tmp/olly.env
set +a

trap 'rm -f /tmp/olly-logs.alloy /tmp/olly-logs.sh /tmp/olly.env' EXIT

install -d -m 0750 -o root -g root /etc/alloy /var/lib/alloy-logs/data
install -m 0644 -o root -g root /tmp/olly-logs.alloy /etc/alloy/logs.alloy

umask 077
printf 'LOKI_USERNAME=%s\nAUTHENTIK_ALLOY_APP_PASSWORD=%s\n' \
  "${LOKI_USERNAME}" \
  "${LOKI_PASSWORD}" \
  > /etc/alloy/logs.env
chown root:root /etc/alloy/logs.env
chmod 0600 /etc/alloy/logs.env

docker pull "${ALLOY_IMAGE}" >/dev/null
docker rm -f alloy-logs >/dev/null 2>&1 || true

docker_args=(
  --detach
  --name alloy-logs
  --restart unless-stopped
  --read-only
  --tmpfs /tmp:rw,nosuid,nodev,noexec,size=64m
  --publish 127.0.0.1:12345:12345
  --env-file /etc/alloy/logs.env
  --volume /etc/alloy/logs.alloy:/etc/alloy/logs.alloy:ro
  --volume /etc/alloy/logs.env:/etc/alloy/logs.env:ro
  --volume /var/lib/alloy-logs/data:/var/lib/alloy/data
  --volume /var/log:/var/log:ro
)

[[ -d /var/lib/docker/containers ]] && docker_args+=(--volume /var/lib/docker/containers:/var/lib/docker/containers:ro)
[[ -d /run/log/journal ]] && docker_args+=(--volume /run/log/journal:/run/log/journal:ro)
[[ -d /var/log/journal ]] && docker_args+=(--volume /var/log/journal:/var/log/journal:ro)
[[ -f /etc/machine-id ]] && docker_args+=(--volume /etc/machine-id:/etc/machine-id:ro)

docker run "${docker_args[@]}" \
  "${ALLOY_IMAGE}" \
  run \
  --server.http.listen-addr=0.0.0.0:12345 \
  --storage.path=/var/lib/alloy/data \
  /etc/alloy/logs.alloy >/dev/null
