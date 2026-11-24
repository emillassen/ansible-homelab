# jellyfin

Jellyfin from the repo.jellyfin.org apt repo, updated by unattended-upgrades, with the bundled `jellyfin-ffmpeg` (which ships Intel's VA-API and QSV drivers). Intel's OpenCL runtime, which QSV tone mapping needs, isn't packaged for Debian 13, so the role installs Intel's release debs, pinned with their checksums.

`/etc/jellyfin` and `/var/lib/jellyfin` are data: users, libraries, watch history, metadata and plugins. `run migrate` copies both from the old guest into emptied directories, and Jellyfin stays stopped until it has. `/var/cache/jellyfin` isn't copied.

## Proxmox host setup

The Proxmox API won't let the controller's token add bind mounts or devices, so after the first provision, as root on the Proxmox host:

```sh
pct exec 120 -- getent group render     # the GID for dev0
pct shutdown 120
pct set 120 --mp0 /mnt/movies/,mp=/movies --mp1 /mnt/series/,mp=/series \
  --dev0 /dev/dri/renderD128,gid=<render GID>,mode=0660
pct start 120
```

The media mounts keep the old guest's paths, so the libraries match without a rescan. `dev0` replaces the old guest's `lxc.cgroup2` and `lxc.mount.entry` lines and its chown hook.

## Updating the Intel runtime

The debs in `defaults/main.yml` aren't covered by Renovate. Take the IGC and gmmlib versions from the [compute-runtime release notes](https://github.com/intel/compute-runtime/releases), and the checksums from the release's `ww*.sum` and the IGC release notes. The release is built for Ubuntu; check that it still installs on Debian 13 (`apt-get -s install ./*.deb`).

## Resources

1. https://jellyfin.org/docs/general/installation/linux/
1. https://jellyfin.org/docs/general/post-install/transcoding/hardware-acceleration/intel/
1. https://pve.proxmox.com/pve-docs/pct.1.html
