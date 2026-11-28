# nextcloud

Nextcloud All-in-One on the beta channel, as in the guide. Ansible writes the mastercontainer's `docker-compose.yml`; the mastercontainer creates and runs every other container (Apache, Nextcloud, Postgres, Redis, Imaginary, Talk, Euro-Office, notify-push, Fail2ban). AIO updates itself and its containers at 05:00 through `/root/automatic-updates.sh` under `flock /run/lock/nextcloud-update.lock` (the nightly deploy holds it while it works here, so AIO waits), AIO's script for updates without a backup first; it's the brief's one self-updater, so there's no Renovate pin. Apache's port 11000 is limited to Caddy (`nextcloud.indud.io`) by the DOCKER-USER filter. The AIO UI is on `https://<VM>:8080`. The containers log to json-file, not Loki.

The data directory is the `proxmox-nextcloud` NFS share on Holocron, mounted by `nfs_automount` at `/mnt/proxmox-nextcloud` (a hard mount). Holocron's rule matches the production address, so the mastercontainer only starts once `net_production` is set. On its first start Ansible tells it to start the other containers once (`START_CONTAINERS=1`); after that their restart policy and the AIO UI run them.

`run migrate` stops AIO on the old VM (`STOP_CONTAINERS=1`, then the mastercontainer), which makes the database container dump the database. It copies the Docker volumes listed in `nextcloud_volumes` with their owners: AIO's configuration and secrets, the Nextcloud install with `config.php`, the dump, Apache and Euro-Office. The database volume isn't copied: on its first start the new database container finds the dump and an empty volume and restores it, which is AIO's own path for a Postgres upgrade. Settings made in the UI (2FA, apps, email, trusted proxies) travel with the volumes.

The VM disk is 64 GB, as the setup guide says. A clone has the template's 32 GB, so after a rebuild grow the disk to 64 GB in Proxmox (`provision` prints a reminder), then grow the partition and filesystem online in the VM (`base` turns cloud-init off, so nothing does it at boot):

```sh
sudo growpart /dev/sda 1 && sudo resize2fs /dev/sda1
```

## Resources

1. https://github.com/nextcloud/all-in-one#how-to-use-this
1. https://github.com/nextcloud/all-in-one#how-to-change-the-default-location-of-nextclouds-datadir
1. https://github.com/nextcloud/all-in-one#how-to-enable-automatic-updates-without-creating-a-backup-beforehand
1. https://github.com/nextcloud/all-in-one/blob/main/Containers/postgresql/start.sh
1. https://github.com/nextcloud/all-in-one/blob/main/Containers/mastercontainer/daily-backup.sh
