# uptime_kuma

Uptime Kuma from its pinned source tag plus the release's built frontend (`dist.tar.gz`), with Debian's Node.js. It runs as the `uptime-kuma` user and can only write to `data/`. A Renovate bump (or a revert) stops the service, clears everything but `data/`, unpacks the new source and frontend, runs `npm ci` again and writes the version to `.version`.

`data/` holds `kuma.db` (SQLite: monitors, history, settings), uploads and screenshots. `run migrate` stops the old service first, so the WAL is flushed into `kuma.db`, and copies the directory.

Its DNS is AdGuard plus `uptime_kuma_fallback_dns` (9.9.9.9), which a gateway rule lets only this host reach on port 53, so alerts still go out when AdGuard is down.

Chromium isn't installed, so "real browser" monitors won't work. Add it here if one is ever needed.

## Resources

1. https://github.com/louislam/uptime-kuma
1. https://github.com/louislam/uptime-kuma/wiki/%F0%9F%94%A7-How-to-Install
