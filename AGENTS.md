# UEFI_MGV workspace - agent rules and facts

Loaded in every chat (symlink `.UEFI_MGV/AGENTS.md`). Keep it one page.
General rules (any project): `~/.copilot/instructions/RADZIO.instructions.md`.
Hidden agent memory holds NO facts. Everything is here or in .notes/.

## Where things are
- Status (now, issues, fixes): `KurrwxxDD/.notes/STATUS.txt`. Read it at task start; update it when work changes.
- Knowledge: `KurrwxxDD/.notes/` (index: `.notes/README.txt`).
- Logs: `KurrwxxDD/.logs/` (never search it by default).
- Workstation scripts: `KurrwxxDD/development/*.sh`. Simics test framework: `KurrwxxDD/development/uefi-dev/`.
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
- `EXEC_CNIC_BUILD.sh <ip>` = build + deploy + restart. `TARGET=DEBUG` for serial debug prints.
- Test scope: unit tests + only the targeted Simics test. Full suite ONLY when the user asks.
- uefi-dev Simics tests run ONLY through LAVA (`~/lava/svl/submit.sh`, `results.sh --wait`). Never run its run-tests.sh on a host by hand. Missing LAVA support for a test = add it first (`development/doc/lava/`).
- kernel-dev tests: NO LAVA (user choice), run by hand over ssh. How: "Linux kernel / ixd" below.
- Repo rules (nic-core): files are CRLF (check: lines == CR count before commit). Never commit: SharedNssip submodule, NicCorePkg/Include/Version.h (restore after builds), EXEC_CNIC_BUILD.sh, Build/, EFIx64/.

## Simics hosts
- Hosts, IPs, roles: `KurrwxxDD/config.txt` only. Use a host only for its role; ask before blocking it.
- One job per host. How to work: `development/doc/simics/` (start: 01-overview.txt).

## Linux kernel / ixd
- `development/doc/simics/02-linux.txt`.
- Kernel tree: `/home/mswiatko/kernels/os.linux.kernel.net-next`. Deploy: `update-simics-kernel.sh <ip>` run from it.
- Tests, when a kernel/ixd change needs checking (do NOT read test sources to choose):
  1. Pick: `bash KurrwxxDD/development/kernel-dev/misc/run-tests.sh list` (local; per test: args, what, Needs, Changes, Time; suites).
  2. Changed tests locally? `development/setup-kernel-dev.sh <ip> copy` first.
  3. Run: `ssh root@<ip> /root/SimicsWorkspace/development/kernel-dev/misc/run-tests.sh <tests|suite>`, or `.../misc/tests/<name>.sh [args]` for args.
  4. Changes none/port = just run. driver or `restart` = host must be free (`who` on host and guest, no SFs/bridges) else ask.
  5. Result: last line `== failed: none` (single test: exit 0). On FAIL read only that test + `misc/readme.txt` "Known".
- New test: `development/kernel-dev/misc/readme.txt` "Rules" (line 2 = catalog entry).

## UEFI driver
- `development/doc/simics/03-uefi.txt`. Not in suites: snpstate, snpdamage, txfill -> run `restart load <test>`.

## Other
- Workstation (workstation-ip in config.txt): no sudo, never reboot/delete.
- LAVA: `~/lava/svl` (`submit.sh PFD|PFP all`, `results.sh [--wait] <job>`). Details: `development/doc/lava/`. Agent's own tools: edit freely. Never commit `.env`, `token.env`, `ssh/`.
- Agent gotchas: terminal tool wraps at 80 cols (Simics serial log does not); UEFI `Print %02x` gives UPPERCASE hex; check a new file is non-empty before scp.

## Reporting
- Short report after every test: result + next step. No change summaries unless asked.
