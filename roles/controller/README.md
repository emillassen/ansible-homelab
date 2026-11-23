# controller

The Ansible controller, LXC `113` at `192.168.1.103`. The role installs the `ansible` user, its SSH key, the controller's host key (both restored from the vault, so a rebuilt `113` keeps its identity), and the `ansible-sync`, `ansible-run` and `agent-shell` commands.

What Ansible can't do here is in the bootstrap section of the [project README](../../README.md#bootstrap): creating the LXC, the UniFi reservation, the Proxmox token, the vault password and the key on `207`.

## Who can run what

| Key                      | Login on `113` | Allowed                                                                          |
| ------------------------ | -------------- | -------------------------------------------------------------------------------- |
| yours                    | `root`         | anything                                                                         |
| yours                    | `ansible`      | `sync`, `run check`, `run apply`, `run provision`                                |
| `hermes-207-ansible`     | `ansible`      | `sync`, `run check`, `run apply`, from `.225` only, when `hermes_ssh_key` is set |
| the controller's own key | `root`         | anything (the controller manages itself)                                         |

Every call through `agent-shell` is logged to the journal with the tag `agent-shell`:

```sh
journalctl -t agent-shell
```

## Rebuild `113`

1. Stop the old `113`, then destroy it in the Proxmox UI.
1. Run every block in [Bootstrap](../../README.md#bootstrap) from "Create `113`" on. The keys, the vault and the UniFi reservation are reused.

## Resources

1. https://man.openbsd.org/sshd.8#AUTHORIZED_KEYS_FILE_FORMAT
1. https://docs.astral.sh/uv/
