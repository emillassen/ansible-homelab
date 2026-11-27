# ufw

Default-deny UFW on every guest. SSH is open only from `ufw_ssh_sources`, service ports from `ufw_allow` in each host's `host_vars`:

```yaml
ufw_allow:
  - port: "53"          # anyone
    proto: udp
  - port: "3000"        # only these sources
    proto: tcp
    from: "{{ web_client_sources }}"
```

`from` is one address or a list. `web_client_sources` (Caddy, Uptime Kuma, the admin laptop) is the usual one for a web UI; LAN clients reach it through Caddy.

On the Docker VMs only SSH is in UFW: Docker's published ports skip the INPUT chain, so they are limited by `docker_user_filter` instead (roles/docker_host).

When a port gains a `from`, the role deletes its old open-to-anyone rule. Otherwise it adds rules and never removes them: a port taken out of `ufw_allow`, or a source taken out of `from`, stays open until it is deleted by hand:

```sh
ufw status numbered
ufw delete <number>
```

## Resources

1. https://docs.ansible.com/projects/ansible/latest/collections/community/general/ufw_module.html
1. https://docs.docker.com/engine/network/packet-filtering-firewalls/
