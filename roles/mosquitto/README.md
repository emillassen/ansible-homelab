# mosquitto

Mosquitto from the mosquitto.org apt repo, updated by unattended-upgrades. The listener config comes from this role. The password file comes from `vault_mosquitto_passwd`. `mosquitto.db` (retained messages and persistent sessions) is data: `run migrate` copies it.

The repo's signing key is kept in `files/mosquitto-repo.gpg` and expires on 2030-07-10. To replace it, download the new key, check its fingerprint against the one on mosquitto.org and commit it:

```sh
curl -fo roles/mosquitto/files/mosquitto-repo.gpg https://repo.mosquitto.org/debian/mosquitto-repo.gpg
gpg --show-keys roles/mosquitto/files/mosquitto-repo.gpg
```

To add or change a user, make the line on the guest without touching the live file, then put it in `vault_mosquitto_passwd` and apply:

```sh
mosquitto_passwd -c /tmp/p <user> && cat /tmp/p && rm /tmp/p
```

## Resources

1. https://mosquitto.org/download/
1. https://mosquitto.org/man/mosquitto-conf-5.html
1. https://mosquitto.org/man/mosquitto_passwd-1.html
