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

- The disk image is bind-mounted **read-only** by default. The `edit`
  subcommand and `--rw` flag switch to read-write (see *Write mode*
  below).
- `--rm` removes the container immediately on exit. No state persists.
- The image contains only the tools required for the job (no package
  manager, no network stack).

If these trade-offs are not acceptable for your environment, do not use
this tool.

## Write mode

The `edit` subcommand and `--rw` flag on `shell`/`run` mount the disk
image read-write. This modifies the captured image in place.

**Risks:**

- **Journal replay.** Mounting a dirty ext4 or xfs filesystem
  read-write triggers automatic journal/log replay, modifying the
  image even if the user changes nothing.
- **Filesystem housekeeping.** btrfs performs background writes
  (balance, cleaner threads) on writable mounts.
- **Crash consistency.** An ungraceful container exit during a write
  session leaves the image dirty.
- **Inherently read-only formats.** squashfs, erofs, and iso9660
  reject `--rw` and `edit` with a clear error.

**Safety mechanism:** The `edit` subcommand creates an APFS reflink
backup (`.pre-edit`) before the first write session. On APFS volumes,
this is instant and free (copy-on-write; disk usage increases only as
blocks diverge). Rollback: `mv image.pre-edit image.img`.

The `--rw` flag on `shell` and `run` provides **no backup and no
confirmation** — it is intended for expert users who understand the
risks.

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
  throwaway test images, never for production images.

All decrypted volumes are opened with `cryptsetup --readonly`; the
source image is never modified.

## CVE tracking

The local `./build` script scans every image with **Trivy** (gating:
`--severity HIGH,CRITICAL --ignore-unfixed`), **Grype** (full severity,
no unfixed filter), and **Docker Scout**. The CI pipeline
(`.github/workflows/scan.yml`) runs the same Trivy gate. **MEDIUM** and
**LOW** findings are reviewed and accepted below; none are currently
suppressed via `.trivyignore.yaml` or `.grype.yaml` — those files stay
as placeholders for a future finding that genuinely needs a
time-boxed waiver (see the `expired_at` convention in
`.trivyignore.yaml`), rather than parking every accepted exception
there.

As of the 2026-10-28 review (image built from `ubuntu:24.04`, arm64):

- **CRITICAL: 0** and **HIGH: 0** across Trivy, Grype, and Scout.
- Docker Scout had previously flagged **CVE-2026-114605** (HIGH,
  "Uncontrolled Recursion", CVSS 7.5) in `dnspython`, and Grype flagged
  **CVE-2025-69534** (Medium) in `python3-markdown`. Both packages are
  hard `Depends` of `python3-samba` (pulled in transitively via
  `samba`), used only by Samba's optional AD-DC tooling
  (`samba-tool`, `samba_dnsupdate`) — this image execs only the
  `smbd` binary (`src/container/dispatch.sh:611`) and never loads
  Samba's Python bindings. The Dockerfile now force-purges both
  packages after install (`dpkg --force-depends --purge`), removing the
  vulnerable code from the image instead of carrying a waiver;
  `import samba`, `smbd --version`, and `testparm --version` remain
  functional without them. This was the only pair of findings in this
  review with any upstream fix at all (dnspython 2.9.0, Markdown
  3.8.1 — neither yet packaged for Ubuntu 24.04).
- `apt-get upgrade` already runs during build, so every package is at
  the latest version Ubuntu 24.04's repositories offer; confirmed via
  `apt-get upgrade` reporting "0 upgraded" against a freshly updated
  package index. Every remaining finding below has Grype
  `fix.state: not-fixed` or `wont-fix` — Ubuntu has not shipped (or, for
  `wont-fix`, will never ship) a patched package version. There is
  nothing left to fix by bumping a version pin or re-running the build.

Accepted MEDIUM/LOW findings (Grype full-severity scan; `fix` is
Grype's `fix.state` — `not-fixed` means no Ubuntu 24.04 package exists
yet, `wont-fix` means Ubuntu/Debian has decided not to patch it):

| Package(s) | Count | Severity | Fix | Reason accepted |
| --- | --- | --- | --- | --- |
| `rsync` | 33 | Medium | not-fixed | Only invoked locally by the `capture`/`clean --update-volume` subcommands against a user-chosen path or device; no `rsync --daemon` or network listener runs. |
| `libpython3.12-*`, `python3.12*` | 26 | Medium | not-fixed/wont-fix | CPython is a dependency of Samba's Python bindings and `mc`; usb-explore never execs `python3` with attacker-controlled input or untrusted scripts. |
| `libcups2t64` | 11 | Medium | not-fixed | CUPS client libraries pulled in by `samba-libs`; no CUPS daemon or print service runs in this image. |
| `jq`, `libjq1` | 10 | Medium | not-fixed | `jq` processes only the tool's own JSON output/config, never untrusted network input. |
| `libpcre2-8-0` | 7 | Medium | not-fixed | Regex engine linked by several tools; requires a crafted pattern as input, not reachable from attacker-controlled data here. |
| `libc-bin`, `libc6` | 6 | Medium | not-fixed | glibc base; local parsing/DoS issues not reachable from this read-only, offline tool. |
| `libgnutls30t64` | 6 | Medium | not-fixed | TLS library pulled by `samba`/`cryptsetup-bin`; this image runs no TLS or network service. |
| `bsdutils`, `fdisk`, `libblkid1`, `libfdisk1`, `libmount1`, `libsmartcols1`, `libuuid1`, `mount`, `util-linux` | 4 | Medium | not-fixed | Core partition/mount tooling — this tool's entire purpose is parsing a disk image the user already controls and chose to mount; same threat model as any disk-utility GUI. |
| `libexpat1` | 4 | Medium | not-fixed | XML parser not invoked on attacker-controlled data in this tool. |
| `libpopt0` | 3 | Medium | not-fixed | Command-line option parser linked by `lvm2`/Samba tools; parses only this container's own fixed argv. |
| `libavahi-client3`, `libavahi-common-data`, `libavahi-common3` | 3 | Low/Medium | not-fixed | Client stub `smbd` links to register the share over mDNS; the vulnerable `avahi-daemon` process (which parses inbound mDNS packets) is never started in this image. |
| `libgssapi-krb5-2`, `libk5crypto3`, `libkrb5-3`, `libkrb5support0` | 2 | Medium | not-fixed | Kerberos/GSSAPI libraries pulled by Samba for optional AD authentication; `smb.conf` here is `server role = standalone` with guest-only access, so GSSAPI is never negotiated. |
| `libtirpc-common`, `libtirpc3t64` | 2 | Medium | not-fixed | Legacy Sun RPC compatibility library pulled by Samba; no RPC/portmapper service runs. |
| `libacl1` | 2 | Medium | wont-fix | ACL library linked by `util-linux`/Samba; no fix planned upstream, not reachable from untrusted input in this tool's usage. |
| `dash` | 2 | Medium | not-fixed | `/bin/sh`; CVEs require executing an attacker-supplied shell script, and this image only runs its own first-party scripts. |
| `erofs-utils` | 2 | Medium | not-fixed | Requires a maliciously crafted EROFS filesystem — same accepted threat model as the other filesystem-parsing tools above. |
| `tar` | 2 | Medium | not-fixed | Used only by the explicit `archive` subcommand on user-chosen paths. |
| `gpgv` | 2 | Low | not-fixed/wont-fix | Not exercised by any usb-explore subcommand; pulled in transitively. |
| `libslang2` | 2 | Low | not-fixed | Terminal UI library used by `mc`, an optional interactive tool the user runs themselves inside their own container session. |
| `dmeventd`, `dmsetup`, `libdevmapper-event1.02.1`, `libdevmapper1.02.1`, `liblvm2cmd2.03`, `lvm2` | 1 | Medium | not-fixed | `dmeventd` (the LVM event-monitoring daemon) is never started; the `lvm` driver only runs one-shot `vgchange`/`lvcm`-style invocations. |
| `libglib2.0-0t64` | 1 | Medium | not-fixed | Linked transitively by Samba/D-Bus-related libraries; not exercised via untrusted network input. |
| `liblmdb0` | 1 | Medium | not-fixed | Embedded database linked by Samba's internal registry, touching only this container's own local config state. |
| `libpam-modules`, `libpam-modules-bin`, `libpam-runtime`, `libpam0g` | 1 | Medium | wont-fix | PAM stack pulled by Samba; no interactive login surface, container is `--rm` and non-persistent. |
| `libsasl2-2`, `libsasl2-modules-db` | 1 | Medium | not-fixed | SASL library pulled by Samba for optional auth mechanisms; the guest-only standalone `smb.conf` never negotiates SASL. |
| `perl-base` | 1 | Medium | not-fixed | Minimal Perl runtime pulled in transitively; usb-explore never execs a Perl script with untrusted input. |
| `coreutils` | 1 | Low | wont-fix | Long-standing `shred`/symlink-handling note; no fix planned upstream. |
| `icu` (`libicu74`) | 1 | Low | not-fixed | No fix available; not reachable in normal operation. |
| `systemd` (`libsystemd0`, `libudev1`) | 1 | Low | not-fixed | systemd is not run as PID 1 in this ephemeral container. |
| `shadow` (`login`, `passwd`) | 1 | Low | not-fixed | No interactive login surface; container is `--rm` and non-persistent. |

These findings are accepted because the image is an ephemeral,
`--rm`, read-only forensic tool that runs inside the Docker Desktop
Linux VM (see *Privileged container* above) and never processes
untrusted network input. They are re-reviewed on every base-image
refresh and will be dropped from this list as Ubuntu ships fixes.
Re-run the scan locally with `./build --no-test` to get the current,
itemized findings — the table above is a point-in-time snapshot and
the CVE IDs within each row will shift (mostly on `rsync` and
`python3.12`, both under active CVE assignment as of this review)
between reviews.

## Reporting a vulnerability

Open a GitHub issue marked **Security** or email the maintainer directly.
Please do not disclose vulnerabilities publicly before they have been
addressed.
