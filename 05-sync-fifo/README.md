# 05-sync-fifo — parameterized synchronous FIFO

## Overview

A synchronous FIFO decouples a producer from a consumer that run at different
rates or have bursty timing. This project implements a single-clock FIFO with:

- parameterized data width and depth,
- a registered read output ("standard FIFO" timing),
- `full` / `empty` backpressure flags,
- `almost_full` / `almost_empty` thresholds,
- an exact element count,
- simultaneous read and write support.

The depth must be a power of two. That lets the read and write pointers wrap
naturally and keeps the full/empty logic to a single counter comparison.

Industrial relevance: UART/SPI/I2C receive buffers, ADC sample queues, packet
buffers between a fast acquisition path and a slower control path, and the
elastic buffer between two parts of a pipeline.

## What you will learn

- How a circular buffer works with read and write pointers.
- Why a power-of-two depth simplifies pointer wrap and flag generation.
- How an element counter avoids the classic "one slot wasted" FIFO design.
- How to update the count correctly for all four read/write combinations.
- Why a registered read output has one cycle of latency.
- How `full` and `empty` implement backpressure.
- How to build a randomized scoreboard with a mirror queue.

## Block diagram

```text
                 +--------------------------------------+
 din_i[W-1:0] -->|            memory (DEPTH x W)        |
 wr_en_i ------->|  write at wr_ptr when not full        |
                 |                                      |
                 |  read  at rd_ptr when not empty  --->|--> dout_o[W-1:0]
 rd_en_i ------->|                                      |    (registered)
                 +--------------------------------------+
                        |                |
                        v                v
                    wr_ptr           rd_ptr
                        \               /
                         +-----+-------+
                               |
                          count (0..DEPTH)
                               |
              +----------------+----------------+
              |        |       |       |        |
           full_o  empty_o  count_o  almost_  almost_
                                     full_o   empty_o
```

## Generics

| Name | Type | Default | Meaning |
|---|---|---|---|
| `WIDTH` | `positive` | `8` | Data width in bits |
| `DEPTH` | `positive` | `16` | Number of words; must be a power of two and ≥ 2 |
| `ALMOST_FULL_LEVEL` | `natural` | `DEPTH - 2` | Assert `almost_full_o` when `count >= level` |
| `ALMOST_EMPTY_LEVEL` | `natural` | `2` | Assert `almost_empty_o` when `count <= level` |

Derived widths:

```text
ADDR_WIDTH  = clog2(DEPTH)        -- pointer width
COUNT_WIDTH = clog2(DEPTH + 1)    -- enough for 0..DEPTH
```

The default thresholds assume `DEPTH >= 4`; override them for a 2-deep FIFO.
Both thresholds are inclusive.

## Ports

| Name | Direction | Width | Meaning |
|---|---|---|---|
| `clk_i` | in | 1 | Clock |
| `rst_i` | in | 1 | Synchronous active-high reset |
| `wr_en_i` | in | 1 | Request a write |
| `rd_en_i` | in | 1 | Request a read |
| `din_i` | in | `WIDTH` | Write data |
| `dout_o` | out | `WIDTH` | Read data, valid one cycle after an accepted read |
| `full_o` | out | 1 | High when `count = DEPTH`; writes are ignored |
| `empty_o` | out | 1 | High when `count = 0`; reads are ignored |
| `almost_full_o` | out | 1 | High when `count >= ALMOST_FULL_LEVEL` |
| `almost_empty_o` | out | 1 | High when `count <= ALMOST_EMPTY_LEVEL` |
| `count_o` | out | `clog2(DEPTH + 1)` | Exact number of stored words |

## Design notes

### Pointers and count

`wr_ptr` and `rd_ptr` are `unsigned` values of `ADDR_WIDTH` bits. Incrementing
them at the end of the buffer wraps to zero automatically because the type is
fixed-width. `count` is one bit wider so it can represent `DEPTH` as well as
zero.

Using an explicit count instead of comparing the pointers avoids the usual
"full when pointers are equal after wrapping" ambiguity. The cost is a small
adder; the benefit is that `count_o` is directly usable by the surrounding
logic and the flags are trivial.

### Accept conditions

```text
wr_ok = wr_en_i and not full_s
rd_ok = rd_en_i and not empty_s
```

A write is silently dropped while full, and a read is silently dropped while
empty. That is the normal FIFO contract: the flags are the handshake, and the
enable is a request. If you need to detect a protocol error, add sticky
overflow/underflow bits (see the exercises).

### Registered read output

When `rd_ok` is high, the memory word at `rd_ptr` is copied into `dout_r` on the
rising edge. Therefore:

```text
cycle N:   rd_en_i = 1, empty_o = 0
cycle N+1: dout_o = old head, count decreased by one
```

This is the "standard FIFO" timing and maps to a block-RAM synchronous read.
If you need the head visible immediately (first-word fall-through), see the
exercises.

### Count update

Only one of four cases changes the occupancy:

| Write accepted | Read accepted | `count` |
|---|---|---|
| no | no | unchanged |
| yes | no | `count + 1` |
| no | yes | `count - 1` |
| yes | yes | unchanged |

The simultaneous case is important: a producer and consumer can both move one
word per cycle without the FIFO filling or draining.

### Full with a simultaneous read and write

When the FIFO is full, a write is blocked but a read is still allowed. The read
returns the oldest word; the write request is dropped. The next write can then
reuse the freed slot. This is why `full_o` must be treated as backpressure, not
as a global stall.

### Flags

`full_o` and `empty_o` are combinational functions of the registered `count`, so
they are stable for the whole cycle after the edge that changed the count. The
almost flags are inclusive comparisons:

```text
almost_full_o  = (count >= ALMOST_FULL_LEVEL)
almost_empty_o = (count <= ALMOST_EMPTY_LEVEL)
```

A typical use is to start a burst when `almost_empty_o` asserts and stop
accepting new data when `almost_full_o` asserts, leaving headroom for latency.

### Reset and memory contents

Reset clears both pointers, the count, and the output register. The memory array
is deliberately **not** reset: block RAMs do not have a reset, and the empty
flag prevents reading an unwritten location. `dout_o` is zero after reset and
holds the last read word when the FIFO becomes empty.

## Files

| File | Purpose |
|---|---|
| `sync_fifo.vhd` | Parameterized synchronous FIFO |
| `sync_fifo_tb.vhd` | Directed tests plus a 400-operation randomized scoreboard |

## Simulate

```sh
make test
make wave
```

From the repository root:

```sh
make test PROJECT=05-sync-fifo
make wave PROJECT=05-sync-fifo
```

`make wave` opens `build/sync_fifo_tb.ghw`.

## Signals to inspect in GTKWave

Top-level stimulus and results:

- `sync_fifo_tb.clk`
- `sync_fifo_tb.rst`
- `sync_fifo_tb.wr_en`
- `sync_fifo_tb.rd_en`
- `sync_fifo_tb.din`
- `sync_fifo_tb.dout`
- `sync_fifo_tb.full`
- `sync_fifo_tb.empty`
- `sync_fifo_tb.almost_full`
- `sync_fifo_tb.almost_empty`
- `sync_fifo_tb.count`

FIFO internals:

- `sync_fifo_tb.dut.wr_ptr`
- `sync_fifo_tb.dut.rd_ptr`
- `sync_fifo_tb.dut.count`
- `sync_fifo_tb.dut.dout_r`
- `sync_fifo_tb.dut.full_s`
- `sync_fifo_tb.dut.empty_s`
- `sync_fifo_tb.dut.wr_ok`
- `sync_fifo_tb.dut.rd_ok`
- `sync_fifo_tb.dut.mem` (expand the array to watch individual words)

A useful view is `count` with `full`/`empty` above it: the count ramps up
during the fill, holds during simultaneous traffic, and ramps down during the
drain.

## Testbench strategy

The TB keeps a software queue (`queue`, `head`, `tail`, `qcount`) that mirrors
the FIFO. It predicts which requests are accepted, compares every read against
the queue head, and checks `count` and all four flags after each operation.

| Test | What it proves |
|---|---|
| TC1 | Reset clears the count, flags, and output |
| TC2 | One write and one read return the same word |
| TC3 | Filling to `DEPTH` asserts `almost_full` then `full` |
| TC4 | A write while full is ignored |
| TC5 | Draining returns all words in order and asserts `empty` |
| TC6 | A read while empty is ignored and `dout` holds |
| TC7 | Simultaneous read/write keeps occupancy constant |
| TC8 | At full, the read succeeds while the write is dropped |
| TC9 | 400 randomized operations match the mirror queue |

Total: **2577 checks**. The stress run uses a 16-bit LFSR with a fixed seed, so
failures are reproducible. The TB also drains the queue after the stress run to
verify that no word was lost or reordered.

## Pitfalls

- `dout_o` is not valid in the same cycle as `rd_en_i`; it appears after the
  edge. A consumer that samples it too early reads the previous word.
- `rd_en_i` while `empty_o = 1` does nothing and does not change `dout_o`.
- `wr_en_i` while `full_o = 1` does nothing. Dropping the write silently is the
  contract; add an overflow flag if the producer must know.
- `DEPTH` must be a power of two. A non-power-of-two depth breaks the pointer
  wrap and the count-to-address relationship.
- The almost thresholds are inclusive and are not clamped. Pick levels that
  match your latency budget.
- The memory is not reset, so do not read it before writing. The `empty` flag
  is what makes that safe.
- A full FIFO with a simultaneous read and write is not a deadlock: the read
  proceeds and frees a slot, but that cycle's write is still dropped.
- `count_o` is registered and therefore one cycle behind a request that has not
  yet been clocked in.

## Exercises

1. Add a first-word fall-through mode where `dout_o` always shows the head when
   `empty_o = 0`.
2. Add sticky `overflow_o` and `underflow_o` flags that latch when a request is
   dropped.
3. Make `ALMOST_FULL_LEVEL` and `ALMOST_EMPTY_LEVEL` runtime input ports.
4. Add a `flush_i` input that clears the FIFO without a full reset.
5. Add a `data_valid_o` that is high for exactly one cycle after a read.
6. Measure the maximum throughput and explain why one word per cycle is
   possible.
7. Sketch a dual-clock (asynchronous) FIFO using Gray-coded pointers and
   explain why the single-clock count cannot be shared directly.
8. Add a test that fills the FIFO, reads one word, writes one word, and checks
   that the memory slot was reused correctly.
