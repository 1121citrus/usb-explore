# Contributing

Contributions are welcome. Please read this document before opening a pull
request.

## Development setup

1. Clone the repository.
2. Install [Docker Desktop](https://www.docker.com/products/docker-desktop/).
3. Run `./build --no-scan` to build the image and run the test suite.

## Code style

- Shell scripts must pass `shellcheck -S warning`.
- The `Dockerfile` must pass `hadolint`.
- Markdown files must pass `markdownlint`.
- All lines should stay under 80 characters where possible and must not
  exceed 120 characters.
- Use 4-space indentation in shell scripts.
- Use long-form flags with shell commands (`--output` not `-o`).

## Adding a new filesystem driver

1. Create `src/container/drivers/<name>.sh` implementing `<name>_detect`,
   `<name>_mount`, and `<name>_unmount`.
2. Register the driver in `src/container/dispatch.sh` by appending
   `<name>` to `FS_DRIVERS` (e.g. `FS_DRIVERS=(ext xfs vfat iso9660 <name>)`).
   Keep `iso9660` last — it mounts `/disk.img` directly and must be the
   fallback after all offset-based drivers.
3. Add the required package to `Dockerfile` **and** to the
   `fixtures/generate.sh` `apt-get install` list (the generator runs in
   its own container).
4. Add a fixture image to `test/fixtures/generate.sh` and test cases in
   `test/05-partition-discovery.bats` and `test/06-subcommands.bats`.
5. Remove the filesystem from both "not supported" locations:
   - `src/container/info.sh` — the `MOUNTABLE=false` case in the
     filesystem classification block.
   - `src/container/dispatch.sh` — the explicit error `case` arm at the
     bottom of `mount_partition`.

## Adding a new storage layer driver

Storage layers (LUKS, LVM) sit between partition detection and
filesystem mounting. They transform one block device into another.

1. Create `src/container/drivers/<name>.sh` implementing
   `<name>_detect`, `<name>_activate`, and `<name>_deactivate`.
2. Register the driver in `src/container/dispatch.sh` by appending
   `<name>` to `LAYER_DRIVERS`.
3. Add any required packages to `Dockerfile` and `fixtures/generate.sh`.
4. Add fixture images and test cases. Layer drivers need tests for
   activation, deactivation on error, stacked combinations, and
   credential handling if applicable.

## Pull requests

- Target the `dev` branch.
- Include a description of what changed and why.
- Ensure `./build --no-scan` passes before opening a PR.
- Include or update tests for any new behaviour.

## Commit messages

Use conventional commits: `type(scope): summary`.

Required body sections: `What changed`, `Why this change`,
`Behavioral impact` or `Validation`.

## Releasing

Releasing is two steps, in this order, because of a chicken-and-egg
constraint: GitHub only generates a tag's source tarball — and
therefore its sha256 — once that tag exists on `origin`. The Homebrew
formula's checksum can't be computed until after the tag is pushed,
so it can't be fixed in the same commit that creates the tag.

1. **Cut the release.**
   - Bump `version.txt` and promote `CHANGELOG.md`'s `[Unreleased]`
     section to a dated version section.
   - Push `main` and the new tag together, atomically:
     `git push --atomic origin main vX.Y.Z`.
2. **Update the Homebrew formula.** Once the tag is live on `origin`:

   ```bash
   ./install/homebrew/update-formula vX.Y.Z
   ```

   This fetches the tag's GitHub-generated tarball, computes its real
   sha256, and rewrites `install/homebrew/Formula/usb-explore.rb`'s
   `url`/`sha256` fields in place. Commit and push this separately —
   it does not need its own version bump or tag.

Skipping step 2 is the project's most common release mistake: the
formula's `url` silently points at a stale release, and
`brew install --formula ./install/homebrew/Formula/usb-explore.rb`
(the method documented in `README.md`) fails Homebrew's checksum
verification against whatever `sha256` was last committed. Only
`brew install --HEAD ...` (as used by `install/homebrew/test-formula`)
bypasses the `url`/`sha256` fields entirely, so that test path does
not catch a stale formula — step 2 must be done by hand, every
release.

## Licence

By contributing you agree that your contributions will be licenced under
the same [AGPL-3.0-or-later](LICENSE.md) licence as this project.
