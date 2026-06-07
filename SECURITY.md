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

## CVE tracking

Known CVEs accepted in the base image are listed below with justification.
The CI pipeline runs Trivy and Grype on every build and blocks on
HIGH/CRITICAL unfixed findings.

| CVE | Package | Accepted | Reason |
| --- | --- | --- | --- |
| (none accepted at release) | | | |

## Reporting a vulnerability

Open a GitHub issue marked **Security** or email the maintainer directly.
Please do not disclose vulnerabilities publicly before they have been
addressed.
