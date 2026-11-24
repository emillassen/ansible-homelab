# loki

Loki in Docker Compose, image pinned in `defaults/main.yml` (Renovate updates it), config from `templates/config.yml.j2`. It listens on 3100 and is pushed to through Caddy (`loki.hjem.sh`): every Docker VM's Loki driver sends there. DOCKER-USER lets only Caddy reach 3100 (`docker_user_filter` in the host's vars).

`data/` (owned by 10001, the image's user) isn't copied on a rebuild: Loki starts with no history. There's no retention set, so it keeps everything; the disk is 32 GB.

The VM itself logs to json-file (`docker_loki_default: false`), so Loki never logs to itself through Caddy.

## Resources

1. https://grafana.com/docs/loki/latest/setup/install/docker/
1. https://grafana.com/docs/loki/latest/configure/
