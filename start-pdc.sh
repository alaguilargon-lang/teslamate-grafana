#!/bin/bash
set -euo pipefail

teslamate_pid=''
supervisor_pid=''

stop_children() {
  trap - EXIT
  local pid
  for pid in "$supervisor_pid" "$teslamate_pid"; do
    if [[ -n "$pid" ]]; then
      kill -TERM "$pid" 2>/dev/null || true
    fi
  done
  wait 2>/dev/null || true
}
trap 'exit 0' TERM INT
trap stop_children EXIT

start_agent() {
  trap - EXIT
  local variable
  while IFS= read -r variable; do
    case "$variable" in
      PATH|LANG|GCLOUD_PDC_SIGNING_TOKEN|GCLOUD_PDC_CLUSTER|GCLOUD_HOSTED_GRAFANA_ID) ;;
      *) export -n "$variable" ;;
    esac
  done < <(compgen -e)

  exec /usr/sbin/runuser -u pdc-agent -- /usr/local/bin/pdc \
    -ssh-key-file=/var/lib/pdc-agent/grafana_pdc \
    -metrics-addr=127.0.0.1:8090 \
    '-ssh-flag=-o PermitRemoteOpen=postgres-teslamate:5432'
}

supervise_agent() {
  trap - EXIT
  local child=''
  trap 'if [[ -n "$child" ]]; then kill -TERM "$child" 2>/dev/null || true; fi; exit 0' TERM INT
  while true; do
    start_agent &
    child=$!
    wait "$child" || true
    printf '%s\n' 'PDC se ha cerrado. Nuevo intento en 15 segundos.' >&2
    sleep 15 &
    child=$!
    wait "$child"
  done
}

env -u GCLOUD_PDC_SIGNING_TOKEN -u GCLOUD_PDC_CLUSTER -u GCLOUD_HOSTED_GRAFANA_ID \
  -u GRAFANA_READER_PASSWORD -u GRAFANA_DB_PASSWORD -u GRAFANA_ADMIN_PASSWORD -u GRAFANA_SECRET_KEY \
  /usr/bin/setpriv --reuid=nonroot --regid=nonroot --clear-groups /bin/dash /entrypoint.sh "$@" &
teslamate_pid=$!

if [[ -n "${GCLOUD_PDC_SIGNING_TOKEN:-}" && -n "${GCLOUD_PDC_CLUSTER:-}" && -n "${GCLOUD_HOSTED_GRAFANA_ID:-}" ]]; then
  supervise_agent &
  supervisor_pid=$!
else
  printf '%s\n' 'PDC pendiente de configuración. TeslaMate arranca.' >&2
fi

wait "$teslamate_pid"
