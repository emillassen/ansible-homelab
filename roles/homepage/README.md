# homepage

Homepage built from its pinned source tag with pnpm on NodeSource Node (the `nodejs` role), and run with `next start` as the `homepage` user, which can only write to `config/` and `.next/cache` (so a `logpath` in `settings.yaml` outside `config/` won't work). A Renovate bump (or a revert) stops the service, clears everything but `config/`, unpacks the new source, runs `pnpm install` and `pnpm build`, and writes the version to `.version`. The build needs the guest's 4 GB.

`config/` is data: the YAML files are edited on the guest, and some (`proxmox.yaml`, widget keys in `services.yaml`) hold credentials, so they stay out of this repo. `run migrate` copies the directory. `HOMEPAGE_ALLOWED_HOSTS` is set in the unit from `homepage_allowed_hosts`.

## Resources

1. https://gethomepage.dev/installation/source/
1. https://github.com/gethomepage/homepage
