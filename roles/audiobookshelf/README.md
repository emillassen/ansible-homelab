# audiobookshelf

Audiobookshelf in Docker Compose, image pinned in `defaults/main.yml` (Renovate updates it). The web UI is on 13378; Caddy serves it as `audiobookshelf.hjem.sh`. Logs go to Loki through the Docker driver (`docker_host`). The container runs as root, as upstream ships it.

The books and podcasts are NFS shares on Holocron (`192.168.1.30:/mnt/user/books/{Audiobooks,Podcasts}`), mounted by systemd automount from fstab (`nfs_automount`). Holocron's `books` rule matches the production address, so the mounts and Audiobookshelf only start once `net_production` is set, and apply fails if a share doesn't mount.

`config/` (absdatabase.sqlite) and `metadata/` (covers, item metadata, its own nightly backups in `metadata/backups`) are data: `run migrate` copies them with the old Audiobookshelf stopped. The pinned version can't be older than the one that last wrote the database.

## Resources

1. https://www.audiobookshelf.org/docs#docker-compose-install
1. https://www.audiobookshelf.org/guides/docker-nginxproxymanager-setup/
