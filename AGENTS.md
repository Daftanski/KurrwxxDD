# UEFI_MGV workspace - agent rules and facts

Loaded in every chat (symlink `.UEFI_MGV/AGENTS.md`). Keep it one page.
General rules (any project): `~/.copilot/instructions/RADZIO.instructions.md`.
Hidden agent memory holds NO facts. Everything is here or in .notes/.

## Where things are
- Status (now, issues, fixes): `KurrwxxDD/.notes/STATUS.txt`. Read it at task start; update it when work changes.
- Knowledge: `KurrwxxDD/.notes/` (index: `.notes/README.txt`).
- Logs: `KurrwxxDD/.logs/` (never search it by default).
- Workstation scripts: `KurrwxxDD/development/*.sh`. Simics tests: `development/{uefi,kernel}-dev/misc/`. Agent skills: `development/skills/` (linked into ~/.config/opencode/skills).
- Driver repo: `networking.ipu.tools/boot/uefi/nic-core` (NicCorePkg generic, CnicPkg HAL). edk2 reference: `nic-core/edk2`.
- Branches and commits: git is the truth. Do not copy commit details into notes.

## Standing OKs (no need to ask)
- Commit on new local branches (`git commit -s`), amend/rebase own unpushed commits.
- Use any Simics host: restart, deploy, run tests.
- Update .notes/, AGENTS.md, development/.
- Never push. Ask before anything destructive or shared.

## Build and test
- Unit tests: `bash KurrwxxDD/development/uefi-dev/misc/dev/ut-nic-core.sh` (build all, run all, CRLF check).
- RELEASE build, no deploy (in nic-core): `rm -rf EFIx64` then
  `WORKSPACE=$PWD TARGET=RELEASE BUILD_TOOLS_PRECONFIGURED=1 BUILD_INCREMENTAL=1 EXTERNAL_SOURCES_ALLOWED=1 bash -c 'set --; source Scripts/Cnic/build_cnic.sh'` -> `EFIx64/E4999X10.EFI`.
- `EXEC_CNIC_BUILD.sh <ip>` = build + deploy (+ restart: outside the queue, prefer a LAVA `restart` step). `TARGET=DEBUG` for serial debug prints.
- Test scope: unit tests + only the targeted Simics test. Full suite ONLY when the user asks.
- Simics tests (UEFI and Linux): ONLY through LAVA, with the `lava-test` skill (`~/lava/svl/lava-test.sh`). Never run run-tests.sh / restart.sh / install.sh on a host by hand. No need to ask before a restart.
- Repo rules (nic-core): files are CRLF (check: lines == CR count before commit). Never commit: SharedNssip submodule, NicCorePkg/Include/Version.h (restore after builds), EXEC_CNIC_BUILD.sh, Build/, EFIx64/.

## Simics hosts
- Hosts, IPs, roles: `KurrwxxDD/config.txt` only. Use a host only for its role; ask before blocking it.
- One job per host. How to work: `development/doc/simics/` (start: 01-overview.txt).

## Linux kernel / ixd
- `development/doc/simics/02-linux.txt`.
- Kernel tree: `/home/mswiatko/kernels/os.linux.kernel.net-next`. `update-simics-kernel.sh <ip>` run from it = build + copy; install with a LAVA `install` step.

## UEFI driver
- `development/doc/simics/03-uefi.txt`. Not in suites: snpstate, snpdamage, txfill -> run `restart load <test>`.

## Other
- Workstation (workstation-ip in config.txt): no sudo, never reboot/delete.
- LAVA: `~/lava` (web/API http://localhost:8090), scripts `~/lava/svl` (links to development/lava). Details: `development/doc/lava/`. Agent's own tools: edit freely. Never commit `.env`, `token.env`, `ssh/`. Docker: shell may lack group docker -> `sg docker -c '...'`.
- Agent gotchas: terminal tool wraps at 80 cols (Simics serial log does not); UEFI `Print %02x` gives UPPERCASE hex; check a new file is non-empty before scp.

## Reporting
- Short report after every test: result + next step. No change summaries unless asked.
