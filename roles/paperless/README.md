# paperless

Paperless-ngx with Postgres, Valkey, Gotenberg and Tika in Docker Compose, images pinned in `defaults/main.yml` (Renovate updates them; Postgres majors wait for approval, as they need a dump and restore). The web UI is on 8000; Caddy serves it as `paperless.hjem.sh`, and `PAPERLESS_TRUSTED_PROXIES` trusts its `X-Forwarded-For`, so DOCKER-USER lets only Caddy reach 8000. Logs go to Loki through the Docker driver (`docker_host`).

The database password and `PAPERLESS_SECRET_KEY` are `vault_paperless_db_password` and `vault_paperless_secret_key`, written to `.env` (0600). Postgres only reads the password when it creates the database, so changing it in the vault later locks Paperless out until the database's password is changed too.

The 2026 rebuild started empty (the old VM had no documents), so there is no `run migrate`. Documents, the database and the search index live in the `media`, `pgdata` and `data` volumes; `consume/` and `export/` are bind mounts in the project directory.

## By hand, once

Register at `paperless.hjem.sh`: on an install with no users, the first sign-up becomes the superuser, and sign-up closes after it (`PAPERLESS_ACCOUNT_ALLOW_SIGNUPS` stays at its default, off).

## Resources

1. https://docs.paperless-ngx.com/setup/#docker
1. https://github.com/paperless-ngx/paperless-ngx/blob/main/docker/compose/docker-compose.postgres-tika.yml
1. https://docs.paperless-ngx.com/configuration/
