#!/bin/bash
set -euo pipefail
GRAFANA_ADMIN_PASSWORD=${GRAFANA_ADMIN_PASSWORD:-}
GRAFANA_SECRET_KEY=${GRAFANA_SECRET_KEY:-}

grafana_pid=''
teslamate_pid=''
stop_children() {
  trap - EXIT
  for pid in "$grafana_pid" "$teslamate_pid"; do
    if [[ -n "$pid" ]]; then
      kill -TERM "$pid" 2>/dev/null || true
    fi
  done
  wait 2>/dev/null || true
}
trap 'exit 0' TERM INT
trap stop_children EXIT

start_grafana() {
  local connection="${DATABASE_HOST:-postgres-teslamate}:${DATABASE_PORT:-5432}"
  local history_database="${DATABASE_NAME:-teslamate}"
  local reader_password="$GRAFANA_READER_PASSWORD"
  local database_password="$GRAFANA_DB_PASSWORD"
  local admin_password="$GRAFANA_ADMIN_PASSWORD"
  local secret_key="$GRAFANA_SECRET_KEY"
  local root_url="${GRAFANA_ROOT_URL:-}"
  local variable

  # Keep TeslaMate credentials and platform variables out of Grafana's environment.
  while IFS= read -r variable; do
    export -n "$variable"
  done < <(compgen -e)
  export PATH=/usr/local/bin:/usr/bin:/bin HOME=/var/lib/grafana LANG=C.UTF-8
  export GRAFANA_TESLAMATE_DATABASE_ADDRESS="$connection"
  export GRAFANA_TESLAMATE_DATABASE_NAME="$history_database"
  export GRAFANA_TESLAMATE_READER_PASSWORD="$reader_password"
  export GF_PATHS_DATA=/var/lib/grafana GF_PATHS_LOGS=/var/lib/grafana/logs
  export GF_PATHS_PLUGINS=/var/lib/grafana/plugins GF_PATHS_PROVISIONING=/etc/grafana/provisioning
  export GF_SERVER_HTTP_ADDR=0.0.0.0 GF_SERVER_HTTP_PORT=3000
  if [[ -n "$root_url" ]]; then
    export GF_SERVER_ROOT_URL="$root_url"
    export GF_SECURITY_COOKIE_SECURE=true
  fi
  export GF_DATABASE_TYPE=postgres GF_DATABASE_HOST="$connection" GF_DATABASE_NAME=grafana
  export GF_DATABASE_USER=grafana_server GF_DATABASE_PASSWORD="$database_password" GF_DATABASE_SSL_MODE=disable
  export GF_DATABASE_MAX_OPEN_CONN=5 GF_DATABASE_MAX_IDLE_CONN=2
  export GF_SECURITY_ADMIN_USER=admin GF_SECURITY_ADMIN_PASSWORD="$admin_password" GF_SECURITY_SECRET_KEY="$secret_key"
  export GF_AUTH_ANONYMOUS_ENABLED=false GF_USERS_ALLOW_SIGN_UP=false
  export GF_ANALYTICS_REPORTING_ENABLED=false GF_ANALYTICS_CHECK_FOR_UPDATES=false
  export GF_UNIFIED_ALERTING_ENABLED=false GF_PLUGINS_PREINSTALL_DISABLED=true
  export GF_ALERTING_ENABLED=false GF_METRICS_ENABLED=false GF_LOG_LEVEL=warn
  export GF_DASHBOARDS_DEFAULT_HOME_DASHBOARD_PATH=/dashboards_internal/home.json
  export GOGC=75 GOMEMLIMIT=180MiB

  exec /usr/bin/setpriv --reuid=grafana --regid=grafana --clear-groups \
    /usr/share/grafana/bin/grafana server --homepath /usr/share/grafana
}

env -u GRAFANA_READER_PASSWORD -u GRAFANA_DB_PASSWORD -u GRAFANA_ADMIN_PASSWORD -u GRAFANA_SECRET_KEY \
  /usr/bin/setpriv --reuid=nonroot --regid=nonroot --clear-groups /bin/dash /entrypoint.sh "$@" &
teslamate_pid=$!

if [[ -n "${GRAFANA_READER_PASSWORD:-}" && -n "${GRAFANA_DB_PASSWORD:-}" &&
      ${#GRAFANA_ADMIN_PASSWORD} -ge 16 && ${#GRAFANA_SECRET_KEY} -ge 32 ]]; then
  start_grafana &
  grafana_pid=$!
  printf '%s\n' 'Grafana: iniciando en el puerto 3000.'
else
  printf '%s\n' 'Grafana: faltan credenciales o las claves nuevas son demasiado cortas. TeslaMate sigue arrancando.' >&2
fi

wait "$teslamate_pid"
