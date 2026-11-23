# proxmox_guest

Creates and updates guests through the Proxmox API (`run provision`). LXCs come from the stock Debian 13 template, VMs are full clones of `903`. Each guest gets its temporary MAC and DHCP until `net_production: true` swaps it to the old guest's MAC (and, for AdGuard, WireGuard and Caddy, the static IP). The swap stops the guest first and refuses while the old guest still answers on port 22.

`run provision --check` shows what would change but cannot create, stop or start anything, so it skips the address and host-key report.

## Template `903`

Provisioning reads a new VM's address through the guest agent, so `903` must have `qemu-guest-agent` in the image. Build the image on the laptop:

```sh
mkdir -p ~/Downloads/ubuntu-2604 && cd ~/Downloads/ubuntu-2604
curl -LO https://cloud-images.ubuntu.com/releases/26.04/release/ubuntu-26.04-server-cloudimg-amd64.img
nix shell nixpkgs#guestfs-tools -c virt-customize -a ubuntu-26.04-server-cloudimg-amd64.img --install qemu-guest-agent
nix shell nixpkgs#guestfs-tools -c virt-customize -a ubuntu-26.04-server-cloudimg-amd64.img --no-network --truncate /etc/machine-id --delete /var/lib/dbus/machine-id
sha256sum ubuntu-26.04-server-cloudimg-amd64.img
scp ubuntu-26.04-server-cloudimg-amd64.img root@192.168.1.100:/var/lib/vz/template/iso/
```

The second `virt-customize` matters: the first writes a machine ID, and clones sharing one also share a DHCP client ID.

On the host, check that nothing is a linked clone of `903`, then rebuild it. Destroying `903` deletes the token's ACL on it, so the last lines put it back:

```sh
grep -l 'base-903' /etc/pve/qemu-server/*.conf
qm destroy 903
cd /var/lib/vz/template/iso
sha256sum ubuntu-26.04-server-cloudimg-amd64.img
qm create 903 --name ubuntu-2604-template --ostype l26 --memory 4096 --balloon 4096 --cores 4 --cpu=x86-64-v3 --net0 virtio,bridge=vmbr0,firewall=1 --agent enabled=1 --serial0 socket --vga serial0
qm importdisk 903 ubuntu-26.04-server-cloudimg-amd64.img local-zfs | tail -1
qm set 903 --scsihw virtio-scsi-single --scsi0 local-zfs:vm-903-disk-0,discard=on,iothread=1,ssd=1
qm set 903 --ide2 local-zfs:cloudinit
qm set 903 --boot c --bootdisk scsi0
qm set 903 --ipconfig0 ip=dhcp,ip6=dhcp
qm set 903 --ciuser emil
qm set 903 --sshkey <(echo "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEXHWIy7fzt9lviN1c9Yd7fuA7hCOYE7qc6RmmtojcBB emil@emillassen.com")
qm set 903 --onboot 1
qm resize 903 scsi0 32G
qm template 903
rm ubuntu-26.04-server-cloudimg-amd64.img
pveum acl modify /vms/903 --users ansible@pve --roles AnsibleClone
pveum acl list | grep /vms/903
```

## Stopping a run

Ctrl-C on `ssh ansible-controller run …` ends the play within a few seconds. If `run` reports `busy` and nothing should be running, look on the host:

```sh
pct exec 113 -- pgrep -af ansible-playbook
pct exec 113 -- pkill -f ansible-playbook
```

## Resources

1. https://docs.ansible.com/projects/ansible/latest/collections/community/proxmox/
1. https://pve.proxmox.com/wiki/Cloud-Init_Support
1. https://libguestfs.org/virt-customize.1.html
