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
   `<name>_driver` to `FS_DRIVERS`.
3. Add the required package to `Dockerfile`.
4. Add a fixture image and test cases in `test/05-partition-discovery.bats`
   and `test/06-subcommands.bats`.
5. Update `src/container/info.sh` to remove the filesystem from the
   "not supported" error table.

## Pull requests

- Target the `main` branch.
- Include a description of what changed and why.
- Ensure `./build --no-scan` passes before opening a PR.
- Include or update tests for any new behaviour.

## Commit messages

Use conventional commits: `type(scope): summary`.

Required body sections: `What changed`, `Why this change`,
`Behavioral impact` or `Validation`.

## Licence

By contributing you agree that your contributions will be licenced under
the same [AGPL-3.0-or-later](LICENSE.md) licence as this project.
