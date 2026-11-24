# adguard

AdGuard Home from the pinned release tarball (checksum in `defaults/main.yml`; a Renovate bump has to update it from the release's `checksums.txt`). It runs as the `adguardhome` user with only `CAP_NET_BIND_SERVICE`, and with `--no-check-update`: the old guest's `--update` cron is gone. DNS on 53 (tcp and udp), the web UI on 80.

The binary is in `/opt/AdGuardHome`; config and data are in `/var/lib/adguardhome`. `AdGuardHome.yaml` (settings, the web UI user, upstreams, filter lists) is written by the web UI, so it's data, not a template. `run migrate` copies it with `data/stats.db` and `data/sessions.db`. It leaves out `querylog.json` (90 days, about 3 GB) and the filter lists, which are downloaded again on the first start. AdGuard Home stays stopped until the copy is there; without a config it would open the setup wizard on port 3000.

Changes made in the web UI between `run migrate` and the cutover stay on the old guest.

## Resources

1. https://github.com/AdguardTeam/AdGuardHome/wiki/Getting-Started
1. https://github.com/AdguardTeam/AdGuardHome/wiki/Configuration#command-line-arguments
