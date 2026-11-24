# grafana

Grafana in Docker Compose, image pinned in `defaults/main.yml` (Renovate updates it). It runs as uid 1000 (emil) on 3000, served by Caddy as `grafana.hjem.sh`; DOCKER-USER lets only Caddy reach 3000.

`data/` (grafana.db with users, dashboards and data sources; plugins) is data: `run migrate` copies it with the old Grafana stopped, and the new one stays stopped until it's there. The pinned version can't be older than the one that last wrote `grafana.db`.

## Resources

1. https://grafana.com/docs/grafana/latest/setup-grafana/installation/docker/
