# Changelog

All notable changes to this project are documented here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
Versions follow [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [Unreleased]

### Added

- Initial implementation: `capture`, `info`, `shell`, `copy`, `run`, `diff`
  subcommands
- Sparse `dd` capture with SIGINFO progress reporting
- Partition auto-selection when a disk has exactly one mountable partition
- Filesystem driver registry for future extension (squashfs, btrfs)
- Five-stage CI/CD pipeline with Trivy and Grype scanning
- Multi-platform Docker image (`linux/amd64`, `linux/arm64`)

[Unreleased]: https://github.com/1121citrus/usb-explore/compare/HEAD...HEAD
