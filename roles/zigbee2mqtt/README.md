# zigbee2mqtt

Zigbee2MQTT built from its pinned source tag with pnpm on NodeSource Node (the `nodejs` role), run as the `zigbee2mqtt` user, which can only write to `data/`. The unit is the one from the Zigbee2MQTT guide (`Type=notify` with a watchdog). There's no updater timer: Renovate bumps the tag, and a bump stops the service, clears everything but `data/`, unpacks, runs `pnpm install` and `pnpm run build`, and writes `.version`. pnpm is installed at the version `packageManager` in the tag's `package.json` names, so it has no pin of its own.

The coordinator (`tcp://192.168.1.21:6638`) takes one client at a time, so the service is stopped and disabled until `net_production` is true *and* `data/configuration.yaml` exists. `run migrate` stops the old service, copies the whole `data/` directory (configuration with the network key, `database.db`, `coordinator_backup.json`, `state.json`) and leaves the new service stopped; the cutover apply starts it.

Rollback before the old guest is deleted, on the Proxmox host. Disable the new service *first*: once 116 has run in production its unit is enabled, so any reboot (including the rollback's MAC swap) would reconnect it before an apply could stop it:

```sh
pct exec 116 -- systemctl disable --now zigbee2mqtt
pct exec 104 -- systemctl start zigbee2mqtt   # after the old guest is back on its MAC and address
```
 A second instance on the coordinator, or a new network key, means re-pairing every device.

The frontend (8081) is reachable only from `web_client_sources` (LAN clients use `z2m.hjem.sh`) and asks for a token: `frontend.auth_token`, given through the `ZIGBEE2MQTT_CONFIG_FRONTEND_AUTH_TOKEN` environment override from `/etc/zigbee2mqtt/frontend.env`. The token is `vault_zigbee2mqtt_frontend_token`.

## Resources

1. https://www.zigbee2mqtt.io/guide/installation/01_linux.html
1. https://github.com/Koenkk/zigbee2mqtt
