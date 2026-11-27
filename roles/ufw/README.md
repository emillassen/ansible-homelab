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

The role owns the ruleset: a rule that isn't declared any more (a port taken out of `ufw_allow`, a source taken out of `from`, the old open rule of a port that gained a `from`) is deleted on the next apply, and `run check` shows it first. A rule in a shape the role doesn't write (a route rule, a port range) is left alone and printed, so delete it by hand if it's unwanted:

```sh
ufw status numbered
ufw delete <number>
```

## Resources

1. https://docs.ansible.com/projects/ansible/latest/collections/community/general/ufw_module.html
1. https://docs.docker.com/engine/network/packet-filtering-firewalls/
