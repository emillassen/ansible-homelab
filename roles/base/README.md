# base

Every guest: timezone, locale, key-only SSH with exactly two keys (yours and the controller's), and unattended-upgrades as `services/snippets/unattended-upgrades.md` configures it, with apt's timers at 00:30 (lists) and 01:00 (installs).

It purges packages the images ship that nothing uses (`base_purge_packages_lxc`/`_vm`, with their unused dependencies; a host can override the list, as Smokeping does to keep postfix). LXCs also get needrestart, set to restart services still using replaced libraries after each apt run: an LXC never gets a reboot-required flag, so without it a library update only takes effect when the service happens to restart. `run verify` lists any service left on old libraries.

Nothing here needs a hand step.

## Resources

1. https://github.com/mvo5/unattended-upgrades/blob/master/README.md
1. https://manpages.debian.org/trixie/openssh-server/sshd_config.5.en.html
1. https://manpages.debian.org/trixie/needrestart/needrestart.1.en.html
