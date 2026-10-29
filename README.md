# VHDL learning projects

A flat, simulation-only collection of 14 industrial-style VHDL-2008 projects.
Each project has synthesizable RTL, a self-checking testbench, a README, and a
small Makefile. Everything runs with open tools: **GHDL** for simulation,
**GTKWave** for waveforms, and **GNU Make** for the build.

No vendor tools, no external IP, no vendor-specific primitives. The RTL is
plain `ieee.std_logic_1164` + `ieee.numeric_std`.

Current state: **4 of 14 projects complete** (01–04), all passing. See
[`PROGRESS.md`](PROGRESS.md) for the live tracker, known gaps, and next moves.

## Prerequisites

| Tool | Tested with | Purpose |
|---|---|---|
| GHDL | 5.x (mcode backend) | Analyze, elaborate, simulate |
| GTKWave | 3.3.x | View `.ghw` waveforms |
| GNU Make | 4.x | Build orchestration |
| Bash | 4.x+ | Project scaffolder |

Check the toolchain before building:

```sh
make check
```

This verifies that `ghdl`, `gtkwave`, and `make` are on `PATH` and prints their
versions. It does not need a display.

## Quick start

```sh
make check                 # verify tools
make list                  # show projects and descriptions
make test                  # run all testbenches, print PASS/FAIL
make test PROJECT=04-uart  # run one project
make wave PROJECT=04-uart  # run, then open build/uart_tb.ghw in GTKWave
make clean                 # remove build/ and .logs/
```

Every project is also self-contained:

```sh
cd 04-uart
make test
make wave
```

A successful run ends with a line like:

```text
uart: 19 checks, TEST PASSED
```

and the Make target exits with status 0. Any failed check is reported as
`severity error` during the run; the final summary raises `severity failure`,
which makes `make` return non-zero.

## Layout

```text
Makefile                  # aggregate commands
README.md                 # this file
PROGRESS.md               # live status tracker and roadmap
AGENTS.md                 # repo conventions and build contract
mk/project.mk             # shared per-project build rules
lib/util_pkg.vhd          # clog2, sat_signed, count_ones, is_power_of_two
lib/tb_pkg.vhd            # checks, wait_cycles, test summary
scripts/new-project.sh    # project scaffolder
NN-kebab-name/            # one folder per project
  README.md
  Makefile                # TOP / RTL / TB + include ../mk/project.mk
  *.vhd                   # RTL, optional *_model.vhd, TB
```

Folders are named `NN-kebab-name` so they sort and so the top-level Makefile
can discover them with `[0-9][0-9]-*/Makefile`. VHDL files use `snake_case`; the
testbench entity is `<project>_tb`.

## Conventions

- **VHDL-2008**, `ieee.numeric_std` only. Never `std_logic_arith`,
  `std_logic_unsigned`, or vendor libraries.
- Ports use `_i` / `_o` suffixes: `clk_i`, `rst_i`, `data_i`, `valid_o`.
- Active-high **synchronous** reset; one clock per module.
- All outputs are defaulted, `case` statements are complete, and generics are
  validated with elaboration-time assertions.
- RTL is synthesizable. Bus/sensor/plant models are simulation-only and are
  named `*_model.vhd` or live inside the testbench.
- Tutorial comments explain *why* (timing, bit growth, protocol edges); full
  theory lives in the project README.

## Build-system reference

The per-project Makefile is deliberately tiny:

```make
TOP := uart_tb
RTL := uart_pkg.vhd uart_tx.vhd uart_rx.vhd
TB  := uart_tb.vhd
include ../mk/project.mk
```

`mk/project.mk` analyzes into a per-project `build/` with:

```text
analyze: --std=08 --workdir=build -Wall
run:     --assert-level=failure --wave=build/$(TOP).ghw
```

Analysis order is explicit because GHDL does not infer dependencies:

```text
lib/util_pkg.vhd → lib/tb_pkg.vhd → *_pkg.vhd → leaf RTL → top
→ *_model.vhd → TB
```

GHDL is used with the mcode backend, so `-e` is still required before `-r`, but
there are no object files. Each project has its own work directory, so aggregate
tests are safe. Do not run two analyses against the same `build/` concurrently.

| Target | Behavior |
|---|---|
| `make` / `make help` | Print the command summary |
| `make check` | Verify `ghdl`, `gtkwave`, `make`; no display needed |
| `make list` | Table of projects and their README titles |
| `make test` | Run every project serially; log to `.logs/<project>.log` |
| `make test PROJECT=p` | Run one project |
| `make lint` | Analyze every project with `-Wall` |
| `make wave PROJECT=p` | Run the test, then launch GTKWave in the background |
| `make wave PROJECT=p GTKW=x.gtkw` | Same, with a saved layout |
| `make clean` | Remove all `build/` directories and `.logs/` |
| `make new NAME=15-watchdog TITLE="Watchdog timer"` | Scaffold a project |
| `make fmt PROJECT=p` | Rewrite that project's sources with `ghdl fmt` |

`make test` runs projects one at a time and captures output in
`.logs/<project>.log`. It prints a compact PASS/FAIL summary and, on failure,
the last lines of each failing log.

## GTKWave workflow

`make wave PROJECT=04-uart` runs the test first, then opens
`04-uart/build/uart_tb.ghw` in the background. The simulation is always
headless; GTKWave is only needed for the `wave` target.

This repo does not ship curated `.gtkw` layouts. Each project README lists the
hierarchical signal paths worth viewing. Add them in GTKWave, save your own
layout, and reuse it:

```sh
make wave PROJECT=04-uart GTKW=my-uart.gtkw
```

## Learning path

The projects build on each other but are not a single dependency chain. A
practical order:

| Stage | Projects | Focus |
|---|---|---|
| Basics | 01, 02, 03 | Combinational logic, counters/timers, input conditioning |
| Core protocols | 04, 05, 06, 07, 08 | UART, FIFO, SPI, I2C, CRC |
| Control and DSP | 09, 10, 11, 12 | PWM, quadrature, FIR, PID |
| Integration | 13, 14 | AXI4-Lite, UART sensor node capstone |

Projects 01–04 are complete. The rest are planned; see the roadmap below.

## Projects

| Folder | Build / focus | Status |
|---|---|---|
| `01-combinational-basics` | `mux4`, `prio_enc8`, hex→7-seg decoder | done |
| `02-counter-timer` | Loadable up/down counter, retriggerable one-shot | done |
| `03-input-conditioning` | 2-FF synchronizer, debouncer, edge detect, pulse stretch | done |
| `04-uart` | 8N1 TX/RX, 16× oversampling, framing/break errors | done |
| `05-sync-fifo` | Parameterized FIFO, count/almost flags, backpressure | planned |
| `06-spi-master` | CPOL/CPHA modes 0–3, multi-slave CS | planned |
| `07-i2c-master` | Master + EEPROM model, open-drain bus | planned |
| `08-crc` | Generic CRC-8/16/32 streaming, standard vectors | planned |
| `09-pwm-deadtime` | Complementary PWM, dead time, fault input | planned |
| `10-quadrature-decoder` | x1/x2/x4, position/direction/index | planned |
| `11-fir-filter` | Fixed-point symmetric FIR, `valid`/`ready` streaming | planned |
| `12-pid-controller` | Q-format PID, saturation, anti-windup | planned |
| `13-axi-lite-regfile` | AXI4-Lite slave, byte enables, master BFM | planned |
| `14-uart-sensor-node` | Capstone: UART + FIFO + CRC framed protocol | planned |

`make list` reads the first line of each project README, so the table above
and the command output stay in sync as READMEs are written.

## Adding a project

```sh
make new NAME=15-watchdog TITLE="Watchdog timer"
make test PROJECT=15-watchdog
```

The scaffolder creates a compilable passthrough with a smoke testbench,
Makefile, and README skeleton. Edit the RTL and README, then add the project to
the table above and to `PROGRESS.md`.

## Roadmap

1. Finish the remaining projects (05–14) in the order shown above.
2. Keep `PROGRESS.md` current: tracker, verification snapshot, next moves.
3. Final acceptance: `make clean && make check && make lint && make test`,
   plus a waveform smoke test and a README/signal-list consistency pass.
