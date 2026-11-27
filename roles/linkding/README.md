# linkding

Linkding in Docker Compose, image pinned in `defaults/main.yml` (Renovate updates it). It runs on 9090; Caddy serves it as `linkding.hjem.sh`. Logs go to Loki through the Docker driver (`docker_host`). The settings the old `.env` held were all upstream defaults, so there is no `.env`.

`data/` (db.sqlite3 with users and bookmarks, tasks.sqlite3, secretkey.txt, favicons and previews) is data: `run migrate` copies it with the old Linkding stopped, and the new one stays stopped until it's there.

## Resources

1. https://linkding.link/installation/
1. https://linkding.link/options/
