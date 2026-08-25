#!/usr/bin/env bash
set -euo pipefail

UPSTREAM_URL="https://github.com/chirpstack/chirpstack-docker"
TMP="$(mktemp -d)"
trap 'rm -rf "${TMP}"' EXIT

cd "$(dirname "$0")"

git clone --quiet "${UPSTREAM_URL}" "${TMP}/upstream"
SHA="$(git -C "${TMP}/upstream" rev-parse HEAD)"

for d in chirpstack chirpstack-gateway-bridge mosquitto postgresql; do
  rm -rf "configuration/${d}"
  cp -a "${TMP}/upstream/configuration/${d}" "configuration/${d}"
done

cat > configuration/chirpstack/chirpstack.toml <<'EOF'
[logging]
  level="info"

[postgresql]
  dsn="postgres://chirpstack:$POSTGRESQL_PASSWORD@$POSTGRESQL_HOST/chirpstack?sslmode=disable"
  max_open_connections=10
  min_idle_connections=0

[redis]
  servers=["redis://$REDIS_HOST/"]
  cluster=false

[network]
  net_id="000000"
  enabled_regions=["eu868"]

[api]
  bind="0.0.0.0:8080"
  secret="$CHIRPSTACK_SECRET"

[integration]
  enabled=["mqtt"]

  [integration.mqtt]
    server="$INTEGRATION_MQTT_SERVER"
    username="$INTEGRATION_MQTT_USERNAME"
    password="$INTEGRATION_MQTT_PASSWORD"
    json=true
EOF

echo "${SHA}" > UPSTREAM

echo "upstream sync point: ${SHA}"
echo
echo "gateway backend MQTT in region_eu868.toml:"
grep -n 'server=' configuration/chirpstack/region_eu868.toml
