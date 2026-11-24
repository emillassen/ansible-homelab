# docker_host

Docker from Docker's apt repo (key in `files/`), updated by unattended-upgrades, with the Compose plugin and `nfs-common`. Containers log to Loki through the Loki Docker driver (a plugin, pinned in `defaults/main.yml`):

- `mode: non-blocking`: a slow or unreachable Loki drops log lines instead of stalling the containers.
- `keep-file: true` with `max-size: 10m` and `max-file: 3`: `docker logs` still works and the local copy stays small.
- Two retries with a one-second timeout.

Hosts with `docker_loki_default: false` use `json-file` instead (the Loki VM itself). A change to `daemon.json` restarts Docker; running containers keep their old log settings until they're recreated (`docker compose up -d --force-recreate`).

## Resources

1. https://docs.docker.com/engine/install/ubuntu/
1. https://grafana.com/docs/loki/latest/send-data/docker-driver/configuration/
