# smokeping

Debian's `smokeping` with Apache, updated by unattended-upgrades. `General` and `Targets` come from this role; the RRD history in `/var/lib/smokeping` is not carried over, so graphs start empty.

The package serves at `/smokeping/smokeping.cgi`, not `/`. The Caddy route redirects `/` there.

A syntax error in `Targets` stops the daemon. The handler runs `smokeping --check` before every restart and stops the play if it fails, leaving the running daemon on the old config. To check by hand:

```sh
env -u LC_ALL smokeping --check
```

A failed run forgets the restart, so the next run, with nothing left to change, won't restart either. After fixing the config, restart by hand:

```sh
systemctl restart smokeping apache2
```

The package pulls in `exim4` through `default-mta`. It listens on `127.0.0.1` only and nothing on the guest sends mail.

## Resources

1. https://oss.oetiker.ch/smokeping/doc/smokeping_config.en.html
1. https://packages.debian.org/trixie/smokeping
