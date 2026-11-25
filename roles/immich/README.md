# immich

Immich (server, machine learning, Valkey, and Immich's Postgres with VectorChord) in Docker Compose, following upstream's `docker-compose.yml` for the pinned release. The server and machine learning share `immich_version` (Renovate updates it; read the release notes first). The database image is the one upstream's compose pins for that release, so take it from there on a bump. The web UI is on 2283; Caddy serves it as `immich.hjem.sh`. Logs go to Loki through the Docker driver (`docker_host`). Hardware transcoding is off, as before.

The library (originals, thumbnails, encoded video, profile pictures and Immich's own nightly database backups in `backups/`) is the `proxmox-immich` NFS share on Holocron, mounted by `nfs_automount` at `/mnt/proxmox-immich`. Holocron's rule matches the production address, so the server only starts once `net_production` is set. The database is in `./postgres` on the VM's disk. Its password is generated once into `db.env` (0600).

The database is data: `run migrate` stops the old server and machine learning, dumps the database (`pg_dump --clean --if-exists`) and restores it into the new, empty database as Immich's backup-and-restore guide does, then checks the asset count against the old one. The library doesn't move.

## Resources

1. https://docs.immich.app/install/docker-compose
1. https://docs.immich.app/administration/backup-and-restore
1. https://github.com/immich-app/immich/releases
