# 01-combinational-basics — mux, priority encoder, 7-segment decoder

## Overview

Three small combinational blocks that appear in almost every FPGA design:

- `mux4` — a parameterized 4:1 multiplexer.
- `prio_enc8` — an 8:3 priority encoder where the highest asserted bit wins.
- `seven_seg` — a hexadecimal to active-low 7-segment decoder.

Individually they are trivial, but together they cover the three ways
combinational logic is normally written in VHDL: a selected signal assignment,
a priority `if/elsif` chain, and a lookup table expressed as a `case`
statement. Getting these patterns right early avoids latches and unintended
priority in later, larger designs.

Industrial relevance: multiplexers select datapath sources, priority encoders
turn interrupt/request vectors into an index, and 7-segment decoders drive
front-panel displays on test equipment and controllers.

## What you will learn

- How `with ... select` maps a select value to one of several buses.
- Why a priority encoder needs a `valid_o` flag to distinguish "input 0" from
  "no input".
- Why a `case` table is better than arithmetic for segment decoding.
- How to keep combinational logic total (defaults + `when others`) so synthesis
  cannot infer a latch.
- How to write an exhaustive, clock-free self-checking testbench.

## Block diagram

```text
 mux4
            +---------+
 d0_i ------|         |
 d1_i ------|  4:1    |
 d2_i ------|  mux    |---- y_o
 d3_i ------|         |
 sel_i[1:0]-| sel     |
            +---------+

 prio_enc8
            +---------+
 din_i[7:0]-| highest |
            | bit     |---- index_o[2:0]
            | wins    |---- valid_o
            +---------+

 seven_seg
            +---------+
 hex_i[3:0]-| 16-entry|---- seg_o[6:0]  (g f e d c b a, active low)
            | table   |
            +---------+
```

## Generics

### `mux4`

| Name | Type | Default | Meaning |
|---|---|---|---|
| `WIDTH` | `positive` | `8` | Data width of each input and the output |

## Ports

### `mux4`

| Name | Direction | Width | Meaning |
|---|---|---|---|
| `sel_i` | in | 2 | Select: `00`→`d0_i`, `01`→`d1_i`, `10`→`d2_i`, `11`→`d3_i` |
| `d0_i` | in | `WIDTH` | Input 0 |
| `d1_i` | in | `WIDTH` | Input 1 |
| `d2_i` | in | `WIDTH` | Input 2 |
| `d3_i` | in | `WIDTH` | Input 3 |
| `y_o` | out | `WIDTH` | Selected input |

### `prio_enc8`

| Name | Direction | Width | Meaning |
|---|---|---|---|
| `din_i` | in | 8 | Request vector |
| `valid_o` | out | 1 | High when any bit of `din_i` is set |
| `index_o` | out | 3 | Index of the highest asserted bit |

### `seven_seg`

| Name | Direction | Width | Meaning |
|---|---|---|---|
| `hex_i` | in | 4 | Value `0`–`F` |
| `seg_o` | out | 7 | Segment pattern, bit order `g f e d c b a`, active low |

## Design notes

### mux4

A selected signal assignment is the shortest total description:

```vhdl
with sel_i select
  y_o <= d0_i when "00",
         d1_i when "01",
         d2_i when "10",
         d3_i when others;
```

`when others` is required even though `sel_i` has exactly four encodings,
because `std_logic` has nine values. Without it the assignment would be
incomplete, and simulation could leave `y_o` unchanged (a latch-like effect).
Synthesis collapses the whole thing into a small LUT tree.

### prio_enc8

The `if/elsif` chain is written from bit 7 down to bit 0. The first true branch
wins, so no explicit masking is needed. `valid_o` separates two cases that
share the same index:

| `din_i` | `valid_o` | `index_o` | Meaning |
|---|---|---|---|
| `0000_0000` | 0 | `000` | No request |
| `0000_0001` | 1 | `000` | Request 0 |
| `1000_0001` | 1 | `111` | Requests 0 and 7; 7 wins |

Defaults are assigned before the chain, so every output is driven on every
path and no latch is inferred.

### seven_seg

The output bit order is `g f e d c b a` (bit 6 = g, bit 0 = a). A `'0` turns a
segment on, matching common-anode wiring. Keeping the patterns in a `case`
statement makes them auditable and lets synthesis build a small ROM/LUT; doing
arithmetic on segment bits would be slower to read and easier to get wrong.

`A`–`F` use the conventional hexadecimal shapes (`b`, `d` lower-case to
distinguish them from `8` and `0`).

## Files

| File | Purpose |
|---|---|
| `mux4.vhd` | Parameterized 4:1 multiplexer |
| `prio_enc8.vhd` | 8:3 priority encoder |
| `seven_seg.vhd` | Hexadecimal to active-low 7-segment decoder |
| `combinational_tb.vhd` | Exhaustive self-checking testbench |

## Simulate

```sh
make test
make wave
```

From the repository root:

```sh
make test PROJECT=01-combinational-basics
make wave PROJECT=01-combinational-basics
```

`make wave` opens `build/combinational_tb.ghw`. This project has no clock, so
the waveform is short; step through the input changes rather than expecting a
time-domain pattern.

## Signals to inspect in GTKWave

- `combinational_tb.sel`
- `combinational_tb.d0`, `d1`, `d2`, `d3`
- `combinational_tb.mux_y`
- `combinational_tb.prio_din`
- `combinational_tb.prio_valid`
- `combinational_tb.prio_index`
- `combinational_tb.hex`
- `combinational_tb.seg`
- `combinational_tb.dut_mux.y_o`
- `combinational_tb.dut_prio.index_o`
- `combinational_tb.dut_seg.seg_o`

## Testbench strategy

The testbench is purely combinational: it changes an input, waits 1 ns for the
concurrent assignment to settle, then checks the output. A watchdog still
guards against a stimulus process that never finishes.

| Test | What it proves |
|---|---|
| TC1 | `mux4` selects each input for all four select values |
| TC2 | `prio_enc8` reports every one-hot input correctly |
| TC3 | All-zero is invalid; multiple bits resolve to the highest index |
| TC4 | All 16 `seven_seg` patterns match the expected table |

Total: **45 checks**. Run with `--assert-level=failure` so a failed check is
reported but does not abort the run; the summary raises `failure` only if
something actually failed.

## Pitfalls

- `sel_i` is `std_logic_vector`, not an enumeration. `"0X"` or `"1Z"` falls into
  the `others` branch and selects `d3_i`; do not treat that as a defined state.
- `index_o` is only meaningful when `valid_o = '1'`.
- The segment table is active low. A pattern of all `'1'` means "display blank",
  not "display 8".
- Do not "optimize" the priority chain into independent comparisons without
  preserving the priority order; that changes the result when several bits are
  set.
- Combinational testbenches need a settling delay. Checking in the same delta
  cycle as the input assignment will read the old output.

## Exercises

1. Widen `mux4` to 8:1 and add a generic `SEL_WIDTH`.
2. Replace the priority chain with a `for` loop that scans from the top and
   verify the same results.
3. Add a decimal point input to `seven_seg` (bit 7 of a common 8-bit output).
4. Make `prio_enc8` parameterizable in width and test 4, 8, and 16 inputs.
5. Add a `blank_i` input that forces all segments off.
6. Write a second testbench that drives random inputs and compares the mux
   against a software `case` model.
