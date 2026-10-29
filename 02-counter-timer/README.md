# 02-counter-timer — loadable counter and retriggerable one-shot

## Overview

Two building blocks that turn a clock into time:

- `counter` — a loadable, enabled, up/down counter with a terminal flag.
- `oneshot` — a retriggerable monostable that stretches a trigger edge into a
  pulse of a requested width.

Counters and one-shots are the backbone of timers, watchdogs, PWM generators,
and state machines. The important lesson here is priority: when reset, load,
and enable are asserted together, exactly one behavior must win, and that
choice must be documented and tested.

Industrial relevance: motor timers, debounce windows, watchdog timeouts,
delays in sequencers, and pulse stretching for valve/solenoid drivers.

## What you will learn

- How to define and test a priority order for a counter's control inputs.
- Why unsigned arithmetic wraps naturally and when that is desirable.
- The difference between a level flag (`terminal_o`) and a pulse.
- How to convert a time in nanoseconds into clock cycles with ceiling division.
- How to build a retriggerable one-shot with edge detection.
- How to measure pulse width in a testbench without racing the DUT.

## Block diagram

```text
 counter
                 +------------+
 en_i ---------->|            |
 up_i ---------->|  load /    |---- count_o[WIDTH-1:0]
 load_i -------->|  up/down   |---- terminal_o
 load_val_i ---->|  register  |
 clk_i, rst_i -->|            |
                 +------------+

 oneshot
                 +------------+
 trigger_i ----->| edge det.  |
                 |            |---- pulse_o
                 | remaining  |
 clk_i, rst_i -->| counter    |
                 +------------+
```

## Generics

### `counter`

| Name | Type | Default | Meaning |
|---|---|---|---|
| `WIDTH` | `positive` | `8` | Counter width in bits |

### `oneshot`

| Name | Type | Default | Meaning |
|---|---|---|---|
| `CLK_PERIOD_NS` | `positive` | `10` | Clock period in nanoseconds |
| `PULSE_NS` | `positive` | `100` | Requested pulse width in nanoseconds |

`oneshot` derives `PULSE_CYCLES = ceil(PULSE_NS / CLK_PERIOD_NS)`, with a
minimum of one cycle. The counter is sized with `clog2(PULSE_CYCLES + 1)`.

## Ports

### `counter`

| Name | Direction | Width | Meaning |
|---|---|---|---|
| `clk_i` | in | 1 | Clock |
| `rst_i` | in | 1 | Synchronous active-high reset |
| `en_i` | in | 1 | Count enable |
| `up_i` | in | 1 | `1` = count up, `0` = count down |
| `load_i` | in | 1 | Load `load_val_i` on the next edge |
| `load_val_i` | in | `WIDTH` | Load value |
| `count_o` | out | `WIDTH` | Current count |
| `terminal_o` | out | 1 | High when at the end being counted toward |

### `oneshot`

| Name | Direction | Width | Meaning |
|---|---|---|---|
| `clk_i` | in | 1 | Clock |
| `rst_i` | in | 1 | Synchronous active-high reset |
| `trigger_i` | in | 1 | Rising edge starts/restarts the pulse |
| `pulse_o` | out | 1 | High while the pulse is active |

## Design notes

### Counter priority

The control priority is **reset > load > enable > hold**:

```vhdl
if rst_i = '1' then
  count <= (others => '0');
elsif load_i = '1' then
  count <= unsigned(load_val_i);
elsif en_i = '1' then
  -- up/down
end if;
```

Load must beat enable. If both are asserted and enable won, a loader and a
free-running counter could disagree for one cycle, which is exactly the kind of
off-by-one that breaks a divider or a PWM period.

`count` is an `unsigned`, so `count + 1` at all-ones wraps to zero and
`count - 1` at zero wraps to all-ones. That modulo behavior is intentional and
is what makes the block reusable at any width.

### terminal_o is a level

`terminal_o` is combinational and means "the counter is currently at the end it
is counting toward":

```text
up_i = '1' and count = all ones
up_i = '0' and count = all zeros
```

It is not a registered carry-out and not a one-cycle pulse. A consumer that
needs "the next enabled edge will wrap" can use it directly; a consumer that
needs an event should register it or compare the count itself.

### One-shot

`trigger_i` is edge-detected against a registered copy. A rising edge reloads
`remaining` with `PULSE_CYCLES`; every other cycle decrements it until zero.
Because the reload happens on an edge, holding `trigger_i` high does not
stretch the pulse forever. A second rising edge while the pulse is active
reloads the full width, which makes the block retriggerable.

`pulse_o` is high whenever `remaining /= 0`, so the pulse begins on the clock
edge that samples the trigger and lasts exactly `PULSE_CYCLES` cycles.

The input is assumed to be synchronized to `clk_i`. For a real button or
asynchronous pin, put the synchronizer from project 03 in front of it.

## Files

| File | Purpose |
|---|---|
| `counter.vhd` | Loadable up/down counter with terminal flag |
| `oneshot.vhd` | Retriggerable monostable / pulse stretcher |
| `counter_timer_tb.vhd` | Priority, wrap, terminal, and pulse-width tests |

## Simulate

```sh
make test
make wave
```

From the repository root:

```sh
make test PROJECT=02-counter-timer
make wave PROJECT=02-counter-timer
```

`make wave` opens `build/counter_timer_tb.ghw`.

## Signals to inspect in GTKWave

Counter:

- `counter_timer_tb.clk`
- `counter_timer_tb.rst`
- `counter_timer_tb.en`
- `counter_timer_tb.up`
- `counter_timer_tb.load`
- `counter_timer_tb.load_val`
- `counter_timer_tb.count`
- `counter_timer_tb.term`
- `counter_timer_tb.dut_counter.count`

One-shot:

- `counter_timer_tb.trigger`
- `counter_timer_tb.pulse`
- `counter_timer_tb.dut_oneshot.trigger_d`
- `counter_timer_tb.dut_oneshot.remaining`

## Testbench strategy

The TB uses a 10 ns clock and asks for a 10-cycle pulse (`PULSE_NS = 100`), so
the expected width is easy to see on the waveform.

| Test | What it proves |
|---|---|
| TC1 | Reset clears the count; load wins over enable |
| TC2 | Five up-counts and three down-counts land on the expected values |
| TC3 | Wrap at `FF`/`00` and `terminal_o` behavior at both ends |
| TC4 | One-shot width equals the requested number of cycles |
| TC5 | A second trigger inside the pulse restarts the full width |

Total: **14 checks**. Pulse width is counted by sampling on rising clock edges
with a 1 ns settle delay, which avoids the race between the DUT's registered
update and the TB's check.

## Pitfalls

- `terminal_o` changes immediately after a load or wrap; do not treat it as a
  registered flag that is stable for a whole cycle.
- If `PULSE_NS` is not a multiple of `CLK_PERIOD_NS`, ceiling division makes the
  pulse slightly longer, never shorter.
- A one-shot cannot guarantee a minimum width shorter than one clock. The
  elaboration assertion rejects a zero-cycle request.
- Triggering from an unsynchronized pin can produce a metastable edge detector
  and a jittery pulse. Synchronize first.
- Do not use a one-shot as a safety delay. Safety functions belong in hardware,
  not in FPGA logic.

## Exercises

1. Add a `sync_clear_i` that forces the count to zero without a full reset.
2. Add a registered `carry_o` that pulses for one cycle on wrap.
3. Make `counter` saturate at the ends instead of wrapping, selected by a
   generic.
4. Add a `retrigger_i` mode select: retriggerable vs. non-retriggerable.
5. Replace the one-shot's counter with a down-counter loaded from a register so
   the width can change at runtime.
6. Add a test that asserts a trigger during reset and checks that no pulse is
   produced.
