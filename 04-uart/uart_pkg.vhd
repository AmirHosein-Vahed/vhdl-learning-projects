-- =============================================================================
-- uart_pkg -- shared UART timing helpers (8N1, 16x receive oversampling)
-- =============================================================================
library ieee;
use ieee.std_logic_1164.all;

package uart_pkg is

  constant OVERSAMPLE : positive := 16;

  -- Number of clocks in one bit.  Kept as a function so both TX and RX use
  -- exactly the same rounding rule.
  function calc_bit_period(clk_hz, baud : positive) return positive;

  -- Number of clocks between 16x oversampling ticks.
  function calc_tick_divisor(clk_hz, baud : positive) return positive;

end package;

package body uart_pkg is

  function calc_bit_period(clk_hz, baud : positive) return positive is
    variable n : natural;
  begin
    n := clk_hz / baud;
    assert n >= 2
      report "uart_pkg: clock/baud ratio is too small"
      severity failure;
    return n;
  end function;

  function calc_tick_divisor(clk_hz, baud : positive) return positive is
    variable n : natural;
  begin
    n := clk_hz / (baud * OVERSAMPLE);
    assert n >= 1
      report "uart_pkg: baud rate is too high for 16x oversampling"
      severity failure;
    return n;
  end function;

end package body;
