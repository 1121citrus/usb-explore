# bin/

Developer and installation scripts that are not part of the runtime.

## install

Install or uninstall `usb-explore` on macOS. Copies `src/usb-explore`
to a `PREFIX/bin` directory (default `/usr/local`).

```bash
# Install from a clone
./bin/install

# Install to a custom prefix
./bin/install --prefix ~/.local

# Uninstall
./bin/install --uninstall

# Preview without writing anything
./bin/install --dry-run
```

When run outside a clone (e.g., via `curl | bash`), the script
downloads `src/usb-explore` from GitHub.

Run `./bin/install --help` for all options.
