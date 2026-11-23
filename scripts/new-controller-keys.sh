#!/usr/bin/env bash
# Laptop. First run: make the controller's SSH client key and host key and
# vault-encrypt the private halves into roles/controller/files/.
# --rotate: replace the client key only. The host key is kept, so nothing that
# trusts the controller's identity has to change.
# ansible-vault prompts for the vault password; the first time, this is where you choose it.
set -Eeuo pipefail

cd "$(dirname "$0")/.."
files=roles/controller/files

keys=(id_ed25519 ssh_host_ed25519_key)
if [ -e "$files/id_ed25519.vault" ]; then
  [ "${1:-}" = "--rotate" ] || { echo "keys exist; pass --rotate to replace the client key" >&2; exit 1; }
  keys=(id_ed25519)
fi
command -v ansible-vault >/dev/null || { echo "ansible-vault not on PATH (use .venv/bin)" >&2; exit 1; }

tmp="$(mktemp -d -p "${XDG_RUNTIME_DIR:-/tmp}")"
trap 'rm -rf "$tmp"' EXIT

read -rsp "Vault password: " pass; echo
read -rsp "Again: " pass2; echo
[ "$pass" = "$pass2" ] || { echo "they differ" >&2; exit 1; }
printf '%s\n' "$pass" > "$tmp/pass"
unset pass pass2

for k in "${keys[@]}"; do
  comment=ansible-controller
  [ "$k" = id_ed25519 ] || comment=root@ansible-controller
  ssh-keygen -q -t ed25519 -N '' -C "$comment" -f "$tmp/$k"
  ansible-vault encrypt --vault-password-file "$tmp/pass" --output "$files/$k.vault" "$tmp/$k"
  cp "$tmp/$k.pub" "$files/$k.pub"
done

echo
echo "inventory/group_vars/all/main.yml, controller_ssh_key:"
echo "  \"$(cat "$files/id_ed25519.pub")\""
if [ "${#keys[@]}" -eq 2 ]; then
  echo
  echo "known_hosts line:"
  echo "ansible-controller $(cut -d' ' -f1,2 "$files/ssh_host_ed25519_key.pub")"
fi
