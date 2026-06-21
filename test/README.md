# Test suite

Tests use [BATS](https://bats-core.readthedocs.io/) and run inside
Docker — no test tools are needed on the host.

## Running tests

```bash
# Full build + test (recommended)
./build --no-scan

# Regenerate fixtures only (idempotent; skips existing images)
bash test/fixtures/generate.sh
```

Individual test files can be run with the Docker BATS image:

```bash
docker run --rm \
    -v "$PWD:$PWD" -w "$PWD" \
    -v /var/run/docker.sock:/var/run/docker.sock \
    -e "IMAGE=1121citrus/usb-explore:dev-latest" \
    bats/bats:1.13.0 \
    test/08-cli.bats
```

## Test files

| File | What it covers | Docker needed? |
| --- | --- | --- |
| `01-build.bats` | `build` script flags, dry-run output | No |
| `02-image-structure.bats` | Dockerfile layer structure, installed binaries | Yes (image inspect) |
| `03-invocation.bats` | Container entrypoint, subcommand routing | Yes (container run) |
| `04-env-metadata.bats` | OCI labels, `APP_VERSION` env vars | Yes (image inspect) |
| `05-partition-discovery.bats` | `info` output for every fixture image | Yes (container run) |
| `06-subcommands.bats` | `copy`, `run`, `hash`, `diff`, `find`, `archive` | Yes (container run) |
| `07-capture.bats` | `_fmt_bytes`, `_progress_monitor` helpers | No |
| `08-cli.bats` | Host CLI argument parsing, validation, docker stubs | No |
| `09-install.bats` | `bin/install` flags, temp-prefix install/uninstall | No |
| `10-runtime-compat.bats` | `test/runtime-compat` wrapper script | No |

## Out-of-suite tests

These are not part of the normal build. Run them manually.

| Script | Purpose |
| --- | --- |
| `install-methods` | Validates all four README installation paths in isolation |
| `runtime-compat` | Tests the active container runtime (Docker Desktop, OrbStack, etc.) |

## Fixtures

Test disk images live in `test/fixtures/`. See
[fixtures/README.md](fixtures/README.md) for the full list and
generation instructions.

## Coverage

Coverage is measured by `kcov` via `./build --advise coverage`. Only
the host-side `src/usb-explore` script is measurable — container-side
scripts run inside a separate Docker container that `kcov` cannot
trace into.
