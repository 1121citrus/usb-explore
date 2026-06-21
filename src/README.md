# Source layout

The codebase is split between host-side and container-side scripts.

## Host side

`usb-explore` is the main CLI. It runs natively on macOS, parses
arguments, and delegates to Docker for everything that requires Linux
filesystem tools. It has no dependencies beyond bash and Docker.

When installed (via `bin/install` or Homebrew), only this file is
copied. It locates the Docker image by registry tag, not by local
file path.

## Container side

Everything under `container/` runs inside the Docker image. The
Dockerfile copies `container/` to `/usr/local/lib/usb-explore/`.

| File | Purpose |
| --- | --- |
| `entrypoint.sh` | Container PID 1; validates `/disk.img` and hands off to `dispatch.sh` |
| `dispatch.sh` | Subcommand router, partition mounting, storage-layer pipeline, cleanup |
| `info.sh` | Partition table reporting (`info` / `info --json`) |
| `drivers/*.sh` | Filesystem and storage-layer drivers (see `drivers/README.md`) |

## Testing the host script in isolation

`src/usb-explore` has a source guard at the bottom:

```bash
[[ "${BASH_SOURCE[0]}" != "${0}" ]] && return 0
```

Tests can `source src/usb-explore` to load all function definitions
without triggering argument parsing. This enables unit-style tests
for pure functions like `_fmt_bytes` and validation logic in
subcommand functions.
