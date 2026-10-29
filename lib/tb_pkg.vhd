-- =============================================================================
-- tb_pkg -- tiny self-checking testbench support package
--
-- Design choices worth knowing:
--   * Checks report severity ERROR and keep going.  Run simulations with
--     --assert-level=failure so an error does not abort the whole test.
--   * test_summary raises severity FAILURE when anything failed, which makes
--     GHDL return a non-zero exit status for make/CI.
--   * Counters are package-body variables: one testbench per simulation.
-- =============================================================================
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;

package tb_pkg is

  -- Wait for n rising clock edges.
  procedure wait_cycles(signal clk : in std_logic; n : natural);

  -- Record one boolean check.
  procedure check(condition : boolean; message : string);

  -- Typed equality helpers.  Messages should say *what* is being checked.
  procedure check_eq(actual, expected : integer; message : string);
  procedure check_eq(actual, expected : std_logic; message : string);
  procedure check_eq(actual, expected : std_logic_vector; message : string);
  procedure check_eq(actual, expected : unsigned; message : string);
  procedure check_eq(actual, expected : signed; message : string);

  -- Abort immediately (used by timeout watchdogs).
  procedure fail(message : string);

  -- Print a summary, then stop: exit 0 on success, non-zero on failure.
  procedure test_summary(name : string);

  -- The type is public only because a protected type body needs a declaration
  -- in the package spec.  The single instance lives privately in the body.
  type counter_t is protected
    procedure add_check;
    procedure add_error;
    impure function checks return natural;
    impure function errors return natural;
  end protected counter_t;

  impure function check_count return natural;
  impure function error_count return natural;

end package;

package body tb_pkg is

  type counter_t is protected body
    variable n_checks : natural := 0;
    variable n_errors : natural := 0;

    procedure add_check is
    begin
      n_checks := n_checks + 1;
    end procedure;

    procedure add_error is
    begin
      n_errors := n_errors + 1;
    end procedure;

    impure function checks return natural is
    begin
      return n_checks;
    end function;

    impure function errors return natural is
    begin
      return n_errors;
    end function;
  end protected body counter_t;

  -- Declared after the protected body to keep GHDL's elaboration warning away.
  -- The type is private to this package, so the spec stays small.
  shared variable counters : counter_t;

  procedure wait_cycles(signal clk : in std_logic; n : natural) is
  begin
    for i in 1 to n loop
      wait until rising_edge(clk);
      -- Let registered updates propagate before the caller inspects signals.
      -- One nanosecond is safely below the clock period used by these TBs.
      wait for 1 ns;
    end loop;
  end procedure;

  procedure check(condition : boolean; message : string) is
  begin
    counters.add_check;
    if not condition then
      counters.add_error;
      report "FAIL: " & message severity error;
    end if;
  end procedure;

  procedure check_eq(actual, expected : integer; message : string) is
  begin
    counters.add_check;
    if actual /= expected then
      counters.add_error;
      report "FAIL: " & message &
             " (expected " & integer'image(expected) &
             ", got " & integer'image(actual) & ")" severity error;
    end if;
  end procedure;

  procedure check_eq(actual, expected : std_logic; message : string) is
  begin
    counters.add_check;
    if actual /= expected then
      counters.add_error;
      report "FAIL: " & message &
             " (expected " & std_logic'image(expected) &
             ", got " & std_logic'image(actual) & ")" severity error;
    end if;
  end procedure;

  procedure check_eq(actual, expected : std_logic_vector; message : string) is
  begin
    counters.add_check;
    if actual /= expected then
      counters.add_error;
      report "FAIL: " & message &
             " (expected 0x" & to_hstring(expected) &
             ", got 0x" & to_hstring(actual) & ")" severity error;
    end if;
  end procedure;

  procedure check_eq(actual, expected : unsigned; message : string) is
  begin
    counters.add_check;
    if actual /= expected then
      counters.add_error;
      report "FAIL: " & message &
             " (expected 0x" & to_hstring(std_logic_vector(expected)) &
             ", got 0x" & to_hstring(std_logic_vector(actual)) & ")" severity error;
    end if;
  end procedure;

  procedure check_eq(actual, expected : signed; message : string) is
  begin
    counters.add_check;
    if actual /= expected then
      counters.add_error;
      report "FAIL: " & message &
             " (expected " & integer'image(to_integer(expected)) &
             ", got " & integer'image(to_integer(actual)) & ")" severity error;
    end if;
  end procedure;

  procedure fail(message : string) is
  begin
    report "FATAL: " & message severity failure;
    finish;
  end procedure;

  procedure test_summary(name : string) is
  begin
    if counters.checks = 0 then
      report name & ": no checks were executed" severity failure;
    elsif counters.errors = 0 then
      report name & ": " & integer'image(counters.checks) &
             " checks, TEST PASSED" severity note;
      finish;
    else
      report name & ": " & integer'image(counters.errors) & " of " &
             integer'image(counters.checks) & " checks FAILED" severity failure;
    end if;
  end procedure;

  impure function check_count return natural is
  begin
    return counters.checks;
  end function;

  impure function error_count return natural is
  begin
    return counters.errors;
  end function;

end package body;
