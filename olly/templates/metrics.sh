#!/usr/bin/env bash
set -euo pipefail

set -a
. /tmp/olly-metrics.env
set +a

trap 'rm -f /tmp/olly-metrics.alloy /tmp/olly-metrics.sh /tmp/olly-metrics.env' EXIT

install -d -m 0750 -o root -g root /etc/alloy /var/lib/alloy-metrics/data
install -m 0644 -o root -g root /tmp/olly-metrics.alloy /etc/alloy/metrics.alloy

umask 077
printf 'AUTHENTIK_ALLOY_APP_PASSWORD=%s\n' "${PROMETHEUS_PASSWORD}" > /etc/alloy/metrics.env
chown root:root /etc/alloy/metrics.env
chmod 0600 /etc/alloy/metrics.env

docker pull "${ALLOY_IMAGE}" >/dev/null

if [[ "${PVE_EXPORTER_ENABLED}" == "true" ]]; then
  install -d -m 0750 -o root -g root /etc/pve-exporter
  cat > /etc/pve-exporter/config.yml <<PVE_CONFIG
default:
  user: ${PVE_EXPORTER_USER}
  token_name: ${PVE_EXPORTER_TOKEN_NAME}
  token_value: ${PVE_EXPORTER_TOKEN_SECRET}
  verify_ssl: false
PVE_CONFIG
  chown root:101 /etc/pve-exporter/config.yml
  chmod 0640 /etc/pve-exporter/config.yml

  docker pull --platform "${PVE_EXPORTER_PLATFORM}" "${PVE_EXPORTER_IMAGE}" >/dev/null
  docker rm -f pve-exporter >/dev/null 2>&1 || true
  docker_extra_args=()
  if [[ "${PVE_EXPORTER_TARGET}" != "" && ! "${PVE_EXPORTER_TARGET}" =~ ^[0-9]+(\.[0-9]+){3}$ && ! "${PVE_EXPORTER_TARGET}" == *:* ]]; then
    pve_exporter_target_ip="$(getent hosts "${PVE_EXPORTER_TARGET}" | awk '{ print $1; exit }')"
    [[ "${pve_exporter_target_ip}" != "" ]] && docker_extra_args+=(--add-host "${PVE_EXPORTER_TARGET}:${pve_exporter_target_ip}")
  fi

  docker run -d \
    --platform "${PVE_EXPORTER_PLATFORM}" \
    --name pve-exporter \
    --restart unless-stopped \
    --publish 127.0.0.1:9221:9221 \
    --volume /etc/resolv.conf:/etc/resolv.conf:ro \
    --volume /etc/pve-exporter/config.yml:/etc/prometheus/pve.yml:ro \
    "${docker_extra_args[@]}" \
    "${PVE_EXPORTER_IMAGE}" >/dev/null
else
  docker rm -f pve-exporter >/dev/null 2>&1 || true
fi

if [[ "${OPNSENSE_EXPORTER_ENABLED}" == "true" ]]; then
  install -d -m 0750 -o root -g root /etc/opnsense-exporter
  umask 077
  printf 'OPNSENSE_EXPORTER_OPS_API_KEY=%s\nOPNSENSE_EXPORTER_OPS_API_SECRET=%s\n' \
    "${OPNSENSE_API_KEY}" \
    "${OPNSENSE_API_SECRET}" \
    > /etc/opnsense-exporter/env
  chown root:root /etc/opnsense-exporter/env
  chmod 0600 /etc/opnsense-exporter/env

  docker pull --platform "${OPNSENSE_EXPORTER_PLATFORM}" "${OPNSENSE_EXPORTER_IMAGE}" >/dev/null
  docker rm -f opnsense-exporter >/dev/null 2>&1 || true

  opnsense_args=()
  [[ "${OPNSENSE_INSECURE}" == "true" ]] && opnsense_args+=(--opnsense.insecure)

  opnsense_address="${OPNSENSE_ADDRESS}"

  opnsense_docker_args=()
  if [[ "${opnsense_address}" != "" && ! "${opnsense_address}" =~ ^[0-9]+(\.[0-9]+){3}$ && ! "${opnsense_address}" == *:* ]]; then
    opnsense_address_ip="$(getent hosts "${opnsense_address}" | awk '{ print $1; exit }')"
    [[ "${opnsense_address_ip}" != "" ]] && opnsense_docker_args+=(--add-host "${opnsense_address}:${opnsense_address_ip}")
  fi

  docker run -d \
    --platform "${OPNSENSE_EXPORTER_PLATFORM}" \
    --name opnsense-exporter \
    --restart unless-stopped \
    --publish "127.0.0.1:${OPNSENSE_EXPORTER_LISTEN_PORT}:8080" \
    --env-file /etc/opnsense-exporter/env \
    --volume /etc/resolv.conf:/etc/resolv.conf:ro \
    "${opnsense_docker_args[@]}" \
    "${OPNSENSE_EXPORTER_IMAGE}" \
    --log.level=info \
    --log.format=logfmt \
    --exporter.instance-label="${OPNSENSE_INSTANCE}" \
    --opnsense.protocol=https \
    --opnsense.address="${opnsense_address}" \
    "${opnsense_args[@]}" >/dev/null
else
  docker rm -f opnsense-exporter >/dev/null 2>&1 || true
fi

docker rm -f alloy-metrics >/dev/null 2>&1 || true

docker_args=(
  --detach
  --name alloy-metrics
  --restart unless-stopped
  --network host
  --read-only
  --pid host
  --tmpfs /tmp:rw,nosuid,nodev,noexec,size=64m
  --env-file /etc/alloy/metrics.env
  --volume /etc/alloy/metrics.alloy:/etc/alloy/metrics.alloy:ro
  --volume /etc/alloy/metrics.env:/etc/alloy/metrics.env:ro
  --volume /var/lib/alloy-metrics/data:/var/lib/alloy/data
  --volume /:/host/rootfs:ro,rslave
  --volume /proc:/host/proc:ro
  --volume /sys:/host/sys:ro
)

[[ -d /run/udev/data ]] && docker_args+=(--volume /run/udev/data:/host/run/udev/data:ro)

docker run "${docker_args[@]}" \
  "${ALLOY_IMAGE}" \
  run \
  --server.http.listen-addr=0.0.0.0:12346 \
  --storage.path=/var/lib/alloy/data \
  /etc/alloy/metrics.alloy >/dev/null
