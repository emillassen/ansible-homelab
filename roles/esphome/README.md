# esphome

ESPHome and the Device Builder dashboard in a venv at `/opt/esphome/venv`, from the pins in `files/requirements.txt` (Renovate updates them). It runs as the `esphome` user, which can only write to `/var/lib/esphome`: the YAML in `config/`, PlatformIO's toolchains in `.platformio/` and ESPHome's cache in `.cache/`. The dashboard is on 6052, reachable only from `web_client_sources` (LAN clients use `esphome.hjem.sh`), behind a login: it can read `secrets.yaml` and flash every device. The username is `esphome_dashboard_username`; the password is `vault_esphome_dashboard_password`. Remote build (6055) is open only to `admin_sources`. mDNS on 5353/udp finds the devices.

`config/` is data: the device YAML and `secrets.yaml` (Wi-Fi credentials) stay out of this repo. `run migrate` copies it from the old guest's `/root/config`, without `.esphome/build` (build output, recreated on the next compile); the rest of `.esphome/` is the dashboard's own state and is copied. The first compile after a rebuild downloads the toolchains again and is slow.

After an upgrade of the `esphome` pin, the role starts `esphome-update-devices.service` in the background. It flashes every device in `config/` over the air with the new version, one at a time, and skips devices already on it. Before flashing it reads the device's running version from its log banner; after flashing it waits up to 3 minutes for the device to report the new version. The files in `esphome_update_last` (the TubesZB Zigbee coordinator) go last, and only if every other device succeeded. A failed compile or upload leaves that device on its old firmware. The unit then ends `failed`, which `run verify` reports; fix the YAML, then retry with `systemctl start esphome-update-devices` (`journalctl -u esphome-update-devices` has the log). A first install flashes nothing. Set `esphome_update_devices: false` to turn it off.

There's no USB in the container: flash over the air, or from a browser with ESPHome Web.

## Resources

1. https://esphome.io/guides/installing_esphome/
1. https://github.com/esphome/device-builder
