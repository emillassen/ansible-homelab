#!/bin/bash
# Managed by Ansible (roles/nextcloud). AIO's script for automatic updates without
# a backup first (the Proxmox backup covers the VM).

# Run container update once
if ! docker exec --env AUTOMATIC_UPDATES=1 nextcloud-aio-mastercontainer /daily-backup.sh; then
    while docker ps --format "{{.Names}}" | grep -q "^nextcloud-aio-watchtower$"; do
        echo "Waiting for watchtower to stop"
        sleep 30
    done

    while ! docker ps --format "{{.Names}}" | grep -q "^nextcloud-aio-mastercontainer$"; do
        echo "Waiting for Mastercontainer to start"
        sleep 30
    done

    # Run container update another time to make sure that all containers are updated correctly.
    docker exec --env AUTOMATIC_UPDATES=1 nextcloud-aio-mastercontainer /daily-backup.sh
fi
