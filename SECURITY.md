# Security

## Privileged container

`usb-explore` runs its container with `--privileged` because `losetup`
(attaching the disk image to a loop device) and `mount` both require
`CAP_SYS_ADMIN` and must run as root inside the container. There is no
userspace alternative.

On macOS, Docker containers run inside an isolated Linux VM managed by
Docker Desktop. A container escape from `--privileged` reaches that VM,
not the macOS host filesystem. This is not a trivial risk, but it is
meaningfully smaller than root on your Mac.

Mitigations that are in place:

- The disk image is always bind-mounted **read-only**. The container
  cannot modify the source data.
- `--rm` removes the container immediately on exit. No state persists.
- The image contains only the tools required for the job (no package
  manager, no network stack).

If these trade-offs are not acceptable for your environment, do not use
this tool.

## SMB share (mount subcommand)

The `mount` subcommand starts an SMB server inside the container to
expose the partition as a Finder-mountable volume. Security properties:

- The SMB share is **read-only** (`read only = yes` in smb.conf).
- Guest/anonymous access only — no passwords are stored or transmitted.
- The share is bound to `localhost` via Docker port mapping (`-p
  PORT:PORT`). It is accessible to any process on the same machine
  but is **not reachable from the network**.
- NetBIOS is disabled (`disable netbios = yes`), eliminating broadcast
  discovery.
- SMB1 is disabled (`server min protocol = SMB2`).
- `force user = root` in the share definition allows reading all
  partition files regardless of their Linux UID. This is necessary
  because captured disk images contain files with arbitrary UIDs.

The SMB share is ephemeral — it exists only while the `mount` session
is running and disappears when the container stops.

## LUKS credential handling

The storage-layer feature can decrypt LUKS volumes. Credentials are
accepted three ways, in decreasing order of safety:

- **`--luks-passphrase-file PATH` (recommended).** The file is
  bind-mounted read-only at `/run/luks-passphrase` and read inside the
  container. The secret never appears in the process argument list or
  the container environment, so it is not visible to `ps`, `docker
  inspect`, or shell history.
- **`--luks-key-file PATH`.** Equivalent safety for binary key files;
  bind-mounted read-only at `/run/luks-key`.
- **`--luks-passphrase VALUE` (discouraged).** Passed to the container
  as the `USB_EXPLORE_LUKS_PASSPHRASE` environment variable, which is
  visible in `docker inspect` and process listings. Use only for
  throwaway test images, never for sensitive media.

All decrypted volumes are opened with `cryptsetup --readonly`; the
source image is never modified.

## CVE tracking

The CI pipeline scans every build with **Trivy**, **Grype**, and
**Docker Scout**, and blocks on any unfixed **HIGH** or **CRITICAL**
finding. **MEDIUM** and **LOW** findings are advisory and are reviewed
and accepted below.

As of the storage-layer dev build (scanned 2026-06-21):

- **CRITICAL: 0** and **HIGH: 0** across Trivy, Grype, and Scout.
- The storage-layer packages added by this feature — `cryptsetup-bin`,
  `lvm2`, and their libraries (`libcryptsetup12`, `libdevmapper1.02.1`,
  `libdevmapper-event1.02.1`, `liblvm2cmd2.03`, `dmsetup`, `dmeventd`)
  — produce **no scanner findings**. The feature introduces no new CVEs.
- The image already runs `apt-get upgrade` during build, so packages
  are at the latest patched Ubuntu 24.04 versions. The residual
  MEDIUM/LOW findings are inherited from the `ubuntu:24.04` base and are
  unfixed or marked "won't fix" upstream.

Accepted MEDIUM/LOW findings (canonical set per Docker Scout; Grype
reports a larger superset of the same `ubuntu:24.04` base packages):

| Package | CVE(s) | Severity | Reason accepted |
| --- | --- | --- | --- |
| glibc (`libc6`, `libc-bin`) | CVE-2026-6238, CVE-2026-5435, CVE-2026-4438, CVE-2026-4437, CVE-2026-4046 | Medium | No upstream fix; local parsing/DoS issues not reachable from this read-only, offline tool. |
| `python3.12` | CVE-2025-13462, CVE-2026-2297 | Medium | Python is a build/runtime dependency of `mc`/utilities, not exposed to untrusted network input. No fix available. |
| `expat` (`libexpat1`) | CVE-2025-66382 | Medium | XML parser not invoked on attacker-controlled data in this tool. No fix available. |
| `tar` | CVE-2025-45582 | Medium | `tar` is used only for the explicit `archive` subcommand on user-chosen paths. No fix available. |
| `util-linux` | CVE-2026-27456 | Medium | Inherited base CVE; no fix available. |
| `dpkg` | CVE-2026-2219 | Medium | `dpkg` is not used at runtime (no package manager operations). No fix available. |
| `libgcrypt20` | CVE-2024-2236 | Low | No fix available; not reachable in normal operation. |
| `icu` (`libicu74`) | CVE-2025-5222 | Low | No fix available; not reachable in normal operation. |
| `systemd` (`libsystemd0`, `libudev1`) | CVE-2026-40228 | Low | systemd is not run as PID 1 in this ephemeral container. No fix available. |
| `shadow` (`login`, `passwd`) | CVE-2024-56433 | Low | No interactive login surface; container is `--rm` and non-persistent. No fix available. |

These findings are accepted because the image is an ephemeral,
`--rm`, read-only forensic tool that runs inside the Docker Desktop
Linux VM (see *Privileged container* above) and never processes
untrusted network input. They are re-reviewed on every base-image
refresh and will be dropped from this list as Ubuntu ships fixes.

## Reporting a vulnerability

Open a GitHub issue marked **Security** or email the maintainer directly.
Please do not disclose vulnerabilities publicly before they have been
addressed.
