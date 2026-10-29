# PROGRESS

Living status tracker for the VHDL learning repo. Update this file whenever a
project, README, or build-system item changes state.

- **Last updated:** 2026-10-29
- **Overall:** 5 of 14 projects complete. Lessons 01–05 have RTL, testbenches,
  and READMEs. Root `README.md` and CI are in place. Lesson 06 not started.

## Status at a glance

| Area | State | Notes |
|---|---|---|
| Toolchain (`make check`) | done | GHDL 5.x mcode, GTKWave, GNU Make |
| Root `Makefile` | done | `check list test lint wave clean new fmt` |
| `mk/project.mk` | done | Per-project `build/`, explicit analysis order |
| `lib/util_pkg.vhd` | done | `clog2`, `sat_signed`, `count_ones`, `is_power_of_two` |
| `lib/tb_pkg.vhd` | done | Protected-type counters, checks, `wait_cycles`, summary |
| `scripts/new-project.sh` | done | Scaffolds a compiling project |
| GitHub Actions CI | done | `.github/workflows/ci.yml`: check, lint, test on push/PR |
| Root `README.md` | done | Prereqs, quick start, layout, learning path, roadmap |
| Projects 01–05 | done | RTL + TB + Makefile + README, all passing |
| READMEs 01–05 | done | All five project docs complete |
| Projects 06–14 | not started | See roadmap below |

## Project tracker

Legend: RTL = synthesizable sources, TB = self-checking testbench,
Doc = project README.

| # | Project | RTL | TB | Doc | Test | Checks |
|---|---|---|---|---|---|---|
| 01 | `01-combinational-basics` | done | done | done | PASS | 45 |
| 02 | `02-counter-timer` | done | done | done | PASS | 14 |
| 03 | `03-input-conditioning` | done | done | done | PASS | 14 |
| 04 | `04-uart` | done | done | done | PASS | 19 |
| 05 | `05-sync-fifo` | done | done | done | PASS | 2577 |
| 06 | `06-spi-master` | not started | — | — | — | — |
| 07 | `07-i2c-master` | not started | — | — | — | — |
| 08 | `08-crc` | not started | — | — | — | — |
| 09 | `09-pwm-deadtime` | not started | — | — | — | — |
| 10 | `10-quadrature-decoder` | not started | — | — | — | — |
| 11 | `11-fir-filter` | not started | — | — | — | — |
| 12 | `12-pid-controller` | not started | — | — | — | — |
| 13 | `13-axi-lite-regfile` | not started | — | — | — | — |
| 14 | `14-uart-sensor-node` | not started | — | — | — | — |

## Verification snapshot

Last run: 2026-10-29

```text
make test   -> 5 passed, 0 failed
make lint   -> all projects analyzed cleanly
```

Commands used:

```sh
make clean && make check && make lint && make test
make test PROJECT=05-sync-fifo
```

## Known gaps / issues

1. No `.gtkw` layouts are shipped (by design); READMEs list hierarchical signal
   paths and users save their own.
2. Projects 06–14 are planned but not implemented.

## Next moves

Ordered, smallest useful increment first.

1. **Lessons 06–08.** SPI master (CPOL/CPHA 0–3, multi-slave CS), I2C master
   with EEPROM model and open-drain bus, generic CRC-8/16/32 with standard
   vectors.
2. **Lessons 09–12.** PWM + dead time + fault, quadrature decoder x1/x2/x4,
   symmetric fixed-point FIR with `valid`/`ready`, Q-format PID with
   saturation and anti-windup.
3. **Lessons 13–14.** AXI4-Lite register file with byte enables and master BFM;
   UART sensor-node capstone reusing `../04-uart`, `../05-sync-fifo`,
   `../08-crc` via explicit Makefile paths (do not copy RTL).
4. **Clean sweep.** `make clean && make check && make lint && make test`, wave
   smoke test, README/table/GTKWave-list consistency pass.

## Update protocol

When finishing an item:

1. Flip its cell in the tracker (`not started` → `done`, `**todo**` → `done`).
2. Update the check count from the test output (`N checks, TEST PASSED`).
3. Refresh `Last updated` and the verification snapshot if commands were rerun.
4. Add a line to the milestone log below.

## Milestone log

| Date | Change |
|---|---|
| 2026-10-29 | Foundation complete: root `Makefile`, `mk/project.mk`, `lib/`, scaffolder |
| 2026-10-29 | Lessons 01–03 complete (RTL + TB + Makefile), all passing |
| 2026-10-29 | Lesson 04 complete (UART TX/RX + TB + README), 19 checks |
| 2026-10-29 | Removed half-started `05-sync-fifo` on request |
| 2026-10-29 | Created this `PROGRESS.md` |
| 2026-10-29 | Wrote project READMEs for 01, 02, 03; `make list` descriptions now populated |
| 2026-10-29 | Wrote root `README.md` (prereqs, quick start, layout, build reference, roadmap) |
| 2026-10-29 | Lessons 01–04 marked complete; full clean/check/lint/test passes |
| 2026-10-29 | Added GitHub Actions CI (GHDL 5.0.1 mcode + GTKWave) on push/PR |
| 2026-10-29 | Lesson 05 complete (sync FIFO + 2577-check scoreboard TB + README); 5/5 tests pass |
