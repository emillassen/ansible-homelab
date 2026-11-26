# data_copy

Shared tasks for `run migrate`. A service role's `migrate_export.yml` stops its app and includes `dir_export`; its `migrate_import.yml` includes `dir_import` with `data_copy_service` set, which stops the app after the marker check and starts it after the import. The directory travels as a `tar.gz` through `/home/ansible/transfer` on the controller, which is deleted after the import.

`dir_import` writes `.migrated` into the directory right after the unpack, before the service starts. A run that finds it doesn't import again (the app may have written since); it only starts the service and cleans up, so a run that failed at the start can simply be repeated. An import that failed before the marker runs from the beginning. Delete `.migrated` to import again on purpose.

The controller holds each archive until its import, on a 32 GB disk. Migrate one host at a time (`--limit <host>,<host>-old`), and check the size of the old data first.

## Resources

1. https://docs.ansible.com/projects/ansible/latest/collections/ansible/builtin/unarchive_module.html
