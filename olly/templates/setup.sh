#!/usr/bin/env bash
set -euo pipefail

set -a
. /tmp/olly.env
set +a

install -d -m 0750 -o root -g alloy /etc/alloy
install -d -m 0755 /etc/systemd/system/alloy.service.d
install -d -m 0755 /etc/apt/keyrings

export DEBIAN_FRONTEND=noninteractive
apt-get update >/dev/null
apt-get install -y gpg wget ca-certificates >/dev/null

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

install -m 0644 -o root -g root /tmp/olly-config.alloy /etc/alloy/config.alloy

umask 077
{
  printf 'LOKI_USERNAME=%s\n' "${LOKI_USERNAME}"
  printf 'AUTHENTIK_ALLOY_APP_PASSWORD=%s\n' "${LOKI_PASSWORD}"
} > /etc/alloy/env
chown root:root /etc/alloy/env
chmod 0600 /etc/alloy/env

printf '%s\n' '[Service]' 'EnvironmentFile=/etc/alloy/env' > /etc/systemd/system/alloy.service.d/env.conf
chown root:root /etc/systemd/system/alloy.service.d/env.conf
chmod 0600 /etc/systemd/system/alloy.service.d/env.conf

usermod -aG adm,systemd-journal,www-data alloy
alloy fmt --write /etc/alloy/config.alloy
chown root:alloy /etc/alloy
chmod 0750 /etc/alloy
chmod 0644 /etc/alloy/config.alloy

systemctl daemon-reload
systemctl reset-failed alloy || true
systemctl enable alloy >/dev/null
systemctl restart alloy
sleep 5
systemctl is-active alloy

rm -f /tmp/olly-config.alloy /tmp/olly-setup.sh /tmp/olly.env
