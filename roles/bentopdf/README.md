# bentopdf

BentoPDF's prebuilt simple-mode site (`dist-simple-<version>.zip` from the release), served by Debian's nginx on 8443 with a self-signed certificate; 8080 redirects to it. The nginx site is the community-scripts one. Caddy proxies to `https://<ip>:8443` and skips certificate checks.

A Renovate bump removes the old site and unpacks the new zip. There's no data: everything runs in the browser.

## Resources

1. https://github.com/alam00000/bentopdf
