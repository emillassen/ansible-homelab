# changedetection

changedetection.io and sockpuppetbrowser (headless Chrome, for watches set to the browser fetcher) in Docker Compose, images pinned in `defaults/main.yml` (Renovate updates them). The web UI is on 5000; Caddy serves it as `changedetection.hjem.sh`. Logs go to Loki through the Docker driver (`docker_host`).

The watches and their history are in the `changedetection-data` volume. A rebuild starts empty: restore the watch list from a backup in **Settings → Backup / Restore**, then set the password again under **Settings → General**.

## Resources

1. https://github.com/dgtlmoon/changedetection.io
1. https://github.com/dgtlmoon/sockpuppetbrowser
