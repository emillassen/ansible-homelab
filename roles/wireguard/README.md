# wireguard

WireGuard (`wireguard-tools` from Debian) managed by WGDashboard, pinned in `defaults/main.yml` (Renovate updates it). The release has no built frontend, so the role builds it with Debian's Node and removes `node_modules` afterwards. The dashboard runs as root (it manages the interface) on 10086 and brings `wg0` up itself (`autostart = wg0` in its ini); `wg-quick@wg0` isn't enabled. There's no update timer.

Data, copied by `run migrate` from the old guest:

1. `/etc/wireguard`: `wg0.conf` with the server key, the peers and the PostUp and PostDown rules (forwarding, NAT out of eth0, and SSH through the tunnel only from 10.0.0.3 and 10.0.0.4). The dashboard rewrites it (`SaveConfig = true`), so it isn't templated.
1. `/var/lib/wgdashboard`: `wg-dashboard.ini` (account, password hash, TOTP secret, settings; the role sets the login from the vault, see below), the OIDC providers file and `db/` (SQLite). Also `plugins/` (empty so far). The app finds them through `CONFIGURATION_PATH` and, where it opens them relative to its working directory, through links in `src/`.

The dashboard login is set from the vault after the data is in place: `vault_wireguard_dashboard_password_hash` (the bcrypt hash, as in the ini) and `vault_wireguard_dashboard_totp_key`, with TOTP forced on. A password or TOTP changed in the dashboard is put back on the next apply, so change it in the vault: make the hash on the guest with `/opt/wgdashboard/src/venv/bin/python -c 'import bcrypt,getpass; print(bcrypt.hashpw(getpass.getpass().encode(), bcrypt.gensalt()).decode())'`.

The new guest holds the same server key as the old one, so the dashboard only runs once `net_production` is true and the data is in place. Until then neither it nor `wg0` is up.

The kernel module comes from the Proxmox host; an unprivileged container can't load it.

## Per-peer SSH

Every peer gets `192.168.1.0/24` and is masqueraded to `.102`, so the guests can't tell peers apart. The `FORWARD` chain can, because it runs before the NAT and WireGuard has already dropped any packet whose source isn't the peer's `AllowedIPs`. SSH through the tunnel is allowed only from `10.0.0.3` (work laptop) and `10.0.0.4` (`fw13`); `10.0.0.2` and `10.0.0.5` are phones.

The rules are the `PostUp`/`PostDown` fields of `wg0` in WGDashboard (Home → `wg0` → edit), so they live in `wg0.conf`, which is data. Paste each field whole:

```
iptables -A FORWARD -i wg0 -j ACCEPT; iptables -A FORWARD -o wg0 -j ACCEPT; iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE; sysctl -w net.ipv4.ip_forward=1; sysctl -w net.ipv6.conf.all.forwarding=1; iptables -I FORWARD -i wg0 -p tcp --dport 22 -j DROP; iptables -I FORWARD -i wg0 -s 10.0.0.3 -p tcp --dport 22 -j ACCEPT; iptables -I FORWARD -i wg0 -s 10.0.0.4 -p tcp --dport 22 -j ACCEPT;
```

```
iptables -D FORWARD -i wg0 -j ACCEPT; iptables -D FORWARD -o wg0 -j ACCEPT; iptables -t nat -D POSTROUTING -o eth0 -j MASQUERADE; iptables -D FORWARD -i wg0 -s 10.0.0.4 -p tcp --dport 22 -j ACCEPT; iptables -D FORWARD -i wg0 -s 10.0.0.3 -p tcp --dport 22 -j ACCEPT; iptables -D FORWARD -i wg0 -p tcp --dport 22 -j DROP;
```

`-I` puts the last rule first, so the order ends up `ACCEPT .4`, `ACCEPT .3`, `DROP 22`, then the blanket `ACCEPT`. `PostDown` must mirror `PostUp` exactly. Check with `pct exec 118 -- iptables -L FORWARD -n --line-numbers | head -8`, then from a denied peer: SSH times out, Immich still loads. To change the rules, run the `iptables` commands live with `pct exec 118 --` first (editing the fields restarts the tunnel), then paste the fields. A new peer can't SSH until it's added here.

## Resources

1. https://github.com/WGDashboard/WGDashboard
1. https://www.wireguard.com/quickstart/
