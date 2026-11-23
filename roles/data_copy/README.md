# data_copy

Shared tasks for `run migrate`. A service role's `migrate_export.yml` stops its app and includes `dir_export`; its `migrate_import.yml` includes `dir_import` with `data_copy_service` set, which stops the app after the marker check and starts it after the import. The directory travels as a `tar.gz` through `/home/ansible/transfer` on the controller, which is deleted after the import.

`dir_import` writes `.migrated` into the directory and refuses to run again while it is there.

## Resources

1. https://docs.ansible.com/projects/ansible/latest/collections/ansible/builtin/unarchive_module.html
