# ufw

Default-deny UFW on every LXC and the controller. SSH is open only from `ufw_ssh_sources`, service ports from `ufw_allow` in each host's `host_vars`.

The role adds rules and never removes them. A port taken out of `ufw_allow` stays open until it is deleted by hand:

```sh
ufw status numbered
ufw delete <number>
```

## Resources

1. https://docs.ansible.com/projects/ansible/latest/collections/community/general/ufw_module.html
