# miniflux

Miniflux and its Postgres in Docker Compose, images pinned in `defaults/main.yml` (Renovate updates them). The web UI is on 80; Caddy serves it as `miniflux.hjem.sh`, and `TRUSTED_REVERSE_PROXY_NETWORKS` trusts only Caddy. Logs go to Loki through the Docker driver (`docker_host`).

The database password is generated once on the guest into `.env` (0600); only the two containers use it.

The database is data: `run migrate` dumps it on the old VM with Miniflux stopped (`pg_dump --format=custom`) and restores it into the new Postgres, which runs empty until then. Miniflux starts once `.migrated` is written after the restore. Users, feeds, entries and settings all come with it, so there is no `CREATE_ADMIN`.

A Postgres major bump (18 to 19) needs a dump and restore; Renovate holds majors for approval on the dependency dashboard.

## Resources

1. https://miniflux.app/docs/docker.html
1. https://miniflux.app/docs/configuration.html
