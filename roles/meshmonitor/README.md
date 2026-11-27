# meshmonitor

MeshMonitor in Docker Compose, image pinned in `defaults/main.yml` (Renovate updates it). The web UI is on 8080; Caddy serves it as `meshmonitor.hjem.sh`. Logs go to Loki through the Docker driver (`docker_host`).

The source is the Seeed XIAO nRF52840 (MeshCore USB companion) on the Proxmox host, passed through to the VM. MeshMonitor runs only once `run migrate` has copied its data and the VM has the device.

`data/` (meshmonitor.db, backups, Apprise config) is data: `run migrate` copies it with the old MeshMonitor stopped. `SESSION_SECRET` seals the stored device keys and saved passwords in the database, so it must never change: it is `vault_meshmonitor_session_secret`, written to `.env` (0600), and migrate refuses to start if the old VM's differs. The pinned version can't be older than the one that last wrote `meshmonitor.db`.

## Root paste (Proxmox host)

The USB device can only be attached to one running VM. Pass it through at cutover, with the old VM stopped:

```sh
qm set <vmid> -usb0 host=2886:8044
```

## Resources

1. https://github.com/yeraze/meshmonitor
1. https://github.com/yeraze/meshmonitor/blob/main/docs/features/meshcore.md
1. https://github.com/yeraze/meshmonitor/blob/main/docs/configuration/reverse-proxy.md
1. https://pve.proxmox.com/wiki/USB_Devices_in_Virtual_Machines
