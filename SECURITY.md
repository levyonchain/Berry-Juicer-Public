# Security Policy

## Scope

This repository contains the public components of Berry Juicer: interfaces, the
orchestration vault, periphery, and SDK. The proprietary position strategy is
not included here. Reports against the public contracts in `contracts/` are in
scope.

## Reporting a Vulnerability

Please do not open public issues for security vulnerabilities.

Email **security@berryfi.org** with:

- A description of the issue and its impact.
- Steps to reproduce, or a proof of concept.
- Affected contract(s), file path, and commit hash.

We aim to acknowledge reports within 72 hours.

A PGP key for encrypted reports is published at <https://berryfi.org/.well-known/security.txt>.

## Disclosure

We follow coordinated disclosure. Please give us reasonable time to investigate
and ship a fix before any public disclosure. A formal bug bounty program will
run alongside the independent audit prior to mainnet; details will be published
here when live.

## Out of Scope

- The proprietary Juicer position strategy (not in this repository).
- Third-party dependencies, which should be reported to their maintainers.
- Issues requiring privileged access to a user's own keys or wallet.
