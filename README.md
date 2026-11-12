# KurrwxxDD

Shared development and test environment for NIC drivers and firmware on Simics:
Simics setups (UEFI, Linux), a test framework, and a LAVA scheduler for automated runs.

## Layout

| Path | What |
|---|---|
| `development/` | Everything shared. Start with `development/README.txt`. |
| `development/uefi-dev/` | UEFI setup: EFI driver in the UEFI Shell, tests in `misc/`. |
| `development/kernel-dev/` | Linux setup: own kernel on the Simics guest. |
| `development/lava/` | LAVA server config, job template, `add-device.sh`. |
| `development/doc/` | How-to: `simics/` (platform), `lava/` (scheduler). |
| `config.example` | Template for the private `config.txt` (hosts, roles). |

## First steps

1. `cp config.example config.txt` and fill in your hosts. `config.txt` is not in git.
2. Set up LAVA once: `development/doc/lava/03-maintenance.txt`.
3. For each Simics host: install your ssh key, then run
   `development/setup-uefi-dev.sh <ip>` (UEFI) or `development/setup-kernel-dev.sh <ip>` (Linux),
   then `development/lava/add-device.sh <n>` to register it in LAVA.
4. Run tests through LAVA: `development/doc/lava/02-usage.txt`.

## Rules

- No IPs, passwords or tokens in committed files. Hosts live in `config.txt`, secrets in `~/lava`.
- Simics tests run only through LAVA, one job per host.
