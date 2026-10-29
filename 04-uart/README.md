# 04-uart — 8N1 UART transmitter and receiver

## Overview

A UART is still the default debug, telemetry, and service port on industrial
boards. This project implements the two halves separately:

- `uart_tx`: one start bit, eight data bits (LSB first), one stop bit.
- `uart_rx`: the same 8N1 format, with 16× oversampling and mid-bit sampling.

There is no parity and no break detector; those are good next exercises. The
transmitter uses a simple `valid_i` / `ready_o` handshake, and the receiver
emits one-cycle `valid_o` / `frame_err_o` pulses. Keeping TX and RX independent
makes it easy to reuse one side without dragging in the other.

The testbench runs both blocks at a scaled-down clock (1 MHz, 62.5 kbaud) so
the simulation stays fast while still giving exactly 16 clocks per bit.

## What you will learn

- How a baud-rate divider turns a clock into a serial bit period.
- Why a receiver oversamples instead of sampling once per bit.
- How to find the middle of a start bit and stay aligned across eight data bits.
- Why an asynchronous RX pin needs a two-flop synchronizer before any logic.
- How to report framing errors and reject a false start caused by a glitch.
- How to build a serial BFM and a loopback testbench.

## Block diagram

```text
                 uart_tx
              +-----------+
 data_i[7:0]  |           |  tx_o
 valid_i ---->|  shift /  |-------> serial line
 ready_o <----|  FSM      |
              +-----------+

                 uart_rx
 serial line -->| 2FF sync  |-->| 16x tick |-->| start/data/stop |
                |           |   | os_cnt   |   | sampling FSM  |
                +-----------+   +----------+   +---------------+
                                                   | data_o[7:0]
                                                   | valid_o
                                                   | frame_err_o
```

## Generics

Both entities use the same timing generics.

| Name | Type | Default | Meaning |
|---|---|---|---|
| `CLK_HZ` | `positive` | `50_000_000` | Frequency of `clk_i` in Hz |
| `BAUD` | `positive` | `115_200` | Requested baud rate |

`uart_pkg` derives:

- `bit_period = CLK_HZ / BAUD` — transmitter clocks per bit.
- `tick_divisor = CLK_HZ / (BAUD × 16)` — receiver clocks per oversampling tick.

Both must be at least 2 and 1 respectively. Use a clock/baud combination that
divides cleanly when you can; otherwise the integer truncation becomes a baud
error. The TB uses `1_000_000 / 62_500 = 16`, so the timing is exact.

## Ports — `uart_tx`

| Name | Direction | Width | Meaning |
|---|---|---|---|
| `clk_i` | in | 1 | Clock |
| `rst_i` | in | 1 | Synchronous active-high reset |
| `data_i` | in | 8 | Byte to transmit |
| `valid_i` | in | 1 | One-cycle start request |
| `ready_o` | out | 1 | High while idle and able to accept a byte |
| `tx_o` | out | 1 | Serial output; idle high |

## Ports — `uart_rx`

| Name | Direction | Width | Meaning |
|---|---|---|---|
| `clk_i` | in | 1 | Clock |
| `rst_i` | in | 1 | Synchronous active-high reset |
| `rx_i` | in | 1 | Asynchronous serial input; idle high |
| `data_o` | out | 8 | Last received byte |
| `valid_o` | out | 1 | One-cycle pulse when a good byte arrives |
| `frame_err_o` | out | 1 | One-cycle pulse when the stop bit is zero |

## Design notes

### Transmitter

The TX FSM has four states: `IDLE`, `START`, `DATA`, `STOP`. A `baud_cnt`
counts clocks inside each bit. `ready_o` is high only in `IDLE`, so a producer
can hold `valid_i` until the byte is accepted. The shift register rotates right
by one each bit boundary, which puts the next LSB on `tx_o`.

The stop bit is held for a full bit period before returning to idle. That is
what lets back-to-back bytes be separated correctly.

### Receiver

The external pin first goes through a two-flop synchronizer. The synchronized
signal feeds a free-running 16× tick counter. When a falling edge is seen in
`IDLE`, the tick counter is reset and the FSM moves to `START`.

At `os_cnt = 8` (half a bit) the start bit is sampled again. If it is still low,
the frame is real and the FSM moves to `DATA`; otherwise it is a glitch and the
receiver returns to idle. Data bits are sampled at the same half-bit point of
each subsequent bit, which gives the maximum margin against clock/baud error.

A zero stop bit produces `frame_err_o` and does **not** produce `valid_o`. The
receiver does not implement parity, break detection, or an RX FIFO.

### Timing caveat

`calc_tick_divisor` uses integer division. At 50 MHz / 115200 baud the ideal
divisor is 27.126…, so the actual baud rate is slightly high. This is normally
acceptable for 8N1, but calculate the error before using a marginal clock:

```text
actual_baud = CLK_HZ / (tick_divisor × 16)
error       = (actual_baud - BAUD) / BAUD
```

## Files

| File | Purpose |
|---|---|
| `uart_pkg.vhd` | Oversampling constant and timing helper functions |
| `uart_tx.vhd` | 8N1 transmitter |
| `uart_rx.vhd` | 8N1 receiver with synchronizer and framing error |
| `uart_tb.vhd` | Loopback, raw-frame, framing-error, and glitch tests |

## Simulate

```sh
make test
make wave
```

The top-level Makefile also works:

```sh
make test PROJECT=04-uart
make wave PROJECT=04-uart
```

`make wave` opens `build/uart_tb.ghw` in GTKWave. Add the signals listed below
and save your own layout if you want one; this repo does not ship `.gtkw` files.

## Signals to inspect in GTKWave

Transmitter and loopback:

- `uart_tb.clk`
- `uart_tb.rst`
- `uart_tb.tx_data`
- `uart_tb.tx_valid`
- `uart_tb.tx_ready`
- `uart_tb.tx_line`
- `uart_tb.dut_tx.state`
- `uart_tb.dut_tx.shift`
- `uart_tb.dut_tx.baud_cnt`

Receiver:

- `uart_tb.rx_line`
- `uart_tb.dut_rx.state`
- `uart_tb.dut_rx.rx_sync`
- `uart_tb.dut_rx.os_cnt`
- `uart_tb.dut_rx.bit_idx`
- `uart_tb.dut_rx.shift`
- `uart_tb.dut_rx.valid_o`
- `uart_tb.dut_rx.frame_err_o`

Testbench controls:

- `uart_tb.loopback`
- `uart_tb.host_line`
- `uart_tb.valid_count`
- `uart_tb.frame_count`

## Testbench strategy

| Test | What it proves |
|---|---|
| TC1 | Reset leaves TX ready and the line idle high |
| TC2 | Four bytes loop back correctly: `55`, `A3`, `00`, `FF` |
| TC3 | A zero stop bit produces a framing error and no valid pulse |
| TC4 | A short low glitch is rejected as a false start |
| TC5 | A hand-built valid frame is received correctly |

The receiver flags are one-clock pulses, so the TB counts them on their rising
edges and checks the captured byte. This avoids a race between the stimulus
process finishing and the pulse disappearing.

## Pitfalls

- The TB clock period must match `CLK_HZ`. A 10 ns clock with `CLK_HZ =
  1_000_000` will produce nonsense timing.
- `loopback` and `host_line` must never drive the receiver at the same time.
  The mux selects exactly one source.
- `valid_i` is a request, not a level: hold it until `ready_o` is high, then
  pulse it for one clock. Holding it high for many clocks is harmless here but
  is not a general streaming contract.
- The RX synchronizer adds two clocks of latency. That is included in the
  mid-bit sampling margin, but it matters if you tighten the oversampling.
- A framing error tells you the stop bit was bad. It does not tell you which
  earlier bit was wrong.

## Exercises

1. Add optional even/odd parity to both TX and RX. Add a `parity_err_o` pulse.
2. Detect a break condition (all data bits zero and a zero stop bit).
3. Add a small RX FIFO so a slow consumer does not lose bytes.
4. Make the oversampling factor a generic and test 8× and 16×.
5. Measure the actual baud rate from the waveform and compare it with the
   ideal value.
6. Add an overrun flag for the case where `valid_o` is ignored and another byte
   arrives.
