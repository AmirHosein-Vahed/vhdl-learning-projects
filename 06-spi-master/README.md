# 06-spi-master — 8-bit SPI master with all four modes

## Overview

SPI (Serial Peripheral Interface) is a synchronous, full-duplex, four-wire bus:
`SCLK`, `MOSI`, `MISO`, and one chip select per slave. It is the default link
for sensors, ADCs, flash memories, SD cards, and display controllers because it
is simple, fast, and needs no addressing or arbitration.

This project implements a single master that:

- transfers one byte at a time, MSB first,
- supports all four SPI modes through a 2-bit `mode_i` input,
- selects one of `NUM_SLAVES` devices with a one-hot input,
- derives `SCLK` from the system clock with a programmable divider,
- reports `busy_o` and a one-cycle `done_o` pulse,
- keeps chip select active for one extra clock after the last `SCLK` edge.

Industrial relevance: talking to an SPI temperature sensor or ADC, loading a
DAC, reading/writing configuration flash, and bringing up a peripheral before a
vendor driver exists.

## What you will learn

- What CPOL and CPHA actually change, and why there are four modes.
- The difference between a *leading* and a *trailing* clock edge.
- How to sample MISO and launch MOSI on opposite edges.
- How a clock divider creates a slow serial clock from a fast system clock.
- How one-hot chip select maps to active-low `CS_N` lines.
- Why chip select must stay asserted after the last bit.
- How to write a slave model that is clocked by `SCLK`, not by the system clock.

## SPI modes

`mode_i` is `(CPOL, CPHA)`: `mode_i(1)` is CPOL, `mode_i(0)` is CPHA.

| Mode | `mode_i` | CPOL | CPHA | Idle SCLK | Sample edge | Shift edge |
|---|---|---|---|---|---|---|
| 0 | `"00"` | 0 | 0 | low | rising (leading) | falling (trailing) |
| 1 | `"01"` | 0 | 1 | low | falling (trailing) | rising (leading) |
| 2 | `"10"` | 1 | 0 | high | falling (leading) | rising (trailing) |
| 3 | `"11"` | 1 | 1 | high | rising (trailing) | falling (leading) |

- **CPOL** sets the idle level of `SCLK`. CPOL=0 idles low, CPOL=1 idles high.
- **CPHA** sets *which* edge samples data. CPHA=0 samples on the leading edge
  (the first edge of the clock period); CPHA=1 samples on the trailing edge.
- Data always changes on the edge that does not sample, so the receiver sees a
  stable bit at every sampling edge.

The master and the slave must agree on the mode. A mode mismatch usually shows
up as a received byte shifted by one bit or with the MSB/LSB corrupted.

## Block diagram

```text
                      +--------------------------------------+
  start_i ----------->|                                      |
  mode_i[1:0] ------->|   control FSM                        |
  cs_sel_i[N-1:0] --->|   IDLE -> TRANSFER -> HOLD           |
  data_i[7:0] ------->|                                      |
                      |   div_cnt  ---> SCLK toggle          |----> sclk_o
                      |   mosi_sr  ---> MOSI                |----> mosi_o
                      |   miso_sr  <--- MISO                |<---- miso_i
                      |   phase (0..15)                      |
                      +--------------------------------------+
                            |            |            |
                            v            v            v
                         cs_n_o       busy_o       done_o
                       (one-hot,     (high during  (one-cycle
                        active low)   transfer)     pulse)
```

## Generics

| Name | Type | Default | Meaning |
|---|---|---|---|
| `NUM_SLAVES` | `positive` | `2` | Number of chip-select lines; must be ≥ 1 |
| `CLK_DIV` | `positive` | `4` | `clk_i` cycles per `SCLK` half-period; must be ≥ 1 |

```text
SCLK frequency = clk_i frequency / (2 * CLK_DIV)
```

Both generics are checked by elaboration-time assertions.

## Ports

| Name | Direction | Width | Meaning |
|---|---|---|---|
| `clk_i` | in | 1 | System clock |
| `rst_i` | in | 1 | Synchronous active-high reset |
| `start_i` | in | 1 | Start a transfer; ignored unless idle |
| `mode_i` | in | 2 | `(1)` = CPOL, `(0)` = CPHA |
| `cs_sel_i` | in | `NUM_SLAVES` | One-hot slave select, active high |
| `data_i` | in | 8 | Byte to transmit (MSB first) |
| `data_o` | out | 8 | Byte received from MISO |
| `sclk_o` | out | 1 | Serial clock |
| `mosi_o` | out | 1 | Master-out / slave-in |
| `miso_i` | in | 1 | Master-in / slave-out |
| `cs_n_o` | out | `NUM_SLAVES` | Active-low chip selects |
| `busy_o` | out | 1 | High from start until the transfer completes |
| `done_o` | out | 1 | One-cycle pulse when `data_o` is valid |

`cs_n_o` is simply `not cs_sel_i` while a transfer is running and all ones
otherwise. Selecting no slave still runs the transfer, but nothing drives MISO.

## Design notes

### FSM and timing

```text
            start_i = 1
   IDLE -------------------> TRANSFER --------------------> HOLD
    ^                          |  16 half-periods            |
    |                          |  (8 SCLK periods)           | 1 clk
    +--------------------------+-----------------------------+
                            done_o pulses here
```

`phase` counts 0 to 15. Each phase lasts `CLK_DIV` system clocks, and `SCLK`
toggles at the end of every phase, so one transfer is 16 half-periods.

For `CLK_DIV = 2` and a 10 ns system clock:

```text
start_i  __/‾‾\________________________________________________
busy_o   ____/‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾\_________
cs_n_o   ‾‾‾‾\_________________________________________/‾‾‾‾‾‾‾
sclk_o   ________/‾‾\__/‾‾\__/‾‾\__/‾‾\__ ... __/‾‾\____________
mosi_o   ====X=======X=======X=======X== ... ==X===============
                       ^ sample MISO on each leading edge (mode 0)
done_o   ______________________________________________/‾‾\______
```

Two details matter:

1. `start_i` is sampled on the rising edge and only in `IDLE`, so a start pulse
   that arrives during a transfer is ignored. `busy_o` is the handshake that
   tells the producer when it is safe to start again.
2. `done_o` is asserted in `HOLD` and cleared on the next edge, so it is exactly
   one `clk_i` cycle wide. `data_o` is loaded on the same edge, so a consumer
   that samples on `done_o` sees valid data.

### Data path per mode

CPHA=0 (`mode_i(0) = '0'`):

- On `start_i`, the master puts `data_i(7)` on MOSI immediately, before the
  first clock edge. A CPHA=0 slave expects the first bit to be valid while
  `SCLK` is still idle.
- Phase 0 is the leading edge: sample MISO, toggle SCLK to the active level.
- Phase 1 is the trailing edge: shift the next MOSI bit out, toggle SCLK back.
- The last bit is sampled at phase 14, so the final trailing edge (phase 15)
  only restores the idle clock level.

CPHA=1 (`mode_i(0) = '1'`):

- On `start_i`, MOSI is driven low and the whole byte stays in the shift
  register. The slave must not expect data before the first edge.
- Phase 0 is the leading edge: shift out MOSI bit 7, toggle SCLK.
- Phase 1 is the trailing edge: sample MISO, toggle SCLK back.
- The last bit is sampled at phase 15, which is why the final MISO bit is
  included explicitly in the `data_r` assignment.

In both cases `miso_sr` shifts left and appends `miso_i`, so after eight samples
it holds the received byte with the first bit in the MSB position.

### The HOLD state

A slave that is clocked by `SCLK` updates its internal receive register on the
sampling edge. If `CS_N` is released on that same system-clock edge, a real
device may see the chip select rise before it has finished capturing the last
bit, especially when there is any clock-to-output or board delay.

`HOLD` therefore keeps `CS_N` asserted for one extra `clk_i` cycle after
`SCLK` has returned to idle. In simulation this is what lets both slave models
report the correct byte in modes 1 and 3; without it, the last bit is lost and
`rx_data` stays at `0x00` for the CPHA=1 cases.

The cost is one clock of latency per byte. A production master may instead
sample the last bit one half-period earlier, or rely on the slave's own CS
filtering; keeping the explicit `HOLD` state makes the timing visible and easy
to reason about.

### Clock divider

`div_cnt` counts `0 .. CLK_DIV-1` inside each phase. A phase ends when
`div_cnt = CLK_DIV-1`, so each half-period is exactly `CLK_DIV` clocks. At
`CLK_DIV = 1` the divider is bypassed and `SCLK` toggles every clock.

`SCLK` is generated by a register, not by combinational gating of `clk_i`.
That avoids glitches and keeps the design synthesizable; the serial clock is
just another synchronous output.

## Files

| File | Purpose |
|---|---|
| `spi_master.vhd` | Synthesizable SPI master |
| `spi_slave_model.vhd` | Simulation-only SCLK-clocked slave, drives `'Z'` when deselected |
| `spi_tb.vhd` | Mode sweep, two slaves, spurious-start test |
| `Makefile` | `TOP`, `RTL`, `TB`, includes `../mk/project.mk` |

## Simulate

```sh
make test
make wave
```

From the repository root:

```sh
make test PROJECT=06-spi-master
make wave PROJECT=06-spi-master
```

`make wave` runs the test first and opens `build/spi_tb.ghw`.

## Signals to inspect in GTKWave

Top-level stimulus and results:

- `spi_tb.clk`
- `spi_tb.rst`
- `spi_tb.start`
- `spi_tb.mode` (watch it change between test cases)
- `spi_tb.cs_sel`
- `spi_tb.data_in`
- `spi_tb.data_out`
- `spi_tb.sclk`
- `spi_tb.mosi`
- `spi_tb.miso_line`
- `spi_tb.cs_n`
- `spi_tb.busy`
- `spi_tb.done`
- `spi_tb.slave0_rx`
- `spi_tb.slave1_rx`

Master internals:

- `spi_tb.dut.state` (`IDLE`, `TRANSFER`, `HOLD`)
- `spi_tb.dut.phase` (0–15, one count per half-period)
- `spi_tb.dut.div_cnt`
- `spi_tb.dut.sclk_r`
- `spi_tb.dut.mosi_r`
- `spi_tb.dut.mosi_sr`
- `spi_tb.dut.miso_sr`
- `spi_tb.dut.cs_n_r`
- `spi_tb.dut.data_r`

Slave model internals:

- `spi_tb.slave0.bit_cnt`
- `spi_tb.slave0.rx_sr`
- `spi_tb.slave0.tx_sr`
- `spi_tb.slave0.miso_r`

A good first view is `mode`, `cs_n`, `sclk`, `mosi`, `miso_line`, and `phase`
together. Step through mode 0 and mode 2 and notice that only the idle level
changes; step through mode 1 and 3 and notice that MOSI moves on the opposite
edge from the MISO sample.

## Testbench strategy

Two `spi_slave_model` instances share the bus. Each has a different transmit
byte (`0xA5` and `0x3C`) so the test can prove that the selected chip select
routes the correct device. The master sends a different byte in each mode.

| Test | What it proves |
|---|---|
| TC1 | Reset clears `busy`, `done`, chip selects, and `data_o`; SCLK idles low |
| TC2 | Mode 0, slave 0: full-duplex byte exchange, other slave untouched |
| TC3 | Mode 1, slave 1: CPHA=1 sampling and the HOLD state |
| TC4 | Mode 2, slave 0: CPOL=1 idle-high clock |
| TC5 | Mode 3, slave 1: CPOL=1 and CPHA=1 together |
| TC6 | `start_i` during a transfer is ignored, including a different slave and byte |

Total: **50 checks**. The TB muxes `miso0`/`miso1` onto `miso_line` based on
`cs_n`, which is equivalent to a resolved bus where deselected slaves drive
`'Z'`. It also counts `done` pulses to verify there is exactly one per transfer.

## Pitfalls

- `start_i` is ignored unless the FSM is idle. Poll `busy_o` or wait for
  `done_o`; do not assume every start pulse launches a transfer.
- `data_o` is only valid when `done_o` pulses. Reading it earlier returns the
  previous byte.
- `mode_i` is sampled throughout the transfer. Changing it mid-byte corrupts the
  clock edge sequence; keep it stable until `done_o`.
- `cs_sel_i` is one-hot and is not validated. All-zero still runs a transfer
  (with MISO floating or pulled to a default), and multiple ones assert several
  chip selects at once.
- CPHA=0 requires the first MOSI bit before the first clock edge. A slave that
  waits for an edge to latch bit 7 will lose it.
- Releasing `CS_N` on the last sampling edge is a classic bring-up bug. The
  `HOLD` state exists to make that margin explicit.
- `CLK_DIV = 1` gives the fastest possible `SCLK` (half the system clock), but
  real slaves have a maximum frequency; check the datasheet.
- The slave model is clocked by `SCLK` edges and is not synthesizable. Do not
  copy it into RTL.

## Exercises

1. Add a `cpol_o`/`cpha_o` status output, or latch `mode_i` at start so a
   mid-transfer change cannot corrupt the frame.
2. Add a `start_i` edge detector so a level held high only launches one
   transfer.
3. Support multi-byte transfers with a `length_i` input and a contiguous
   `CS_N` for the whole burst.
4. Add a programmable `CS_N` setup/hold time of N clocks around the transfer.
5. Connect the two slave models directly to one resolved `miso_line` signal and
   remove the TB mux; confirm that `'Z'` resolution works the same way.
6. Add a loopback test that ties MOSI to MISO and checks that the master
   receives exactly what it sent in every mode.
7. Add a slave that returns a status byte and verify a two-byte command/response
   sequence.
8. Measure the achievable throughput and compare it with the theoretical
   `f_clk / (2 * CLK_DIV * 8)` bytes per second.
