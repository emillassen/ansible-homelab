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
ssh ansible-controller run verify --limit caddy
ssh ansible-controller run provision --check --limit caddy
ssh ansible-controller run migrate --check --limit mosquitto,mosquitto-old
```

`provision` and `migrate` are yours only; the `207` key can't run them.

## Verify

`run verify` (`playbooks/verify.yml`) checks that every guest is healthy, not only that its config matches. It changes nothing. A host fails with a list of everything wrong on it:

1. Every guest: no failed systemd units, local disks under 80%, no reboot pending for over 26 hours (unattended-upgrades reboots at 02:00).
1. Docker hosts: every container running and not unhealthy, except those in `verify_docker_exited_ok`.
1. From `host_vars`: `verify_units` must be active, `verify_http` must answer on the guest with its `status` (default 200, redirects not followed), `verify_tcp` ports must accept a connection, `verify_interfaces` must be up.

Run it after any `apply`, rebuild or Renovate merge, and whenever something seems off.

`ansible-verify.timer` on `113` runs it every morning at 07:30 and pushes the result to Uptime Kuma: up, or down with the failing hosts in the message. If it is busy behind another `sync` or `run`, it waits up to half an hour. The output is in `journalctl -u ansible-verify` on `113`. To set it up:

1. In Uptime Kuma, add a monitor of type Push named `Ansible verify`, heartbeat interval `90000` seconds (25 hours, so a missed night also alerts), retries `0`, with the Discord notification. Copy the token from the push URL: the part after `/api/push/` and before `?`.
1. On the laptop, add it to the vault, then commit, push, sync and apply:

   ```sh
   .venv/bin/ansible-vault edit inventory/group_vars/all/vault.yml   # vault_kuma_verify_push_token: "<token>"
   ssh ansible-controller run apply --limit ansible-controller
   ```

   Without the token, the controller role leaves the timer out.

## Nightly deploy

`ansible-nightly.timer` on `113` deploys `main` at 04:30, one guest at a time (AdGuard, Caddy and WireGuard last), and starts no new guest after 06:00. It skips the night if CI on that commit isn't green, `sync` fails, the Proxmox API, storage, DNS or NFS is down, or tonight's 23:30 backup didn't finish by 00:30. A guest without a good backup tonight, or still running unattended-upgrades, waits for the next night.

Per guest: `verify` first (a guest already failing isn't touched), then `apply -e nightly=true`, then `verify` again, which waits up to `verify_wait` (default 300 s) for the app to come up. A guest whose apply would reboot it, or that fails, is **held**: the job skips it until you fix the cause and release it. Nothing is rolled back.

```sh
ssh ansible-controller run held                      # what is held and why
ssh ansible-controller run hold immich postgres 18 upgrade by hand   # before merging such a PR
ssh ansible-controller run apply --limit immich      # after fixing the cause
ssh ansible-controller run release immich            # the next night deploys main to it
ssh ansible-controller run nightly --dry-run         # preflight and the plan, changes nothing
ssh ansible-controller run nightly --now             # a real run outside the window (90 min)
```

Reports are in `/home/ansible/nightly/runs/<date>.md` on `113`, logs in `nightly/logs/`. Two Uptime Kuma push monitors alert in Discord: `Nightly result` (down with a summary when anything wasn't deployed) and `Nightly ran` (06:30; down if no run finished). To set them up, make both as for `Ansible verify` above (heartbeat interval `90000`), add `vault_kuma_nightly_result_push_token` and `vault_kuma_nightly_ran_push_token` to the vault, then `run apply --limit ansible-controller`. Without both, the timers stay off.

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
# The nightly deploy reads the 23:30 backup task, which root owns.
pveum role add AnsibleAudit --privs "Sys.Audit"
pveum acl modify "/nodes/$(hostname)" --users ansible@pve --roles AnsibleAudit
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

Install the Renovate app on the repo. It opens a dependency dashboard issue and one PR per bump. An update only merges once the release is 3 days old (`minimumReleaseAge`).

Renovate merges minor, patch and digest updates itself once `lint` passes. It waits for that by its own runs, so a merge can take a few hours. Anything in `.github/workflows/` merges on its own too, majors included: it only affects CI, and it merges only when the required `lint` check passes. These still wait for you:

1. Majors of the apps and their parts. A Postgres major waits for approval on the dependency dashboard first.
1. Immich: server, machine learning and Valkey come as one PR. Its Postgres image isn't tracked; update it from the matching upstream Compose file.
1. Minors and majors in the root `requirements.txt`, `requirements-uv.txt` and `requirements.yml` (patches merge on their own). They take effect at `sync`, so follow one with `run check`.

Two pins follow upstream instead of their own release stream:

1. Zigbee2MQTT's pnpm has no pin: the role installs the version the tag's `package.json` names in `packageManager`.
1. Gotenberg is held below 9 (`allowedVersions`) to match the Gotenberg major in Paperless's upstream Compose file. Raise the limit when Paperless moves.

A merge changes `main` only. Nothing deploys until `sync` and `apply`.

### GitHub: CI and the ruleset on `main`

`.github/workflows/lint.yml` runs on every PR and every push to `main`:

1. `ansible-playbook --syntax-check` on every playbook, without the vault password
1. `ansible-lint`, with existing findings in `.ansible-lint-ignore`. Fix one and delete its line. Don't add new lines.
1. `shellcheck` on every tracked shell script
1. `renovate-config-validator --strict`

The ruleset on `main` requires a PR and a passing `lint` check, with no approvals required and no bypass. Every change, yours too, goes through a PR:

```sh
git switch -c <topic>
git push -u origin <topic>
gh pr create --fill
gh pr merge --auto --squash   # merges when lint passes
```

Repo setting: auto-merge allowed, head branches deleted after merge.

## Add a service

1. Add the host to `lxc` or `vm` in `inventory/hosts.yml` and write `inventory/host_vars/<host>/main.yml` (copy a neighbour; pick a new temporary MAC with the `BC:24:11` prefix).
1. Write `roles/<service>/` with versions pinned in `defaults/main.yml`, each under a `# renovate:` comment.
1. Add a play for it to `playbooks/site.yml`.
1. Add `verify_units` and `verify_http` (or `verify_tcp`) for it to `host_vars` (see "Verify").
1. Put any password, token or key the role writes in the vault (see "Secrets").
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

   The second `apply` must show `changed=0`, and `run verify --limit <host>` must pass. Then test through the Caddy hostname with real data.

1. Rollback, on the Proxmox host. `<mac_temp>` is in `inventory/host_vars/<host>/main.yml`. For a VM use `qm` and `--net0 virtio=<mac_temp>,bridge=vmbr0,firewall=1`. For Zigbee2MQTT run `pct exec <new> -- systemctl disable --now zigbee2mqtt` first, so 116 can't take the coordinator back on its next boot:

   ```sh
   pct stop <new>
   pct set <new> --net0 name=eth0,bridge=vmbr0,firewall=1,hwaddr=<mac_temp>,ip=dhcp
   pct set <old> --onboot 1
   pct start <old>
   ```

   Then revert the `host_vars` commit.

A rebuild is done when it's accepted and has a backup (the 23:30 PBS job picks up new IDs). The old guest stays stopped until you delete it.

### A lost guest

Restore it from its nightly PBS backup (see "Backups"); that brings the data and the `.migrated` markers back, and `run check --limit <host>` should then show nothing to do.

Provisioning it again with no old guest to copy from (a fresh install) leaves each app with copied data stopped: its start is gated on `.migrated` in its data directory (the role's `*_marker` default or "Check for the migrated data" task). Once the data is in place, or to start empty on purpose, create the marker on the guest and apply:

```sh
touch <data directory>/.migrated
ssh ansible-controller run apply --limit <host>
```

## Apply a Renovate PR

Renovate merges most PRs itself (see "GitHub: Renovate"). Deploy them like this; for a PR it left to you, read the PR and the upstream release notes first, then merge it.

```sh
ssh ansible-controller sync
ssh ansible-controller run check --limit <host>
ssh ansible-controller run apply --limit <host>
ssh ansible-controller run verify --limit <host>
```

A bump to `ansible-core`, `uv` or a collection takes effect at `sync`, which reinstalls the tooling only when a requirements file changed. If an install fails, `run` refuses until a `sync` succeeds. Follow a bump with `run check` with no `--limit`. A change to `scripts/` reaches `113` only at `run apply --limit ansible-controller`.

## Secrets

Every password, token and key that Ansible writes comes from the vault (`inventory/group_vars/all/vault.yml`), never generated on the guest, so a guest rebuilt from scratch gets the same logins. A role's default names the vault variable (`esphome_dashboard_password: "{{ vault_esphome_dashboard_password }}"`); a missing one fails the run with the variable's name.

Add one with `.venv/bin/ansible-vault edit inventory/group_vars/all/vault.yml`; a random value comes from `openssl rand -base64 32 | tr -d '/+=' | cut -c1-32`. Then commit, push, sync and apply.

Left with the app's data (PBS backups and `run migrate` bring them back), because the app writes and rewrites them itself: users and passwords inside an app's database (Uptime Kuma, Immich, Nextcloud, Jellyfin, Audiobookshelf, Grafana, AdGuard's `AdGuardHome.yaml`), WireGuard's `wg0.conf` (server key and peers), ESPHome's `secrets.yaml`, Linkding's `secretkey.txt` (losing it only signs everyone out) and Nextcloud AIO's own passwords.

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

## Backups

Every guest is backed up at 23:30 to Proxmox Backup Server (PBS), VM `217`. PBS stores the backups on Holocron over NFS, so they survive losing the Proxmox host.

PBS is set up by hand from these steps and is not managed by this repo: the controller is restored from PBS, so PBS has to be rebuildable without Ansible. It is not in the `ansible` pool, so the controller's token can't touch it.

|                         |                                                                                        |
| ----------------------- | -------------------------------------------------------------------------------------- |
| VM                      | `217`, name `pbs`, 2 cores, 4 GB RAM, 32 GB disk                                       |
| Address                 | `pbs.hjem.sh`, `192.168.1.122`, MAC `BC:24:11:B4:B5:EA`                                |
| Web UI                  | `https://pbs.hjem.sh` (through Caddy) or `https://192.168.1.122:8007`, user `root@pam` |
| Datastore               | `homelab` at `/mnt/pbs/homelab`, on Holocron's `proxmox-backup-server` share           |
| Proxmox storage         | `pbs`, token `pve@pbs!pve`                                                             |
| Retention               | 14 daily, 8 weekly, 6 monthly                                                          |
| In the password manager | PBS root password, token secret, PBS fingerprint                                       |

The steps below set it up from scratch. After losing the Proxmox host, follow them too, with the changes in "After losing the Proxmox host".

### 1. Holocron: the share

Skip this if the share already exists (after losing only the Proxmox host, it does).

1. Shares → Add Share, name `proxmox-backup-server`.
1. Primary storage: the array (or one pool). Secondary storage: **none**, so the mover never moves the backup files. Don't touch the share from Unraid afterwards (no unBalance, no scripts).
1. NFS: Export **Yes**, Security **Private**, Rule:

   ```text
   192.168.1.122(sec=sys,rw,no_root_squash)
   ```

   `no_root_squash` is required: PBS creates the datastore as root and hands it to its `backup` user (uid 34). Without it, creating the datastore fails with `EPERM`.

1. Check in the Unraid terminal that the line has `no_root_squash` and no `all_squash`:

   ```sh
   grep proxmox-backup-server /etc/exports
   ```

### 2. Proxmox host: create `217`

As root on the Proxmox host (`ssh root@192.168.1.100`). Take the ISO name and SHA256 from https://www.proxmox.com/downloads/proxmox-backup-server and compare the checksum:

```sh
cd /var/lib/vz/template/iso
wget https://enterprise.proxmox.com/iso/proxmox-backup-server_<version>.iso
sha256sum proxmox-backup-server_<version>.iso
```

```sh
qm create 217 --name pbs --ostype l26 --machine q35 --bios ovmf \
  --efidisk0 local-zfs:1,efitype=4m,pre-enrolled-keys=0 \
  --cpu host --cores 2 --memory 4096 --balloon 0 \
  --scsihw virtio-scsi-single --scsi0 local-zfs:32,iothread=1,discard=on \
  --net0 virtio=BC:24:11:B4:B5:EA,bridge=vmbr0,firewall=1 \
  --ide2 local:iso/proxmox-backup-server_<version>.iso,media=cdrom \
  --boot 'order=scsi0;ide2' --agent 1 --onboot 1
qm start 217
```

### 3. PBS: the installer

Open `217`'s console in the Proxmox web UI and install with:

1. Target disk: the 32 GB disk, ext4.
1. Root password: a new one, saved in the password manager.
1. Hostname `pbs.hjem.sh`, IP `192.168.1.122/24`, gateway `192.168.1.1`, DNS `192.168.1.101`.

After it reboots, remove the ISO on the Proxmox host:

```sh
qm set 217 --ide2 none
```

### 4. UniFi: reserve `192.168.1.122`

Skip this on a rebuild: the reservation is already there. PBS sets its address itself; the reservation only stops DHCP from handing `.122` to something else.

1. Network → Client Devices → the client with MAC `bc:24:11:b4:b5:ea`.
1. Settings → IP Settings → Fixed IP Address `192.168.1.122`, name `pbs`, Apply.

### 5. PBS: updates

In the web UI (`https://192.168.1.122:8007`, `root@pam`):

1. Administration → Repositories: disable both `enterprise` repositories, Add → `No-Subscription`.
1. Administration → Updates → Refresh, then Upgrade. Reboot if it asks.
1. Remove the subscription popup with the same apt hook as the Proxmox host. It re-patches the UI after every update of `proxmox-widget-toolkit`. From the Proxmox host (asks for PBS's root password twice):

   ```sh
   scp /etc/apt/apt.conf.d/no-nag-script root@192.168.1.122:/etc/apt/apt.conf.d/
   ssh root@192.168.1.122 'apt-get install --reinstall -y proxmox-widget-toolkit && grep -c NoMoreNagging /usr/share/javascript/proxmox-widget-toolkit/proxmoxlib.js && systemctl restart proxmox-backup-proxy'
   ```

   The second line must print `2`. The hook only runs on the next apt install, so if that line didn't run, the popup comes back; run it again.

   If the host has no hook yet (a fresh Proxmox install), create it as in "Remove the subscription popup" in `docs/proxmox/proxmox.md` of the `homelab` repo. Reload the UI with Ctrl+Shift+R.

### 6. PBS: the datastore

In the web UI under Administration → Shell (or SSH as root):

```sh
apt install -y qemu-guest-agent
systemctl start qemu-guest-agent
mkdir -p /mnt/pbs
echo '192.168.1.30:/mnt/user/proxmox-backup-server /mnt/pbs nfs _netdev,hard 0 0' >> /etc/fstab
systemctl daemon-reload
mount /mnt/pbs
touch /mnt/pbs/test && rm /mnt/pbs/test
proxmox-backup-manager datastore create homelab /mnt/pbs/homelab
```

It must end with `Access time update check successful.` and `TASK OK`. If the atime check fails, use the disk path (`/mnt/diskN/proxmox-backup-server`) in the export and in fstab instead of `/mnt/user/...`.

### 7. PBS: jobs, user and token

Prune at 12:00, garbage collection at 12:30 and verify on Sundays at 13:00, all outside the 23:30 backup and the night's updates:

```sh
proxmox-backup-manager prune-job create homelab-prune --store homelab --schedule '12:00' \
  --keep-daily 14 --keep-weekly 8 --keep-monthly 6
proxmox-backup-manager datastore update homelab --gc-schedule '12:30'
proxmox-backup-manager verify-job create homelab-verify --store homelab --schedule 'sun 13:00' \
  --ignore-verified true --outdated-after 30
```

The user and token that Proxmox backs up with. A token only gets the rights its user also has, so both get the permission:

```sh
proxmox-backup-manager user create pve@pbs
proxmox-backup-manager user generate-token pve@pbs pve
proxmox-backup-manager acl update /datastore/homelab DatastoreBackup --auth-id 'pve@pbs'
proxmox-backup-manager acl update /datastore/homelab DatastoreBackup --auth-id 'pve@pbs!pve'
proxmox-backup-manager cert info | grep -i fingerprint
```

`generate-token` shows the secret only once. Save it and the fingerprint in the password manager.

### 8. Proxmox host: storage and backup job

As root on the Proxmox host:

```sh
pvesm add pbs pbs --server 192.168.1.122 --datastore homelab \
  --username 'pve@pbs!pve' --password '<token secret>' \
  --fingerprint '<fingerprint>' --content backup
pvesm status --storage pbs
```

The status must say `active`. Then the backup job: every guest except PBS itself (`217`, it is rebuilt from these steps, not restored) and `901`, mail on failure, retention left to PBS:

```sh
pvesh create /cluster/backup --schedule '23:30' --storage pbs --all 1 --exclude 217,901 \
  --mode snapshot --prune-backups keep-all=1 --notes-template '{{guestname}}' \
  --mailto <your email> --mailnotification failure --enabled 1
pvesh get /cluster/backup
```

### 9. Check

1. Test one small guest now instead of waiting for 23:30. It must end with `Backup job finished successfully`:

   ```sh
   vzdump 114 --storage pbs --mode snapshot
   ```

1. The next morning, in the PBS web UI under Datastore → `homelab` → Content: every guest has a backup from 23:30.

### 10. PBS: mail and update notices

PBS is updated by hand: Administration → Updates → Upgrade in the web UI, then a reboot if a new kernel came in, outside 23:30 and 12:00–13:00. PBS only mails about pending updates with a subscription, so a timer asks for it at 05:00.

1. Configuration → Notifications: disable `mail-to-root` and `default-matcher`. Add an SMTP target `fastmail` (`smtp.fastmail.com`, TLS, your username and app password, from `pbs@<your domain>`, recipient `root@pam`) and a matcher `fastmail-matcher` (match all, target `fastmail`).
1. Configuration → Access Control → User Management → `root@pam` → E-Mail: your address. Then Test on the `fastmail` target.
1. In the shell, the daily check. It runs `apt update` and mails each new package version once:

   ```sh
   cat > /etc/systemd/system/pbs-update-notify.service <<'EOF'
   [Unit]
   Description=Refresh apt and mail new PBS package updates
   After=network-online.target

   [Service]
   Type=oneshot
   ExecStart=/usr/sbin/proxmox-backup-debug api create /nodes/localhost/apt/update --notify true
   EOF
   cat > /etc/systemd/system/pbs-update-notify.timer <<'EOF'
   [Unit]
   Description=Daily PBS update check with mail

   [Timer]
   OnCalendar=*-*-* 05:00:00
   Persistent=false

   [Install]
   WantedBy=timers.target
   EOF
   systemctl daemon-reload
   systemctl enable --now pbs-update-notify.timer
   systemctl start pbs-update-notify.service
   systemctl status pbs-update-notify.service --no-pager
   ```

   The status must show `TASK OK` and `status=0/SUCCESS`.

### After losing the Proxmox host

The backups are still on Holocron. Rebuild in this order:

1. Install Proxmox. Do "Proxmox host: user, token and pool for Ansible" from "Bootstrap": it gives a new token secret and the host a new CA.
1. Do steps 2, 3 and 5 above (create `217`, install, updates). Skip 1 and 4: the share and the reservation still exist.
1. Step 6, but attach the existing datastore instead of creating a new one, with `--reuse-datastore true` on the last command:

   ```sh
   proxmox-backup-manager datastore create homelab /mnt/pbs/homelab --reuse-datastore true
   ```

1. Step 7 in full: the jobs, the user and a **new** token (the old secret went with the old PBS). Save the new secret and fingerprint.
1. Steps 8 and 10: storage, backup job, mail and update notices.
1. On the Proxmox host, list the backups and restore `113` first, with its own ID. `113` is not in the `ansible` pool:

   ```sh
   pvesm list pbs
   pct restore 113 pbs:backup/ct/113/<time> --storage local-zfs
   pct start 113
   ```

1. On the laptop, point the repo at the new host, as in "Laptop: CA and vault": copy the new CA into `files/pve-root-ca.pem`, put the new token secret in the vault (`.venv/bin/ansible-vault edit inventory/group_vars/all/vault.yml`), commit, push, then `ssh ansible-controller sync`.
1. Restore every other guest with its own ID, **into the `ansible` pool** (the pool membership isn't in the backup, and without it the controller's token can't manage the guest). Restore the VM template `903` first and re-run its ACL line from "Bootstrap" (`pveum acl modify /vms/903 ...`):

   ```sh
   pct restore <id> pbs:backup/ct/<id>/<time> --storage local-zfs --pool ansible
   qmrestore pbs:backup/vm/<id>/<time> <id> --storage local-zfs --pool ansible
   ```

   Start the guests (`pct start <id>` / `qm start <id>`), or reboot the host so `onboot` starts them in order.

1. Check from the laptop. It should show nothing to do:

   ```sh
   ssh ansible-controller run check
   ```

## Accepted risks

1. The controller key is root on every LXC and passwordless-sudo `emil` on every VM. Whoever holds `113` holds the fleet. SSH to `113` is key-only, from `.103`, `.42`, `.102` and `.225`.
1. The vault password sits in plain text in `/home/ansible/.vault-pass` (0600). It and the controller key reach Holocron in `113`'s nightly backup.
1. The `207` key has no passphrase. It can run `sync`, `check` and `apply`, not `provision` or `migrate`. With `207`'s account-wide `gh` token, an agent can't push to `main` (the ruleset requires a PR with a passing `lint`), but it can open and merge its own PR and then apply it; "I merge" is a process rule, not a technical one.
1. New guests' host keys are trusted on first scan, over the LAN, right after creation.
1. The token's `VM.Allocate` on the pool can delete pool guests. No task uses `state: absent`.
1. The firewalls are inside the guests (UFW, and DOCKER-USER for published Docker ports), so root on a guest can turn its own off. Jellyfin, Mosquitto, AdGuard's DNS, Caddy, WireGuard's UDP port and Talk's TURN port stay open to the whole flat LAN, for the clients that use them directly.
1. unattended-upgrades takes every origin, so third-party apt repos are not pinned. Lists refresh at 00:30, installs run at 01:00 and guests reboot at 02:00 when needed.
1. The old community-scripts LXCs get no patches between removing the host cron and their rebuild.
1. Until they are removed, the temporary laptop keys have no passphrase. Whoever copies it gets root on every guest, `run` on the controller (including `provision` and `migrate`), push to this repo and commits that show as verified.
1. Nextcloud AIO updates itself daily, as upstream recommends.
1. The repo is public: IPs, MACs and public keys are visible, and the vault files can be attacked offline. The vault password must be long and random.
1. Python packages are pinned by version, not hash. Galaxy collections are not signature-checked.
1. Caddy's Go and xcaddy downloads and the AdGuard Home download are checked against the checksums upstream publishes, fetched at apply time over HTTPS, not pinned in the repo. A compromised upstream release passes, and an outage blocks that apply.
1. A merged Renovate PR goes live on the next `apply`, breaking changes included. Minor, patch and digest updates merge without review; `lint` checks syntax and style, not whether the new version works.
1. Third-party apt repos (Docker, Jellyfin, NodeSource) can ship a major through unattended-upgrades, outside Renovate.
1. Backups are on Holocron, in the same house, with no off-site copy. PBS doesn't encrypt them; Holocron's disk encryption covers stolen or discarded disks, not access to the running Holocron or the share.
1. PBS doesn't hold the NFS-backed app data (Immich library, Nextcloud data, books) or Jellyfin's media; backing those up is Holocron's job.

## Resources

1. https://docs.ansible.com/projects/ansible/latest/
1. https://docs.ansible.com/projects/ansible/latest/collections/community/proxmox/
1. https://pve.proxmox.com/pve-docs/chapter-pveum.html
1. https://docs.renovatebot.com/
