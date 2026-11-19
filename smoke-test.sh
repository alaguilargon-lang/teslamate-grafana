#!/bin/bash
set -euo pipefail

test_network=teslamate-grafana-ci
test_postgres=teslamate-grafana-ci-postgres
test_app=teslamate-grafana-ci-app
test_password=solo-para-la-prueba-ci
grafana_url=http://127.0.0.1:43000

cleanup() {
  local status=$?
  if (( status != 0 )); then
    docker logs --tail 100 "$test_app" 2>&1 || true
    docker stats --no-stream "$test_app" 2>&1 || true
  fi
  docker rm -f "$test_app" "$test_postgres" >/dev/null 2>&1 || true
  docker network rm "$test_network" >/dev/null 2>&1 || true
}
trap cleanup EXIT

docker network create "$test_network" >/dev/null
docker run -d --name "$test_postgres" --network "$test_network" \
  -e POSTGRES_DB=teslamate -e "POSTGRES_PASSWORD=$test_password" postgres:18-trixie >/dev/null
for attempt in {1..60}; do
  if docker exec "$test_postgres" pg_isready -h 127.0.0.1 -U postgres -d teslamate >/dev/null; then break; fi
  sleep 1
done

docker exec -i "$test_postgres" psql -U postgres -d teslamate -v ON_ERROR_STOP=1 <<'SQL'
CREATE USER grafana_server PASSWORD 'solo-para-la-prueba-ci';
CREATE DATABASE grafana OWNER grafana_server;
CREATE USER grafana_reader PASSWORD 'solo-para-la-prueba-ci';
GRANT USAGE ON SCHEMA public TO grafana_reader;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT SELECT ON TABLES TO grafana_reader;
SQL

docker run -d --name "$test_app" --network "$test_network" \
  --cpus 0.2 --memory 512m --memory-swap 512m \
  -p 127.0.0.1:43000:3000 -p 127.0.0.1:44000:4000 \
  -e "DATABASE_HOST=$test_postgres" -e DATABASE_NAME=teslamate \
  -e DATABASE_USER=postgres -e "DATABASE_PASS=$test_password" -e DISABLE_MQTT=true \
  -e ENCRYPTION_KEY=clave-larga-de-prueba-no-real-1234567890 \
  -e "GRAFANA_DB_PASSWORD=$test_password" -e "GRAFANA_READER_PASSWORD=$test_password" \
  -e "GRAFANA_ADMIN_PASSWORD=$test_password" -e GRAFANA_SECRET_KEY=solo-para-la-prueba-ci-12345678901234567890 \
  teslamate-grafana:prueba >/dev/null

echo 'Esperando a que TeslaMate complete las migraciones y Grafana sirva HTTP.'
for attempt in {1..120}; do
  if curl -fsS --max-time 2 http://127.0.0.1:44000/ >/dev/null 2>&1 &&
    curl -fsS --max-time 2 "$grafana_url/api/health" 2>/dev/null | jq -e '.database == "ok"' >/dev/null; then
    break
  fi
  [[ $(docker inspect --format '{{.State.Running}}' "$test_app") == true ]]
  sleep 2
done

curl -fsS --max-time 10 http://127.0.0.1:44000/ >/dev/null
curl -fsS --max-time 10 --user "admin:$test_password" "$grafana_url/api/search?query=Drives" |
  jq -e 'any(.[]; .title == "Drives")' >/dev/null
anonymous_status=$(curl -sS --max-time 10 -o /dev/null -w '%{http_code}' "$grafana_url/api/search")
[[ "$anonymous_status" == 401 || "$anonymous_status" == 403 ]]
curl -fsS --max-time 30 --user "admin:$test_password" -H 'Content-Type: application/json' \
  --data '{"from":"now-1h","to":"now","queries":[{"refId":"A","datasource":{"type":"grafana-postgresql-datasource","uid":"TeslaMate"},"format":"table","rawSql":"SELECT count(*) AS cars FROM public.cars"}]}' \
  "$grafana_url/api/ds/query" | jq -e '.results.A.frames[0].data.values[0][0] == 0' >/dev/null
docker stats --no-stream "$test_app"
