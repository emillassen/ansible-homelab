# caddy

Caddy from the Caddy apt repo for the `caddy` user, the unit and the directories. The binary that runs is `/usr/local/bin/caddy`, built with xcaddy and two plugins: `caddy-dns/cloudflare` (DNS-01 through Cloudflare, `acme_dns`) and `WeidiDeng/caddy-cloudflare-ip` (`trusted_proxies cloudflare`). Caddy, the plugins, xcaddy and Go are pinned in `defaults/main.yml`; a change to any of them rebuilds on the next apply. The Go and Debian `/usr/bin/caddy` aren't used. There's no update timer.

The Caddyfile is `templates/Caddyfile.j2`. The handler validates it before restarting, and a bad file fails the play and leaves the running Caddy alone. `admin off` means there's no `caddy reload`; every change restarts Caddy (about a second).

Every `*.hjem.sh` site imports `lan_only`, which aborts any connection whose address isn't in 192.168.1.0/24. Only `nextcloud.indud.io` is public (through Cloudflare, with origin-pull mTLS). A new internal site needs `import lan_only` too.

The Cloudflare API token is `vault_caddy_cloudflare_api_token` in `inventory/group_vars/all/vault.yml`, written to `/etc/caddy/.env`. The Cloudflare origin pull CA in `files/` is public: https://developers.cloudflare.com/ssl/origin-configuration/authenticated-origin-pull/

## Cloudflare

1. The token: https://dash.cloudflare.com/profile/api-tokens → Create Token → Custom, name `Caddy`, permissions `Zone / Zone / Read` and `Zone / DNS / Edit`, zone resources `Include / Specific zone` for `hjem.sh` and `indud.io`. Put it in the vault.
1. To roll it (after it was shown anywhere): Caddy → Roll on the same page, put the new value in the vault, then `run apply --limit caddy`. Issued certificates keep working; a wrong token shows up in `journalctl -u caddy` at the next renewal.
1. Origin pull mTLS: on each zone, SSL/TLS → Origin Server → Authenticated Origin Pulls → On (Global).

`/var/lib/caddy` (certificates, ACME accounts) is data: `run migrate` copies it while the old guest keeps serving, and Caddy stays stopped until it's there, so it doesn't order every certificate again.

## Resources

1. https://caddyserver.com/docs/install#debian-ubuntu-raspbian
1. https://github.com/caddyserver/xcaddy
1. https://caddyserver.com/docs/caddyfile/options
1. https://caddyserver.com/docs/caddyfile/matchers#remote-ip
