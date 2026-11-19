ARG TESLAMATE_VERSION=4.4.0
ARG GRAFANA_VERSION=13.3.1

FROM grafana/grafana:${GRAFANA_VERSION}-ubuntu AS grafana
FROM teslamate/grafana:${TESLAMATE_VERSION} AS dashboards
FROM teslamate/teslamate:${TESLAMATE_VERSION}

USER root
RUN apt-get update \
    && apt-get install -y --no-install-recommends libfontconfig1 \
    && rm -rf /var/lib/apt/lists/* \
    && groupadd --system --gid 10002 grafana \
    && useradd --system --uid 10002 --gid grafana --home-dir /var/lib/grafana --shell /usr/sbin/nologin grafana \
    && install -d -o grafana -g grafana /var/lib/grafana /var/lib/grafana/plugins /var/lib/grafana/logs

COPY --from=grafana /usr/share/grafana /usr/share/grafana
COPY --from=dashboards /dashboards /dashboards
COPY --from=dashboards /dashboards_internal /dashboards_internal
COPY --from=dashboards /dashboards_reports /dashboards_reports
COPY --from=dashboards /etc/grafana/provisioning/dashboards/dashboards.yml /etc/grafana/provisioning/dashboards/dashboards.yml
COPY datasource.yml /etc/grafana/provisioning/datasources/teslamate.yml
COPY --chmod=0555 start.sh /usr/local/bin/start-teslamate-and-grafana

RUN command -v setpriv \
    && test -x /entrypoint.sh \
    && test -f /dashboards/drives.json \
    && setpriv --reuid=grafana --regid=grafana --clear-groups /usr/share/grafana/bin/grafana --version

EXPOSE 3000 4000
ENTRYPOINT ["tini", "-g", "--", "/usr/local/bin/start-teslamate-and-grafana"]
CMD ["bin/teslamate", "start"]
