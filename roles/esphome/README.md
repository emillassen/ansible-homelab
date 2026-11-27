# esphome

ESPHome and the Device Builder dashboard in a venv at `/opt/esphome/venv`, from the pins in `files/requirements.txt` (Renovate updates them). It runs as the `esphome` user, which can only write to `/var/lib/esphome`: the YAML in `config/`, PlatformIO's toolchains in `.platformio/` and ESPHome's cache in `.cache/`. The dashboard is on 6052, reachable only from `web_client_sources` (LAN clients use `esphome.hjem.sh`), behind a login: it can read `secrets.yaml` and flash every device. The username is `esphome_dashboard_username`; the password is picked on the first apply, kept on the guest and read with `cat /etc/esphome/dashboard.env` (a rebuilt guest gets a new one). Remote build (6055) is open only to `admin_sources`. mDNS on 5353/udp finds the devices.

`config/` is data: the device YAML and `secrets.yaml` (Wi-Fi credentials) stay out of this repo. `run migrate` copies it from the old guest's `/root/config`, without `.esphome/build` (build output, recreated on the next compile); the rest of `.esphome/` is the dashboard's own state and is copied. The first compile after a rebuild downloads the toolchains again and is slow.

There's no USB in the container: flash over the air, or from a browser with ESPHome Web.

## Resources

1. https://esphome.io/guides/installing_esphome/
1. https://github.com/esphome/device-builder
