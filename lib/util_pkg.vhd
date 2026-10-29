-- =============================================================================
-- util_pkg -- small helpers shared by the projects
--
-- These are intentionally simple, synthesizable functions.  Keeping them in
-- one place avoids every project inventing its own width/saturation helpers.
-- =============================================================================
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package util_pkg is

  -- ceil(log2(value)); clog2(1) = 0.  Used for pointer/filter widths.
  function clog2(value : positive) return natural;

  -- Saturate a signed value to width bits.  Sign-extends when width is larger,
  -- clamps to the most negative/positive value when width is smaller.
  function sat_signed(value : signed; width : positive) return signed;

  -- Number of '1' bits; useful for parity and simple popcount checks.
  function count_ones(value : std_logic_vector) return natural;

  -- True when value is an exact power of two (used to validate FIFO depths).
  function is_power_of_two(value : positive) return boolean;

end package;

package body util_pkg is

  function clog2(value : positive) return natural is
    variable n : natural := value - 1;
    variable r : natural := 0;
  begin
    while n > 0 loop
      n := n / 2;
      r := r + 1;
    end loop;
    return r;
  end function;

  function sat_signed(value : signed; width : positive) return signed is
    -- The aggregate target is a constrained subtype, so "others" is legal even
    -- though width is a runtime parameter.  The sign bit is then overridden.
    variable max_value : signed(width - 1 downto 0) := (others => '1');
    variable min_value : signed(width - 1 downto 0) := (others => '0');
  begin
    max_value(width - 1) := '0';
    min_value(width - 1) := '1';

    if value'length <= width then
      -- Widening cannot overflow, so simple sign extension is enough.
      return resize(value, width);
    elsif value > resize(max_value, value'length) then
      return max_value;
    elsif value < resize(min_value, value'length) then
      return min_value;
    else
      return value(width - 1 downto 0);
    end if;
  end function;

  function count_ones(value : std_logic_vector) return natural is
    variable n : natural := 0;
  begin
    for i in value'range loop
      if value(i) = '1' then
        n := n + 1;
      end if;
    end loop;
    return n;
  end function;

  function is_power_of_two(value : positive) return boolean is
    variable n : positive := value;
  begin
    -- Divide out factors of two; only 1 is left for a power of two.
    while n mod 2 = 0 loop
      n := n / 2;
    end loop;
    return n = 1;
  end function;

end package body;
