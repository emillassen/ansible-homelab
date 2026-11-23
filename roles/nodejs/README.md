# nodejs

Node.js from NodeSource's `node_<major>.x` repo, for the services whose upstream builds on a newer Node than Debian ships (Homepage, Zigbee2MQTT). unattended-upgrades keeps it current within `nodejs_major`; changing the major is a manual bump in `defaults/main.yml`.

The signing key is kept in `files/nodesource-repo.gpg`. To replace it, download it, check the fingerprint against NodeSource's docs, and commit it:

```sh
curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key | gpg --dearmor > roles/nodejs/files/nodesource-repo.gpg
gpg --show-keys roles/nodejs/files/nodesource-repo.gpg
```

## Resources

1. https://github.com/nodesource/distributions
