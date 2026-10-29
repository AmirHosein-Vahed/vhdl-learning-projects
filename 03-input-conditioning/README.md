# 03-input-conditioning — synchronizer, debouncer, edge detector

## Overview

This project is the chain that sits between a physical switch or button and the
rest of the FPGA logic:

1. `sync_ff` — a two-flop synchronizer for the asynchronous pin.
2. `debounce` — a counter-based filter that ignores contact bounce.
3. `edge_detect` — one-cycle rise/fall pulses for "do this once" actions.
4. `input_conditioning` — the three blocks wired together in the correct order.

Every real board has at least one asynchronous input, and feeding it straight
into a state machine is a classic source of metastability and double-counting.
This project makes the fix explicit and testable.

Industrial relevance: operator pushbuttons, limit switches, door sensors,
encoder index pulses, and any signal arriving from outside the FPGA clock
domain.

## What you will learn

- Why a single flop is not enough to cross a clock domain.
- How a debounce counter turns "stable for N cycles" into clean logic.
- Why edge detection belongs *after* synchronization and debouncing.
- How to measure latency through a pipeline of blocks.
- Why a debouncer is not a safety function.
- How to count one-cycle events reliably in a testbench.

## Block diagram

```text
 raw_i      +--------+     +----------+     +-------------+
 (async) --->| sync_ff|---->| debounce |---->| edge_detect |----> rise_o
             | 2 FF   |     | counter  |     | 1-cycle     |----> fall_o
             +--------+     +----------+     +-------------+
                                  |
                                  +------------------------------> clean_o
```

`input_conditioning` instantiates exactly this chain.

## Generics

### `sync_ff`

| Name | Type | Default | Meaning |
|---|---|---|---|
| `STAGES` | `positive` | `2` | Number of synchronizer flops; must be ≥ 2 |

### `debounce`

| Name | Type | Default | Meaning |
|---|---|---|---|
| `CLK_PERIOD_NS` | `positive` | `10` | Clock period in nanoseconds |
| `DEBOUNCE_NS` | `positive` | `100` | Required stable time before the output follows |

### `input_conditioning`

| Name | Type | Default | Meaning |
|---|---|---|---|
| `CLK_PERIOD_NS` | `positive` | `10` | Passed to `debounce` |
| `DEBOUNCE_NS` | `positive` | `100` | Passed to `debounce` |

`debounce` derives `DEBOUNCE_CYCLES = ceil(DEBOUNCE_NS / CLK_PERIOD_NS)` and
sizes its counter with `clog2(DEBOUNCE_CYCLES + 1)`.

## Ports

### `sync_ff`

| Name | Direction | Width | Meaning |
|---|---|---|---|
| `clk_i` | in | 1 | Destination clock |
| `rst_i` | in | 1 | Synchronous active-high reset |
| `async_i` | in | 1 | Asynchronous input |
| `sync_o` | out | 1 | Synchronized output |

### `debounce`

| Name | Direction | Width | Meaning |
|---|---|---|---|
| `clk_i` | in | 1 | Clock |
| `rst_i` | in | 1 | Synchronous active-high reset |
| `raw_i` | in | 1 | Input to debounce (normally synchronized) |
| `debounced_o` | out | 1 | Stable filtered output |

### `edge_detect`

| Name | Direction | Width | Meaning |
|---|---|---|---|
| `clk_i` | in | 1 | Clock |
| `rst_i` | in | 1 | Synchronous active-high reset |
| `level_i` | in | 1 | Level to watch |
| `rise_o` | out | 1 | One-cycle pulse on a rising edge |
| `fall_o` | out | 1 | One-cycle pulse on a falling edge |

### `input_conditioning`

| Name | Direction | Width | Meaning |
|---|---|---|---|
| `clk_i` | in | 1 | Clock |
| `rst_i` | in | 1 | Synchronous active-high reset |
| `raw_i` | in | 1 | Raw asynchronous input |
| `clean_o` | out | 1 | Debounced level |
| `rise_o` | out | 1 | One-cycle pulse on a clean rising edge |
| `fall_o` | out | 1 | One-cycle pulse on a clean falling edge |

## Design notes

### Why two flops

The first flop samples an asynchronous signal and may go metastable — its
output can hover between `0` and `1` for a short time. The second flop gives
that metastability a full clock period to resolve before downstream logic sees
it. One flop removes neither the metastability nor the race.

Two flops are the usual minimum for a single-bit control signal. This structure
is **not** safe for multi-bit buses: different bits can resolve in different
cycles. Use a handshake or an asynchronous FIFO for buses (project 05).

### Debounce algorithm

The output only follows the input after the input has been stable for
`DEBOUNCE_CYCLES`:

```text
if raw_i = stable then
  count <= 0                 -- nothing to do
elsif count = CNT_MAX then
  stable <= raw_i            -- stable long enough
  count  <= 0
else
  count <= count + 1
end if;
```

Any change restarts the counter, so contact bounce and short glitches never
reach the output. The filter adds up to `DEBOUNCE_CYCLES` of latency on each
transition — that is the price of rejecting bounce.

### Edge detection

`edge_detect` registers `level_i` and compares:

```text
rise_o = level_i and not level_d
fall_o = not level_i and level_d
```

Both outputs are one clock wide. Because they are combinational functions of a
registered signal, they are glitch-free as long as `level_i` is synchronous.

### Order matters

The pipeline order is synchronize → debounce → edge detect. Debouncing before
synchronizing would feed a metastable signal into the counter; edge-detecting
before debouncing would emit an event for every bounce. `input_conditioning`
enforces the correct order so users cannot accidentally wire it wrong.

### Not a safety function

A debouncer cleans up an operator input; it does not make that input safe. An
emergency stop must remove power through hard-wired safety hardware, not through
FPGA logic that can be reconfigured or can fail.

## Files

| File | Purpose |
|---|---|
| `sync_ff.vhd` | Parameterizable multi-flop synchronizer |
| `debounce.vhd` | Counter-based debouncer |
| `edge_detect.vhd` | One-cycle rise/fall pulse generator |
| `input_conditioning.vhd` | Synchronizer + debouncer + edge detector |
| `input_conditioning_tb.vhd` | Latency, bounce, glitch, and event-count tests |

## Simulate

```sh
make test
make wave
```

From the repository root:

```sh
make test PROJECT=03-input-conditioning
make wave PROJECT=03-input-conditioning
```

`make wave` opens `build/input_conditioning_tb.ghw`. The TB uses a 10 ns clock
and a 100 ns debounce window, so a press takes about ten cycles to appear.

## Signals to inspect in GTKWave

Top-level stimulus and results:

- `input_conditioning_tb.clk`
- `input_conditioning_tb.rst`
- `input_conditioning_tb.raw`
- `input_conditioning_tb.clean`
- `input_conditioning_tb.rise`
- `input_conditioning_tb.fall`
- `input_conditioning_tb.rise_count`
- `input_conditioning_tb.fall_count`

Synchronizer:

- `input_conditioning_tb.async_in`
- `input_conditioning_tb.sync_out`
- `input_conditioning_tb.dut_sync.chain`

Inside `input_conditioning`:

- `input_conditioning_tb.dut.synchronized`
- `input_conditioning_tb.dut.debounced`
- `input_conditioning_tb.dut.u_debounce.count`
- `input_conditioning_tb.dut.u_debounce.stable`
- `input_conditioning_tb.dut.u_edge.level_d`

## Testbench strategy

| Test | What it proves |
|---|---|
| TC1 | The synchronizer output appears after two clocks, not one |
| TC2 | Bounce is filtered and exactly one rise event is produced |
| TC3 | A glitch shorter than the debounce window creates no event |
| TC4 | Release is debounced and produces exactly one fall event |
| TC5 | Rise/fall pulses are not stretched |

Total: **14 checks**. The TB counts rise/fall events on the pulse edges rather
than sampling them at a clock edge; a one-cycle combinational pulse can be
missed by a clocked monitor due to delta-cycle ordering.

## Pitfalls

- A synchronizer adds latency. A two-flop stage delays the signal by two clocks;
  account for that in any timing budget.
- Do not synchronize a multi-bit bus with `sync_ff` per bit. The bits can
  resolve on different cycles and produce a transient invalid value.
- `DEBOUNCE_NS` must be longer than the worst-case bounce, but shorter than the
  shortest legitimate press you need to detect.
- The debouncer's counter restarts on every change. A signal that toggles faster
  than the debounce window will never pass.
- `rise_o` and `fall_o` are one clock wide. If a consumer can be busy, latch the
  event or add a small event FIFO.
- A debouncer is not a substitute for a safety-rated input circuit.

## Exercises

1. Parameterize the synchronizer depth and show the latency difference for
   `STAGES = 2` and `STAGES = 3`.
2. Replace the debounce counter with a saturating up/down counter and compare
   behavior on a noisy input.
3. Add a `pressed_o` output that stays high while the button is held.
4. Add a generic `ACTIVE_LOW` to invert the raw input for active-low buttons.
5. Measure the worst-case latency from `raw_i` to `rise_o` and add a check for
   it.
6. Feed two independent buttons through two `input_conditioning` instances and
   test a simultaneous press/release.
