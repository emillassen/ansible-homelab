# nfs_automount

NFS shares in fstab as systemd automounts (`hard`, with a mount timeout and a one-minute idle unmount), for roles that set `nfs_automount_shares`. Holocron's NFS rules match each guest's production address, so the automounts start only with `net_production`, and the role then fails unless every share is mounted from its export (with a 30-second limit, since a hard mount on a dead server blocks).
