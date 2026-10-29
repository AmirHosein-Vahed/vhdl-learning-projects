# AGENTS.md

## Mission

Build and maintain a simulation-only VHDL-2008 learning repo: 14 flat projects,
each with synthesizable RTL, a self-checking testbench, a README, and a Makefile.
Toolchain: GHDL 5.x (mcode) + GTKWave + GNU Make. No vendor tools, external IP,
or vendor-specific primitives.

## Source of truth

The repo is scaffolded from this file. If a project is missing, create it using
the layout, conventions, and phases below. Do not invent a parallel structure.
Once code exists, the code and Make targets override this prose.

## Progress tracking

`PROGRESS.md` is the live status board: per-project tracker, verification
snapshot, known gaps, and ordered next moves. Update it whenever a project,
README, or build-system item changes state, and append to its milestone log.

## Layout

```text
Makefile                  # aggregate commands
README.md                 # user-facing quick start + learning path
mk/project.mk             # shared per-project build rules
lib/util_pkg.vhd          # clog2, saturate, helpers
lib/tb_pkg.vhd            # check procedures, wait_cycles, test summary
scripts/new-project.sh    # project scaffolder
NN-kebab-name/            # one folder per project
  README.md
  Makefile                # TOP/RTL/TB + include ../mk/project.mk
  *.vhd                   # RTL, optional simulation models, TB
```

Keep folder names `NN-kebab-name`; the top Makefile discovers projects via
`[0-9][0-9]-*/Makefile`. VHDL files use `snake_case`; the testbench entity is
`<project>_tb`.

## Commands (implement exactly)

```sh
make                                  # help
make check                            # verify ghdl/gtkwave/make
make list                             # project table
make test                             # all projects, PASS/FAIL summary
make test PROJECT=04-uart             # one project
make wave PROJECT=04-uart             # run, then open build/uart_tb.ghw
make wave PROJECT=04-uart GTKW=x.gtkw # optional user-saved layout
make lint                             # analyze all with -Wall
make clean                            # remove build/ and .logs/
make new NAME=15-watchdog TITLE="Watchdog timer"
make fmt PROJECT=04-uart              # ghdl fmt --std=08 (rewrites files)
```

- `make test`: run projects serially, capture `.logs/<project>.log`, print a
  compact PASS/FAIL summary, exit nonzero if any project fails. Do not depend
  on `make -j`.
- `make wave`: require `PROJECT`, run its test first, then launch GTKWave in the
  background. Tests must stay headless; GTKWave is not needed for `test/lint`.
- `make check` must not require a display.

## Build contract

Per-project Makefile is deliberately small:

```make
TOP := uart_tb
RTL := uart_pkg.vhd uart_tx.vhd uart_rx.vhd
TB  := uart_tb.vhd
include ../mk/project.mk
```

`mk/project.mk` uses per-project `build/` and these flags:

```text
analyze: --std=08 --workdir=build -Wall
run:     --assert-level=failure --wave=build/$(TOP).ghw
```

Analysis order is explicit and must stay explicit; GHDL has no dependency
ordering: `lib/util_pkg.vhd` → `lib/tb_pkg.vhd` → `*_pkg.vhd` → leaf RTL →
top → `*_model.vhd` → TB.

GHDL is the mcode backend: `-e` is still required, but there are no object
files. Do not run two analyses against the same work directory concurrently.
Each project has its own `build/`, so aggregate tests are safe.

## VHDL conventions

- VHDL-2008. Use `ieee.numeric_std` only; never `std_logic_arith`,
  `std_logic_unsigned`, or vendor libraries.
- Ports use `_i`/`_o` suffixes (`clk_i`, `rst_i`, `data_i`, `valid_o`).
  Active-high synchronous reset; one clock per module.
- Tutorial-heavy comments: explain *why* (timing, bit growth, FSM transitions,
  protocol edges). Do not narrate obvious assignments; full theory belongs in
  the README.
- Default all outputs, use complete `case` statements, avoid latches, validate
  generics with elaboration-time assertions.
- Keep RTL synthesizable. Bus/sensor/plant models are simulation-only and must
  be named `*_model.vhd` or live in the TB.

## Testbench rules

- One self-checking TB per project; deterministic (fixed random seed).
- Use `lib/tb_pkg.vhd` for checks and `wait_cycles`; no external frameworks.
- Individual checks report `severity error` and accumulate. Run with
  `--assert-level=failure` so they do not abort early; the final summary raises
  `severity failure` to produce a nonzero exit.
- Every TB has a timeout watchdog, prints `TEST PASSED`, and calls
  `std.env.finish`. Cover reset, nominal, boundaries, and error paths.
- Override generics in TBs for fast simulation (small clock/baud values);
  do not simulate 50 MHz unless timing requires it.
- I2C models: drive `'Z'` for release and use `'H'` pullups in the TB. No
  internal pullups.

## Project plan (14)

| Folder | Build / focus |
|---|---|
| `01-combinational-basics` | `mux4`, `prio_enc8`, hex→7-seg decoder |
| `02-counter-timer` | loadable up/down counter, retriggerable one-shot |
| `03-input-conditioning` | 2-FF synchronizer, debouncer, edge detect, pulse stretch |
| `04-uart` | 8N1 TX/RX, 16× oversampling, framing/break errors |
| `05-sync-fifo` | parameterized FIFO, count/almost flags, backpressure |
| `06-spi-master` | CPOL/CPHA modes 0–3, multi-slave CS |
| `07-i2c-master` | master + EEPROM model, open-drain bus |
| `08-crc` | generic CRC-8/16/32 streaming, standard vectors |
| `09-pwm-deadtime` | complementary PWM, dead time, fault input |
| `10-quadrature-decoder` | x1/x2/x4, position/direction/index |
| `11-fir-filter` | fixed-point symmetric FIR, `valid`/`ready` streaming |
| `12-pid-controller` | Q-format PID, saturation, anti-windup |
| `13-axi-lite-regfile` | AXI4-Lite slave, byte enables, master BFM |
| `14-uart-sensor-node` | capstone: UART + FIFO + CRC framed protocol |

Project 14 reuses sources from `../04-uart`, `../05-sync-fifo`, and
`../08-crc` via explicit Makefile paths. Do not copy that RTL.

## README contract

Top-level README: prerequisites, quick start, layout, conventions, learning
path, build-system reference, GTKWave workflow, roadmap.

Every project README: overview and industrial relevance; what you learn; ASCII
block diagram; generic/port tables; design/timing notes; file map; simulation
commands; **signals to inspect in GTKWave**; TB strategy; pitfalls/exercises.

Do not add curated `.gtkw` files. READMEs list hierarchical signal paths; users
may save their own layout and pass it with `GTKW=`.

## Acceptance

- `make clean && make check && make lint && make test` succeeds; all 14 print
  `TEST PASSED`.
- `make wave PROJECT=<p>` produces `build/<top>.ghw` and opens GTKWave.
- `make new` produces a skeleton that compiles and passes immediately.
- README tables and GTKWave signal lists match the actual VHDL.
- .gitignore covers `build/`, `.logs/`, `*.ghw`, `*.vcd`, `*.fst`.

## Implementation order

1. Foundation: Makefiles, `mk/project.mk`, `lib/`, scaffold script, projects 01–02.
2. Core: 03 input conditioning, 04 UART, 05 FIFO.
3. Interfaces: 06 SPI, 07 I2C, 08 CRC.
4. Control/DSP: 09 PWM, 10 quadrature, 11 FIR, 12 PID.
5. Integration: 13 AXI4-Lite, 14 sensor node.
6. Clean sweep: lint, full test, waveform check, README consistency.
