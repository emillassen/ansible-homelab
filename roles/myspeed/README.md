# myspeed

MySpeed from its pinned release zip, with Debian's Node.js. It runs as the `myspeed` user and can only write to `data/` and `bin/`, where it downloads the speed-test binaries. A Renovate bump unpacks the new zip over the old one and runs `npm ci` again.

`data/` holds `storage.db` (settings and results), the logs and the speed-test binaries MySpeed downloads itself. `run migrate` copies it.

## Resources

1. https://github.com/gnmyt/myspeed
1. https://docs.myspeed.dev/
