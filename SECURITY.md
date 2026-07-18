# Security policy

## Supported version

Security fixes target the latest GitHub Release and the current `master` branch.
Older downloaded scripts and locally modified copies are not patched in place.

## Reporting a vulnerability

Please use [GitHub's private vulnerability reporting form](https://github.com/okturan/MacNetStatsTerm/security/advisories/new)
instead of opening a public issue. Include the macOS version, shell and terminal,
the command or environment involved, clear reproduction steps, and the impact.

Reports are especially useful when they demonstrate:

- command or argument injection through interface selection, environment
  variables, or parsed system-command output;
- terminal escape injection or terminal-state damage beyond the documented
  limitation of an uncatchable `SIGKILL`;
- unsafe installation or release artifacts, including a mismatch between a
  release script and its published checksum;
- an Actions or release-workflow weakness that could alter distributed code.

Incorrect throughput, unsupported non-macOS behavior, and ordinary failures to
identify a VPN or unusual interface can be filed as normal bugs unless they
cross a security boundary. The utility reads interface counters; it does not
capture packets, inspect processes, or transmit traffic.

Do not include packet contents, credentials, or private network data. Synthetic
command output is preferred. The maintainer will coordinate validation,
remediation, and disclosure through the private advisory.
