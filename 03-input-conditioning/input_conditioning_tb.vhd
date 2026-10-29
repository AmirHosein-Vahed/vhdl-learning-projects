-- =============================================================================
-- input_conditioning_tb -- synchronizer, debounce, and edge-detect tests
--
-- The stimulus deliberately toggles raw_i on consecutive clocks to model
-- contact bounce.  A monitor counts rise/fall pulses so the test can prove
-- that debouncing produces exactly one event per real transition.
-- =============================================================================
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;

library work;
use work.tb_pkg.all;

entity input_conditioning_tb is
end entity;

architecture sim of input_conditioning_tb is

  constant CLK_PERIOD   : time := 10 ns;
  constant DEBOUNCE_NS  : positive := 100;  -- 10 cycles
  constant TIMEOUT      : time := 1 ms;

  signal clk        : std_logic := '0';
  signal rst        : std_logic := '1';
  signal raw        : std_logic := '0';
  signal clean      : std_logic;
  signal rise       : std_logic;
  signal fall       : std_logic;

  signal async_in   : std_logic := '0';
  signal sync_out   : std_logic;

  signal rise_count : natural := 0;
  signal fall_count : natural := 0;

begin

  clk <= not clk after CLK_PERIOD / 2;

  dut_sync : entity work.sync_ff
    generic map (STAGES => 2)
    port map (
      clk_i   => clk,
      rst_i   => rst,
      async_i => async_in,
      sync_o  => sync_out
    );

  dut : entity work.input_conditioning
    generic map (
      CLK_PERIOD_NS => 10,
      DEBOUNCE_NS   => DEBOUNCE_NS
    )
    port map (
      clk_i   => clk,
      rst_i   => rst,
      raw_i   => raw,
      clean_o => clean,
      rise_o  => rise,
      fall_o  => fall
    );

  -- Count events directly on the pulse edges.  Sampling a one-cycle pulse at
  -- the clock edge races with the combinational edge detector, so event
  -- counting is more reliable than a clocked monitor here.
  rise_monitor : process (rise, rst) is
  begin
    if rst = '1' then
      rise_count <= 0;
    elsif rising_edge(rise) then
      rise_count <= rise_count + 1;
    end if;
  end process;

  fall_monitor : process (fall, rst) is
  begin
    if rst = '1' then
      fall_count <= 0;
    elsif rising_edge(fall) then
      fall_count <= fall_count + 1;
    end if;
  end process;

  stim : process is
  begin
    report "TC1: two-flop synchronizer latency" severity note;
    wait_cycles(clk, 3);
    rst <= '0';
    wait_cycles(clk, 2);
    check_eq(sync_out, '0', "synchronizer starts low");

    async_in <= '1';
    wait_cycles(clk, 1);
    check_eq(sync_out, '0', "first stage only after one clock");
    wait_cycles(clk, 1);
    check_eq(sync_out, '1', "second stage after two clocks");
    async_in <= '0';
    wait_cycles(clk, 2);

    report "TC2: bounce is filtered and one rise is produced" severity note;
    for i in 0 to 5 loop
      raw <= '1';
      wait_cycles(clk, 1);
      raw <= '0';
      wait_cycles(clk, 1);
    end loop;

    -- Hold the button down longer than the debounce window.
    raw <= '1';
    wait_cycles(clk, 12);
    check_eq(clean, '1', "clean follows a stable press");
    check_eq(rise_count, 1, "exactly one rising event after bounce");
    check_eq(fall_count, 0, "no falling event yet");

    report "TC3: short glitches do not create events" severity note;
    raw <= '0';
    wait_cycles(clk, 5);   -- shorter than DEBOUNCE_NS
    raw <= '1';
    wait_cycles(clk, 12);
    check_eq(clean, '1', "clean stays high through a short glitch");
    check_eq(rise_count, 1, "glitch did not create another rise event");
    check_eq(fall_count, 0, "glitch did not create a fall event");

    report "TC4: release is debounced as well" severity note;
    raw <= '0';
    wait_cycles(clk, 12);
    check_eq(clean, '0', "clean follows a stable release");
    check_eq(fall_count, 1, "exactly one falling event");
    check_eq(rise_count, 1, "rise count is unchanged by release");

    report "TC5: one-cycle pulse width" severity note;
    wait_cycles(clk, 3);
    check_eq(rise, '0', "rise pulse is not stretched");
    check_eq(fall, '0', "fall pulse is not stretched");

    test_summary("input_conditioning");
  end process;

  watchdog : process is
  begin
    wait for TIMEOUT;
    fail("input conditioning testbench timeout");
  end process;

end architecture;
