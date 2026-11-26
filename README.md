# Homelab Ansible

Builds every LXC and Linux VM on the Proxmox host from scratch and moves each service's data across, like a restore from backup. Runs from the controller LXC `113` (`192.168.1.103`).

Layout:

1. `inventory/hosts.yml`: every guest. `site.yml` only touches hosts in `managed`; `legacy` is the old guests, used only to copy data.
1. `inventory/host_vars/<host>/main.yml`: IDs, sizes, MACs, IPs, ports.
1. `roles/base`, `roles/ufw`: every guest. `roles/controller`: `113`. One role per service from Phase 3 on.
1. `scripts/`: `sync`, `run` and `agent-shell` for the controller, and `new-controller-keys.sh` for the laptop.

On the controller the commands are `ansible-sync` and `ansible-run`. Over SSH as `ansible` they are `sync` and `run`:

```sh
ssh ansible-controller sync
ssh ansible-controller run check --limit caddy
ssh ansible-controller run apply --limit caddy
ssh ansible-controller run provision --check --limit caddy
ssh ansible-controller run migrate --check --limit mosquitto,mosquitto-old
```

`provision` and `migrate` are yours only; the `207` key can't run them.

## Bootstrap

Run these in order the first time. To rebuild `113` later, start at "Create `113`".

Run the Proxmox host blocks over `ssh root@192.168.1.100`, not in the web UI's shell: restarting `pveproxy` cuts that shell off. The host and fresh LXCs don't know Ghostty's terminal type; run `export TERM=xterm-256color` first, or once from the laptop:

```sh
infocmp -x xterm-ghostty | ssh root@192.168.1.100 -- tic -x -
```

### Laptop: tools and controller keys

```sh
cd ~/Documents/ansible-homelab
uv venv --python "$(command -v python3)" .venv
uv pip install --python .venv/bin/python -r requirements.txt
.venv/bin/ansible-galaxy collection install -r requirements.yml
PATH="$PWD/.venv/bin:$PATH" scripts/new-controller-keys.sh
```

The script asks for the vault password. Choose a long random one and keep it in your password manager. Put the printed `controller_ssh_key` in `inventory/group_vars/all/main.yml` and the printed line in `known_hosts`.

### Proxmox host: remove the community-scripts updater

```sh
crontab -l
crontab -l | grep -v 'update-lxcs-cron.sh' | crontab -
crontab -l
```

### Proxmox host: user, token and pool for Ansible

```sh
pveum pool add ansible --comment "Guests created by Ansible"
pveum role add AnsibleGuest --privs "VM.Allocate,VM.Audit,VM.Config.CPU,VM.Config.Cloudinit,VM.Config.Disk,VM.Config.Memory,VM.Config.Network,VM.Config.Options,VM.PowerMgmt,VM.GuestAgent.Audit"
pveum role add AnsibleClone --privs "VM.Audit,VM.Clone"
pveum role add AnsibleDisk --privs "Datastore.Audit,Datastore.AllocateSpace"
pveum role add AnsibleCTTemplate --privs "Datastore.Audit,Datastore.AllocateTemplate"
pveum role add AnsibleBridge --privs "SDN.Use"
pveum user add ansible@pve --comment "Ansible provisioning, API token only"
pveum acl modify /pool/ansible --users ansible@pve --roles AnsibleGuest
pveum acl modify /vms/903 --users ansible@pve --roles AnsibleClone
pveum acl modify /storage/local-zfs --users ansible@pve --roles AnsibleDisk
pveum acl modify /storage/local --users ansible@pve --roles AnsibleCTTemplate
pveum acl modify /sdn/zones/localnetwork --users ansible@pve --roles AnsibleBridge
pveum user token add ansible@pve provision --privsep 0 --comment "controller 113"
pveum acl list | grep ansible
```

The token secret is printed once. Destroying and recreating `903` deletes its ACL; re-run the `/vms/903` line afterwards. With `--privsep 0` the token has exactly the user's rights. The user has no password, so it can't log in. `113` is not in the pool, so the token can't touch its own controller.

Then check that the API certificate covers the host's IP. The SAN must list `IP Address:192.168.1.100`:

```sh
openssl x509 -in /etc/pve/local/pve-ssl.pem -noout -ext subjectAltName
```

If it lists an old address instead, and `hostname -I` and `grep pve /etc/hosts` both show `.100`, reissue the node certificate. The root CA stays the same:

```sh
pvecm updatecerts --force
systemctl restart pveproxy
openssl x509 -in /etc/pve/local/pve-ssl.pem -noout -ext subjectAltName
```

### Laptop: CA and vault

Copy the CA into the repo. It's public, so it isn't vaulted. Then create the vault with only the token secret in it:

```sh
scp root@192.168.1.100:/etc/pve/pve-root-ca.pem files/pve-root-ca.pem
.venv/bin/ansible-vault create inventory/group_vars/all/vault.yml
```

```yaml
vault_proxmox_token_secret: "<secret>"
```

### Laptop: SSH to the controller

The host key is the controller's, from `roles/controller/files/ssh_host_ed25519_key.pub`; it survives a rebuild, so this is done once. Your key is on the YubiKey, so `IdentityFile` names its public half and gpg-agent signs.

```sh
cat >> ~/.ssh/config <<'EOF'

Host ansible-controller
  HostName 192.168.1.103
  User ansible
  IdentityFile ~/.ssh/emillassen.pub
  IdentitiesOnly yes
  StrictHostKeyChecking yes
EOF
echo '192.168.1.103 ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIN7/JqYY7GI01EM9kvQxQYfSD4TaQSfjeMlM2uRvVqoe' >> ~/.ssh/known_hosts
```

Commit and push. The controller only gets code from GitHub.

### Hermes `207`: the agents' key (optional)

Skip this until you want Hermes to run `sync`, `check` and `apply`. As `emil` on `207`:

```sh
ssh-keygen -t ed25519 -N '' -C hermes-207-ansible -f ~/.ssh/ansible-controller
cat ~/.ssh/ansible-controller.pub
cat >> ~/.ssh/config <<'EOF'
Host ansible-controller
  HostName 192.168.1.103
  User ansible
  IdentityFile ~/.ssh/ansible-controller
  IdentitiesOnly yes
  StrictHostKeyChecking yes
EOF
echo '192.168.1.103 ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIN7/JqYY7GI01EM9kvQxQYfSD4TaQSfjeMlM2uRvVqoe' >> ~/.ssh/known_hosts
```

Put the printed key in `hermes_ssh_key` in `inventory/group_vars/all/main.yml`, commit, push, then:

```sh
ssh ansible-controller sync
ssh ansible-controller run apply --limit ansible-controller
```

To take the access away again, set `hermes_ssh_key` back to `""` and do the same.

### Proxmox host: create `113`

The MAC is fixed in `inventory/host_vars/ansible-controller/main.yml`, so the UniFi reservation survives a rebuild.

```sh
pveam list local | grep -q debian-13-standard_13.6-1_amd64.tar.zst || { pveam update && pveam download local debian-13-standard_13.6-1_amd64.tar.zst; }
test -s /root/.ssh/emil.pub || echo 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEXHWIy7fzt9lviN1c9Yd7fuA7hCOYE7qc6RmmtojcBB emil@emillassen.com' > /root/.ssh/emil.pub
pct create 113 local:vztmpl/debian-13-standard_13.6-1_amd64.tar.zst \
  --hostname ansible-controller --cores 1 --memory 1024 --swap 512 \
  --rootfs local-zfs:32 --unprivileged 1 --features nesting=1 --ostype debian \
  --net0 name=eth0,bridge=vmbr0,firewall=1,hwaddr=BC:24:11:A1:D7:58,ip=dhcp \
  --onboot 1 --ssh-public-keys /root/.ssh/emil.pub
pct start 113
pct exec 113 -- ip -4 -br addr show eth0
```

### UniFi: reserve `192.168.1.103`

Skip this on a rebuild: the reservation is already there.

1. Network → Client Devices → the client with MAC `bc:24:11:a1:d7:58`.
1. Settings → IP Settings → Fixed IP Address `192.168.1.103`, name `ansible-controller`, Apply.
1. On the host, check that the address is `.103`:

   ```sh
   pct reboot 113
   pct exec 113 -- ip -4 -br addr show eth0
   ```

### `113`: bootstrap

```sh
pct enter 113
export TERM=xterm-256color
apt update && apt install -y git
rm -rf /root/ansible
git clone https://github.com/emillassen/ansible-homelab.git /root/ansible
/root/ansible/bootstrap-controller.sh https://github.com/emillassen/ansible-homelab.git
rm -rf /root/ansible
exit
```

It upgrades the image, asks for the vault password, applies `site.yml` to itself, then runs `check` over SSH. The last recap must show `changed=0`. It is safe to re-run after a failure. Then reboot onto the upgraded packages and check from the laptop:

```sh
pct reboot 113
```

```sh
ssh ansible-controller run check --limit ansible-controller
```

### Proxmox host: controller access to the old guests

Copying data needs the controller's key on every old guest, plus `rsync` and `python3`. Every `pct exec` and `qm guest exec` reads `/dev/null`; otherwise the first one swallows the rest of a paste. The host keys are read through `pct` and the guest agent, so they are trusted without a first-use scan. Add the printed lines to `known_hosts`. `key` is `controller_ssh_key` from `inventory/group_vars/all/main.yml`; change it here after rotating that key.

```sh
key='ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILN3J6Yob8INNpKUODlZxy5FSonPRb2FAa3rAChBC/zr ansible-controller'
for id in 100 101 102 103 104 105 106 107 108 109 110 111 112; do
  pct exec $id -- bash -c "
    apt update && apt install -y openssh-server rsync python3
    install -d -m 700 /root/.ssh
    grep -qxF '$key' /root/.ssh/authorized_keys 2>/dev/null || echo '$key' >> /root/.ssh/authorized_keys
    chmod 600 /root/.ssh/authorized_keys
    systemctl enable --now ssh" </dev/null
done
for id in 100 101 110 111; do
  pct exec $id -- ufw allow from 192.168.1.103 to any port 22 proto tcp comment 'ansible controller' </dev/null
done
for id in 201 202 203 204 205 206 208; do
  qm guest exec $id --timeout 120 -- bash -c "
    grep -qxF '$key' /home/emil/.ssh/authorized_keys || echo '$key' >> /home/emil/.ssh/authorized_keys
    command -v rsync >/dev/null || apt install -y rsync" </dev/null
done
for p in 100:adguard-old 101:wireguard-old 102:bentopdf-old 103:mosquitto-old 104:zigbee2mqtt-old \
  105:esphome-old 106:homepage-old 107:smokeping-old 108:myspeed-old 109:changedetection-old \
  110:caddy-old 111:jellyfin-old 112:uptime-kuma-old; do
  printf '%s %s\n' "${p#*:}" "$(pct exec ${p%%:*} -- cut -d' ' -f1,2 /etc/ssh/ssh_host_ed25519_key.pub </dev/null)"
done
for p in 201:immich-old 202:miniflux-linkding-old 203:audiobookshelf-old 204:grafana-loki-old \
  205:paperless-old 206:nextcloud-old 208:meshmonitor-old; do
  printf '%s %s\n' "${p#*:}" "$(qm guest exec ${p%%:*} -- cut -d' ' -f1,2 /etc/ssh/ssh_host_ed25519_key.pub </dev/null |
    python3 -c 'import json, sys; print(json.load(sys.stdin)["out-data"].strip())')"
done
```

After committing `known_hosts` and running `ssh ansible-controller sync`, check every old guest from `113` as root:

```sh
runuser -u ansible -- bash -c 'cd /opt/ansible && ANSIBLE_CONFIG=/opt/ansible/ansible.cfg ANSIBLE_COLLECTIONS_PATH=~/collections ANSIBLE_VAULT_PASSWORD_FILE=~/.vault-pass ~/venv/bin/ansible legacy -m ansible.builtin.ping'
```

### `113`: check the token

The secret is read without echo and passed to `curl` on stdin, so it stays out of history and the process list. Paste the `read` line on its own, type the secret and press Enter, then paste the rest. Pasted together, `read` swallows the next line instead of waiting. If you don't have the secret to hand, `.venv/bin/ansible-vault view inventory/group_vars/all/vault.yml` on the laptop shows it.

```sh
read -rs SECRET
```

```sh
printf 'Authorization: PVEAPIToken=ansible@pve!provision=%s\n' "$SECRET" |
  curl -sS --cacert /opt/ansible/files/pve-root-ca.pem -H @- https://192.168.1.100:8006/api2/json/access/permissions
unset SECRET
```

It must list exactly `/pool/ansible`, `/vms/903`, `/storage/local-zfs`, `/storage/local` and `/sdn/zones/localnetwork`.

### GitHub: Renovate

Install the Renovate app on the repo. It opens a dependency dashboard issue and one PR per bump. Nothing merges on its own.

## Add a service

1. Add the host to `lxc` or `vm` in `inventory/hosts.yml` and write `inventory/host_vars/<host>/main.yml` (copy a neighbour; pick a new temporary MAC with the `BC:24:11` prefix).
1. Write `roles/<service>/` with versions pinned in `defaults/main.yml`, each under a `# renovate:` comment.
1. Add a play for it to `playbooks/site.yml`.
1. Commit, push, then:

   ```sh
   ssh ansible-controller sync
   ssh ansible-controller run provision --check --limit <host>
   ssh ansible-controller run provision --limit <host>
   ```

1. Add the printed host key line to `known_hosts`, the host to `managed`, and its temporary IP as `ansible_host`. Commit, push, then:

   ```sh
   ssh ansible-controller sync
   ssh ansible-controller run check --limit <host>
   ssh ansible-controller run apply --limit <host>
   ```

## Rebuild a guest

Before each rebuild, the report lists the data to copy, how, and how it will be tested. Below, `<host>` is the new guest, `<old>` and `<new>` are the old and new IDs.

1. Point the inventory at both guests. Add the old guest to `legacy_lxc` or `legacy_vm` in `inventory/hosts.yml` as `<host>-old`, with `ansible_host` (its production IP) and `migrate_roles` (the roles with a `migrate_export.yml`). In `inventory/host_vars/<host>/main.yml` set `legacy_host: <host>-old`, the new `vmid`, `net_production: false` and `ansible_host` to the temporary address. Copy the `<host>` line in `known_hosts` to a `<host>-old` line. Afterwards, remove all of it again.
1. Provision on the temporary MAC and DHCP address, as in "Add a service". Zigbee2MQTT and anything on NFS stay stopped.
1. Copy the data, if the service has any. The old guest lists its roles under `migrate_roles` in `inventory/hosts.yml`. The export stops the app on the old guest, so this is the start of the outage:

   ```sh
   ssh ansible-controller run migrate --check --limit <host>,<host>-old
   ssh ansible-controller run migrate --limit <host>,<host>-old
   ```

1. Set `net_production: true` and `ansible_host` back to the production IP in `inventory/host_vars/<host>/main.yml`. Commit, push, and `ssh ansible-controller sync`.
1. Stop the old guest and turn off its `onboot`. On the Proxmox host (use `qm` for a VM):

   ```sh
   pct shutdown <old> && pct set <old> --onboot 0
   ```

1. Swap the MAC (and set the static IP for AdGuard, WireGuard and Caddy). `provision` refuses while the old guest still answers on port 22:

   ```sh
   ssh ansible-controller run provision --limit <host>
   ssh ansible-controller run apply --limit <host>
   ssh ansible-controller run apply --limit <host>
   ```

   The second `apply` must show `changed=0`. Then test through the Caddy hostname with real data.

1. Rollback, on the Proxmox host. `<mac_temp>` is in `inventory/host_vars/<host>/main.yml`. For a VM use `qm` and `--net0 virtio=<mac_temp>,bridge=vmbr0,firewall=1`. For Zigbee2MQTT run `pct exec <new> -- systemctl disable --now zigbee2mqtt` first, so 116 can't take the coordinator back on its next boot:

   ```sh
   pct stop <new>
   pct set <new> --net0 name=eth0,bridge=vmbr0,firewall=1,hwaddr=<mac_temp>,ip=dhcp
   pct set <old> --onboot 1
   pct start <old>
   ```

   Then revert the `host_vars` commit.

A rebuild is done when it's accepted and has a backup (the nightly vzdump picks up new IDs). The old guest stays stopped until you delete it.

### A lost guest

Restore it from its nightly vzdump on Holocron; that brings the data and the `.migrated` markers back, and `run check --limit <host>` should then show nothing to do.

Provisioning it again with no old guest to copy from (a fresh install) leaves each app with copied data stopped: its start is gated on `.migrated` in its data directory (the role's `*_marker` default or "Check for the migrated data" task). Once the data is in place, or to start empty on purpose, create the marker on the guest and apply:

```sh
touch <data directory>/.migrated
ssh ansible-controller run apply --limit <host>
```

## Apply a Renovate PR

1. Read the PR and the upstream release notes, then merge it.
1. Then:

   ```sh
   ssh ansible-controller sync
   ssh ansible-controller run check --limit <host>
   ssh ansible-controller run apply --limit <host>
   ```

A bump to `ansible-core`, `uv` or a collection takes effect at `sync`. Follow it with `run check` with no `--limit`. A change to `scripts/` reaches `113` only at `run apply --limit ansible-controller`.

## Rotate secrets

### Proxmox token

```sh
pveum user token remove ansible@pve provision
pveum user token add ansible@pve provision --privsep 0 --comment "controller 113"
```

Then on the laptop, `.venv/bin/ansible-vault edit inventory/group_vars/all/vault.yml`, commit, push, and `ssh ansible-controller sync`.

### Vault password

```sh
.venv/bin/ansible-vault rekey inventory/group_vars/all/vault.yml roles/controller/files/*.vault
```

Commit and push, then on `113` as root:

```sh
/home/ansible/src/bootstrap-controller.sh https://github.com/emillassen/ansible-homelab.git --reset-vault-pass
```

### Controller key

This replaces the controller's client key. Its host key stays, so `known_hosts` on the laptop, on `207` and in the repo doesn't change. The new public key goes everywhere before the private key is swapped, and each step must finish with no failed or unreachable host before the next.

1. Copy the current `controller_ssh_key` value into `controller_ssh_key_previous` in `inventory/group_vars/all/main.yml`.
1. Make the new key and put the printed value in `controller_ssh_key`, then commit and push:

   ```sh
   PATH="$PWD/.venv/bin:$PATH" scripts/new-controller-keys.sh --rotate
   ```

1. Give every guest except the controller both keys. The recap must show `failed=0` and `unreachable=0` for every host:

   ```sh
   ssh ansible-controller sync
   ssh ansible-controller run apply --limit 'managed:!ansible-controller'
   ```

1. If old guests are still running, add the new key to them with the "controller access to the old guests" block in [Bootstrap](#bootstrap), with `key=` set to the new key.
1. Swap the controller's private key. Its own `root` login gets both keys first:

   ```sh
   ssh ansible-controller run apply --limit ansible-controller
   ```

1. Set `controller_ssh_key_previous` back to `""`, commit, push, then `sync` and `run apply`. It now connects with the new key and removes the old one. Remove the old key from any old guests by hand.

### The `207` key

Re-run the `207` block in [Bootstrap](#hermes-207-the-agents-key-optional), update `hermes_ssh_key`, commit, push, then `sync` and `run apply --limit ansible-controller`.

## Temporary laptop key

During the rebuild, a key without a passphrase at `~/.ssh/homelab-temp` stands in for the YubiKey: it is `emil_ssh_key_temp` (controller and every guest), and a write deploy key on this repo. A second one, `~/.ssh/homelab-temp-signing`, signs the repo's commits (GitHub won't take a deploy key as a signing key). A third, `emil_ssh_key_work`, lets the work laptop (`C:\Users\<you>\.ssh\homelab-work`) run commands on the controller and log in to the VMs as `emil`, only from `wireguard_lan_ip`, where WireGuard traffic reaches the LAN. The old VMs got it by hand (paste below); they go away with their rebuilds. Remove them once everything is rebuilt:

1. Set `emil_ssh_key_temp: ""` and `emil_ssh_key_work: ""` in `inventory/group_vars/all/main.yml`, commit and push with the YubiKey, then:

   ```sh
   git config --unset core.sshCommand
   git config --unset gpg.format
   git config --unset user.signingkey
   ssh ansible-controller sync
   ssh ansible-controller run apply
   ```

1. In `Host ansible-controller` in `~/.ssh/config`, remove the `IdentityFile ~/.ssh/homelab-temp` and `IdentityAgent none` lines and uncomment `IdentityFile ~/.ssh/emillassen.pub`.
1. Delete the deploy key and the signing key on GitHub, then the files:

   ```sh
   gh repo deploy-key list
   gh repo deploy-key delete <id>
   gh ssh-key list
   gh ssh-key delete <id>
   rm ~/.ssh/homelab-temp ~/.ssh/homelab-temp.pub ~/.ssh/homelab-temp-signing ~/.ssh/homelab-temp-signing.pub
   ```

1. On the work laptop, delete `homelab-work` and `homelab-work.pub` from `.ssh` and the `Host ansible-controller` block from `.ssh\config`.

## Accepted risks

1. The controller key is root on every LXC and passwordless-sudo `emil` on every VM. Whoever holds `113` holds the fleet. SSH to `113` is key-only, from `.103`, `.42`, `.102` and `.225`.
1. The vault password sits in plain text in `/home/ansible/.vault-pass` (0600). It and the controller key reach Holocron in `113`'s nightly backup.
1. The `207` key has no passphrase. It can run `sync`, `check` and `apply`, not `provision` or `migrate`. With `207`'s account-wide `gh` token, an agent could push to `main` and apply it; "I merge" is a process rule, not a technical one.
1. New guests' host keys are trusted on first scan, over the LAN, right after creation.
1. The token's `VM.Allocate` on the pool can delete pool guests. No task uses `state: absent`.
1. VMs have no host firewall. SSH there is key-only but reachable from the whole LAN.
1. unattended-upgrades takes every origin, so third-party apt repos are not pinned. Guests reboot at 02:00 when needed.
1. The old community-scripts LXCs get no patches between removing the host cron and their rebuild.
1. Until they are removed, the temporary laptop keys have no passphrase. Whoever copies it gets root on every guest, `run` on the controller (including `provision` and `migrate`), push to this repo and commits that show as verified.
1. Nextcloud AIO updates itself daily, as upstream recommends.
1. The repo is public: IPs, MACs and public keys are visible, and the vault files can be attacked offline. The vault password must be long and random.
1. Python packages are pinned by version, not hash. Galaxy collections are not signature-checked.
1. A merged Renovate PR goes live on the next `apply`, breaking changes included.

## Resources

1. https://docs.ansible.com/projects/ansible/latest/
1. https://docs.ansible.com/projects/ansible/latest/collections/community/proxmox/
1. https://pve.proxmox.com/pve-docs/chapter-pveum.html
1. https://docs.renovatebot.com/
