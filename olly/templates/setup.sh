#!/usr/bin/env bash
set -euo pipefail

set -a
. /tmp/olly.env
set +a

install -d -m 0755 /etc/systemd/system
install -d -m 0755 /etc/apt/keyrings

export DEBIAN_FRONTEND=noninteractive
apt-get update >/dev/null
apt-get install -y acl gpg wget ca-certificates >/dev/null

tmp_key="$(mktemp)"
wget -q -O "${tmp_key}" https://apt.grafana.com/gpg-full.key
gpg --show-keys --with-fingerprint "${tmp_key}" | grep -q "B53A E77B ADB6 30A6 8304  6005 963F A277 1045 8545"
gpg --dearmor < "${tmp_key}" > /etc/apt/keyrings/grafana.gpg
rm -f "${tmp_key}"
chmod 0644 /etc/apt/keyrings/grafana.gpg

printf '%s\n' "deb [signed-by=/etc/apt/keyrings/grafana.gpg] https://apt.grafana.com stable main" > /etc/apt/sources.list.d/grafana.list
apt-get update >/dev/null
apt-get install -y alloy rsyslog >/dev/null
systemctl enable --now rsyslog >/dev/null

install -d -m 0750 -o root -g alloy /etc/alloy
install -m 0644 -o root -g root /tmp/olly-logs.alloy /etc/alloy/logs.alloy

umask 077
{
  printf 'LOKI_USERNAME=%s\n' "${LOKI_USERNAME}"
  printf 'AUTHENTIK_ALLOY_APP_PASSWORD=%s\n' "${LOKI_PASSWORD}"
} > /etc/alloy/logs.env
chown root:root /etc/alloy/logs.env
chmod 0600 /etc/alloy/logs.env

cat > /etc/systemd/system/alloy-logs.service <<'SERVICE'
[Unit]
Description=Grafana Alloy logs collector
Documentation=https://grafana.com/docs/alloy
Wants=network-online.target
After=network-online.target

[Service]
Restart=always
User=alloy
Environment=HOSTNAME=%H
EnvironmentFile=/etc/alloy/logs.env
WorkingDirectory=/var/lib/alloy
ExecStart=/usr/bin/alloy run --server.http.listen-addr=127.0.0.1:12345 --storage.path=/var/lib/alloy-logs/data /etc/alloy/logs.alloy
ExecReload=/usr/bin/env kill -HUP $MAINPID
TimeoutStopSec=20s

[Install]
WantedBy=multi-user.target
SERVICE

usermod -aG adm,systemd-journal,www-data alloy
if [[ -d /var/lib/docker/containers ]]; then
  setfacl -m u:alloy:--x /var/lib/docker || true
  setfacl -m u:alloy:--x /var/lib/docker/containers || true
  setfacl -d -m u:alloy:rx /var/lib/docker/containers || true
  find /var/lib/docker/containers -type d -exec setfacl -m u:alloy:rx {} + || true
  find /var/lib/docker/containers -name '*.log' -exec setfacl -m u:alloy:r {} + || true
fi
install -d -m 0750 -o alloy -g alloy /var/lib/alloy-logs/data
alloy fmt --write /etc/alloy/logs.alloy
chown root:alloy /etc/alloy
chmod 0750 /etc/alloy
chmod 0644 /etc/alloy/logs.alloy

systemctl daemon-reload
systemctl disable --now alloy >/dev/null 2>&1 || true
rm -rf /etc/systemd/system/alloy.service.d
systemctl reset-failed alloy alloy-logs || true
systemctl enable alloy-logs >/dev/null
systemctl restart alloy-logs
sleep 5
systemctl is-active alloy-logs

rm -f /tmp/olly-logs.alloy /tmp/olly-setup.sh /tmp/olly.env
