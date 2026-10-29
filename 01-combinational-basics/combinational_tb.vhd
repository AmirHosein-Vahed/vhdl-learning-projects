-- =============================================================================
-- combinational_tb -- exhaustive checks for mux4, prio_enc8, and seven_seg
--
-- This testbench is purely combinational, so a short delay after each input
-- change is enough to let the concurrent assignments settle.  There is no
-- clock; the watchdog still protects against a coding mistake that prevents
-- the stimulus process from finishing.
-- =============================================================================
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;

library work;
use work.tb_pkg.all;

entity combinational_tb is
end entity;

architecture sim of combinational_tb is

  type seg_table_t is array (0 to 15) of std_logic_vector(6 downto 0);
  type byte_table_t is array (0 to 15) of std_logic_vector(7 downto 0);

  constant SEG_EXPECTED : seg_table_t := (
    "1000000", "1111001", "0100100", "0110000",
    "0011001", "0010010", "0000010", "1111000",
    "0000000", "0010000", "0001000", "0000011",
    "1000110", "0100001", "0000110", "0001110"
  );

  constant MUX_EXPECTED : byte_table_t := (
    x"A0", x"B1", x"C2", x"D3",
    x"A0", x"B1", x"C2", x"D3",
    x"A0", x"B1", x"C2", x"D3",
    x"A0", x"B1", x"C2", x"D3"
  );

  signal sel       : std_logic_vector(1 downto 0) := "00";
  signal d0        : std_logic_vector(7 downto 0) := x"A0";
  signal d1        : std_logic_vector(7 downto 0) := x"B1";
  signal d2        : std_logic_vector(7 downto 0) := x"C2";
  signal d3        : std_logic_vector(7 downto 0) := x"D3";
  signal mux_y     : std_logic_vector(7 downto 0);

  signal prio_din  : std_logic_vector(7 downto 0) := (others => '0');
  signal prio_valid: std_logic;
  signal prio_index: std_logic_vector(2 downto 0);

  signal hex       : std_logic_vector(3 downto 0) := (others => '0');
  signal seg       : std_logic_vector(6 downto 0);

begin

  dut_mux : entity work.mux4
    port map (
      sel_i => sel,
      d0_i  => d0,
      d1_i  => d1,
      d2_i  => d2,
      d3_i  => d3,
      y_o   => mux_y
    );

  dut_prio : entity work.prio_enc8
    port map (
      din_i   => prio_din,
      valid_o => prio_valid,
      index_o => prio_index
    );

  dut_seg : entity work.seven_seg
    port map (
      hex_i => hex,
      seg_o => seg
    );

  stim : process is
    variable expected : std_logic_vector(7 downto 0);
    variable one_hot  : std_logic_vector(7 downto 0);
  begin
    report "TC1: mux4 selects the requested input" severity note;
    for s in 0 to 3 loop
      sel <= std_logic_vector(to_unsigned(s, 2));
      wait for 1 ns;
      case s is
        when 0      => expected := d0;
        when 1      => expected := d1;
        when 2      => expected := d2;
        when others => expected := d3;
      end case;
      check_eq(mux_y, expected, "mux4 sel=" & integer'image(s));
      check_eq(mux_y, MUX_EXPECTED(s), "mux4 table sel=" & integer'image(s));
    end loop;

    report "TC2: priority encoder one-hot inputs" severity note;
    for i in 0 to 7 loop
      one_hot := (others => '0');
      one_hot(i) := '1';
      prio_din <= one_hot;
      wait for 1 ns;
      check_eq(prio_valid, '1', "one-hot valid, bit " & integer'image(i));
      check_eq(prio_index, std_logic_vector(to_unsigned(i, 3)),
               "one-hot index, bit " & integer'image(i));
    end loop;

    report "TC3: priority encoder edge cases" severity note;
    prio_din <= x"00";
    wait for 1 ns;
    check_eq(prio_valid, '0', "all-zero input is invalid");
    check_eq(prio_index, "000", "all-zero index is zero");

    prio_din <= x"81";
    wait for 1 ns;
    check_eq(prio_valid, '1', "multiple bits valid");
    check_eq(prio_index, "111", "highest bit wins (bit 7)");

    prio_din <= x"06";
    wait for 1 ns;
    check_eq(prio_index, "010", "highest bit wins (bit 2)");

    report "TC4: seven-segment table" severity note;
    for i in 0 to 15 loop
      hex <= std_logic_vector(to_unsigned(i, 4));
      wait for 1 ns;
      check_eq(seg, SEG_EXPECTED(i),
               "seven-seg value " & integer'image(i));
    end loop;

    test_summary("combinational_basics");
  end process;

  watchdog : process is
  begin
    wait for 1 ms;
    fail("combinational testbench timeout");
  end process;

end architecture;
