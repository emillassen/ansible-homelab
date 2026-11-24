# wireguard

WireGuard (`wireguard-tools` from Debian) managed by WGDashboard, pinned in `defaults/main.yml` (Renovate updates it). The release has no built frontend, so the role builds it with Debian's Node and removes `node_modules` afterwards. The dashboard runs as root (it manages the interface) on 10086 and brings `wg0` up itself (`autostart = wg0` in its ini); `wg-quick@wg0` isn't enabled. There's no update timer.

Data, copied by `run migrate` from the old guest:

1. `/etc/wireguard`: `wg0.conf` with the server key, the peers and the PostUp and PostDown rules (forwarding, NAT out of eth0, and SSH through the tunnel only from 10.0.0.3 and 10.0.0.4). The dashboard rewrites it (`SaveConfig = true`), so it isn't templated.
1. `/var/lib/wgdashboard`: `wg-dashboard.ini` (account, password hash, TOTP secret, settings), the OIDC providers file and `db/` (SQLite). Also `plugins/` (empty so far). The app finds them through `CONFIGURATION_PATH` and, where it opens them relative to its working directory, through links in `src/`.

The new guest holds the same server key as the old one, so the dashboard only runs once `net_production` is true and the data is in place. Until then neither it nor `wg0` is up.

The kernel module comes from the Proxmox host; an unprivileged container can't load it.

## Rollback

On the Proxmox host: `pct shutdown 118`, then `pct set 101 --onboot 1 && pct start 101`. Its dashboard brings `wg0` up again.

## Resources

1. https://github.com/WGDashboard/WGDashboard
1. https://www.wireguard.com/quickstart/
