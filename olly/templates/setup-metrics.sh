#!/usr/bin/env bash
set -euo pipefail

set -a
. /tmp/olly-metrics.env
set +a

export DEBIAN_FRONTEND=noninteractive
apt-get update >/dev/null
apt-get install -y alloy ca-certificates >/dev/null

install -d -m 0750 -o root -g alloy /etc/alloy
install -d -m 0755 /etc/systemd/system

install -m 0644 -o root -g root /tmp/olly-metrics.alloy /etc/alloy/metrics.alloy
chown root:alloy /etc/alloy
chmod 0750 /etc/alloy
chmod 0644 /etc/alloy/metrics.alloy

umask 077
{
  printf 'AUTHENTIK_ALLOY_APP_PASSWORD=%s\n' "${PROMETHEUS_PASSWORD}"
} > /etc/alloy/metrics.env
chown root:root /etc/alloy/metrics.env
chmod 0600 /etc/alloy/metrics.env

if [[ "${PVE_EXPORTER_ENABLED}" == "true" ]]; then
  if ! command -v docker >/dev/null 2>&1; then
    echo "docker is required for pve-exporter but is not installed" >&2
    exit 1
  fi

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

  systemctl enable --now docker >/dev/null
  docker pull --platform "${PVE_EXPORTER_PLATFORM}" "${PVE_EXPORTER_IMAGE}" >/dev/null
  image_platform="$(docker image inspect "${PVE_EXPORTER_IMAGE}" --format '{{.Os}}/{{.Architecture}}')"
  if [ "${image_platform}" != "${PVE_EXPORTER_PLATFORM}" ]; then
    echo "pve-exporter image ${PVE_EXPORTER_IMAGE} resolved to ${image_platform}, expected ${PVE_EXPORTER_PLATFORM}" >&2
    exit 1
  fi
  docker rm -f pve-exporter >/dev/null 2>&1 || true
  docker_extra_args=()
  if [[ "${PVE_EXPORTER_TARGET}" != "" && ! "${PVE_EXPORTER_TARGET}" =~ ^[0-9]+(\.[0-9]+){3}$ && ! "${PVE_EXPORTER_TARGET}" == *:* ]]; then
    pve_exporter_target_ip="$(getent hosts "${PVE_EXPORTER_TARGET}" | awk '{ print $1; exit }')"
    if [[ "${pve_exporter_target_ip}" != "" ]]; then
      docker_extra_args+=(--add-host "${PVE_EXPORTER_TARGET}:${pve_exporter_target_ip}")
    fi
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

cat > /etc/systemd/system/alloy-metrics.service <<'SERVICE'
[Unit]
Description=Grafana Alloy metrics collector
Documentation=https://grafana.com/docs/alloy
Wants=network-online.target
After=network-online.target

[Service]
Restart=always
User=alloy
Environment=HOSTNAME=%H
EnvironmentFile=/etc/alloy/metrics.env
WorkingDirectory=/var/lib/alloy
ExecStart=/usr/bin/alloy run --server.http.listen-addr=127.0.0.1:12346 --storage.path=/var/lib/alloy-metrics/data /etc/alloy/metrics.alloy
ExecReload=/usr/bin/env kill -HUP $MAINPID
TimeoutStopSec=20s

[Install]
WantedBy=multi-user.target
SERVICE

install -d -m 0750 -o alloy -g alloy /var/lib/alloy-metrics/data
alloy fmt --write /etc/alloy/metrics.alloy
systemctl daemon-reload
systemctl reset-failed alloy-metrics || true
systemctl enable alloy-metrics >/dev/null
systemctl restart alloy-metrics
sleep 5
systemctl is-active alloy-metrics

rm -f /tmp/olly-metrics.alloy /tmp/olly-metrics-setup.sh /tmp/olly-metrics.env
