# mosquitto

Mosquitto from the mosquitto.org apt repo, updated by unattended-upgrades. The listener config comes from this role. The password file and `mosquitto.db` (retained messages and persistent sessions) are data: `run migrate` copies them, and the broker stays stopped until the password file exists.

The repo's signing key is kept in `files/mosquitto-repo.gpg` and expires on 2030-07-10. To replace it, download the new key, check its fingerprint against the one on mosquitto.org and commit it:

```sh
curl -fo roles/mosquitto/files/mosquitto-repo.gpg https://repo.mosquitto.org/debian/mosquitto-repo.gpg
gpg --show-keys roles/mosquitto/files/mosquitto-repo.gpg
```

To add or change a user, on the guest:

```sh
mosquitto_passwd /etc/mosquitto/passwd <user>
systemctl restart mosquitto
```

## Resources

1. https://mosquitto.org/download/
1. https://mosquitto.org/man/mosquitto-conf-5.html
1. https://mosquitto.org/man/mosquitto_passwd-1.html
