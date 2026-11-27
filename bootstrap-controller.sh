#!/usr/bin/env bash
# Configure a fresh controller LXC (113). Run as root inside it:
#   ./bootstrap-controller.sh https://github.com/emillassen/ansible-homelab.git [--reset-vault-pass]
# Safe to re-run.
set -Eeuo pipefail
umask 027
# Ansible needs a locale that exists; C.UTF-8 always does, even before base generates the rest.
export LANG=C.UTF-8 LC_ALL=C.UTF-8
# Never read a uv.toml from wherever this happens to run.
export UV_NO_CONFIG=1

repo_url="${1:-}"
reset_vault_pass=""
[ "${2:-}" != "--reset-vault-pass" ] || reset_vault_pass=1

home=/home/ansible

[ "$(id -u)" -eq 0 ] || { echo "run as root" >&2; exit 1; }
# shellcheck source=/dev/null
. /etc/os-release
[ "$VERSION_CODENAME" = trixie ] || { echo "expects Debian 13 (trixie)" >&2; exit 1; }
[ -n "$repo_url" ] || { echo "usage: $0 REPO_URL [--reset-vault-pass]" >&2; exit 64; }

echo "== ansible user"
id ansible >/dev/null 2>&1 || useradd --system --create-home --home-dir "$home" --shell /bin/bash ansible
install -d -o ansible -g ansible -m 0700 "$home/log" "$home/.ssh"
install -d -o ansible -g ansible -m 0750 /opt/ansible
# Commands run as ansible from here on; it cannot read /root.
cd "$home"

echo "== lock"
[ -e /home/ansible/run.lock ] || install -m 0644 -o ansible -g ansible /dev/null /home/ansible/run.lock
exec 9>>/home/ansible/run.lock
flock -n 9 || { echo "busy: another sync or run holds the lock" >&2; exit 75; }

echo "== packages"
apt update
# A fresh image is behind; start current. unattended-upgrades keeps it there.
DEBIAN_FRONTEND=noninteractive apt full-upgrade -y
apt install -y ca-certificates curl git openssh-client python3 python3-venv rsync util-linux
python3 -c 'import sys; sys.exit(sys.version_info < (3, 13))' || { echo "needs Python 3.13+" >&2; exit 1; }

echo "== repo"
if [ -d "$home/src/.git" ]; then
  runuser -u ansible -- git -C "$home/src" pull --ff-only
else
  runuser -u ansible -- git clone "$repo_url" "$home/src"
fi

echo "== uv and venv"
[ -x "$home/uv/bin/pip" ] || runuser -u ansible -- python3 -m venv "$home/uv"
runuser -u ansible -- "$home/uv/bin/pip" install --quiet --disable-pip-version-check -r "$home/src/requirements-uv.txt"
[ -x "$home/venv/bin/python" ] || runuser -u ansible -- env UV_PYTHON_DOWNLOADS=never "$home/uv/bin/uv" venv --python /usr/bin/python3 "$home/venv"

echo "== vault password"
while :; do
  if [ ! -s "$home/.vault-pass" ] || [ -n "$reset_vault_pass" ]; then
    read -rsp "Vault password: " pass1; echo
    read -rsp "Again: " pass2; echo
    [ "$pass1" = "$pass2" ] || { echo "they differ, try again"; continue; }
    install -m 0600 -o ansible -g ansible /dev/null "$home/.vault-pass"
    printf '%s\n' "$pass1" > "$home/.vault-pass"
    unset pass1 pass2
    reset_vault_pass=""
  fi

  echo "== sync"
  runuser -u ansible -- env ANSIBLE_LOCK_HELD=1 "$home/src/scripts/sync"

  if runuser -u ansible -- env ANSIBLE_CONFIG=/opt/ansible/ansible.cfg \
    "$home/venv/bin/ansible-vault" view --vault-password-file "$home/.vault-pass" \
    /opt/ansible/inventory/group_vars/all/vault.yml >/dev/null; then
    break
  fi
  echo "wrong vault password, try again"
  rm -f "$home/.vault-pass"
done

echo "== first apply, local"
cd /opt/ansible
ANSIBLE_CONFIG=/opt/ansible/ansible.cfg \
  ANSIBLE_VAULT_PASSWORD_FILE="$home/.vault-pass" \
  ANSIBLE_COLLECTIONS_PATH="$home/collections" \
  "$home/venv/bin/ansible-playbook" playbooks/site.yml --limit ansible-controller --connection local

exec 9>&-

echo "== steady state, over SSH"
/usr/local/sbin/ansible-run check --limit ansible-controller

cat <<'DONE'

Bootstrap finished. The recap above must show changed=0.
Next:
  rm -rf /root/ansible
  From the laptop: ssh ansible-controller run check --limit ansible-controller
  From 207:        ssh ansible-controller run check --limit ansible-controller
DONE
