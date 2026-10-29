-- =============================================================================
-- counter_timer_tb -- checks counter priority/wrap and one-shot pulse width
-- =============================================================================
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;

library work;
use work.tb_pkg.all;

entity counter_timer_tb is
end entity;

architecture sim of counter_timer_tb is

  constant CLK_PERIOD   : time := 10 ns;
  constant TIMEOUT      : time := 1 ms;
  constant PULSE_CYCLES : positive := 10;

  signal clk       : std_logic := '0';
  signal rst       : std_logic := '1';

  signal en        : std_logic := '0';
  signal up        : std_logic := '1';
  signal load      : std_logic := '0';
  signal load_val  : std_logic_vector(7 downto 0) := (others => '0');
  signal count     : std_logic_vector(7 downto 0);
  signal term      : std_logic;

  signal trigger   : std_logic := '0';
  signal pulse     : std_logic;

begin

  clk <= not clk after CLK_PERIOD / 2;

  dut_counter : entity work.counter
    generic map (WIDTH => 8)
    port map (
      clk_i      => clk,
      rst_i      => rst,
      en_i       => en,
      up_i       => up,
      load_i     => load,
      load_val_i => load_val,
      count_o    => count,
      terminal_o => term
    );

  dut_oneshot : entity work.oneshot
    generic map (
      CLK_PERIOD_NS => 10,
      PULSE_NS      => PULSE_CYCLES * 10
    )
    port map (
      clk_i     => clk,
      rst_i     => rst,
      trigger_i => trigger,
      pulse_o   => pulse
    );

  stim : process is
    variable width : natural;
  begin
    report "TC1: reset and load priority" severity note;
    wait_cycles(clk, 3);
    rst <= '0';
    wait_cycles(clk, 1);
    check_eq(count, x"00", "counter resets to zero");
    check_eq(term, '0', "not terminal when counting up from zero");

    load_val <= x"10";
    load <= '1';
    wait_cycles(clk, 1);
    load <= '0';
    check_eq(count, x"10", "load wins over enable");

    report "TC2: up/down counting and enable" severity note;
    en <= '1';
    up <= '1';
    wait_cycles(clk, 5);
    check_eq(count, x"15", "five up-counts");

    up <= '0';
    wait_cycles(clk, 3);
    check_eq(count, x"12", "three down-counts");

    en <= '0';
    wait_cycles(clk, 2);
    check_eq(count, x"12", "disabled counter holds its value");

    report "TC3: wrap and terminal flag" severity note;
    up <= '1';
    load_val <= x"FF";
    load <= '1';
    wait_cycles(clk, 1);
    load <= '0';
    wait for 1 ns;
    check_eq(count, x"FF", "loaded maximum");
    check_eq(term, '1', "terminal when up at maximum");

    en <= '1';
    up <= '1';
    wait_cycles(clk, 1);
    check_eq(count, x"00", "up-count wraps to zero");
    check_eq(term, '0', "terminal clears after wrap");

    load_val <= x"00";
    load <= '1';
    wait_cycles(clk, 1);
    load <= '0';
    up <= '0';
    wait for 1 ns;
    check_eq(term, '1', "terminal when down at minimum");

    wait_cycles(clk, 1);
    check_eq(count, x"FF", "down-count wraps to maximum");

    report "TC4: one-shot pulse width" severity note;
    load <= '0';
    en <= '0';
    wait_cycles(clk, 5);

    trigger <= '1';
    wait_cycles(clk, 1);
    trigger <= '0';

    width := 0;
    while pulse = '1' loop
      wait until rising_edge(clk);
      wait for 1 ns;
      width := width + 1;
    end loop;
    check_eq(width, PULSE_CYCLES, "one-shot pulse width in cycles");

    report "TC5: retriggerable one-shot" severity note;
    wait_cycles(clk, 3);

    trigger <= '1';
    wait_cycles(clk, 1);
    trigger <= '0';
    wait_cycles(clk, 4);       -- still inside the first pulse
    trigger <= '1';
    wait_cycles(clk, 1);
    trigger <= '0';

    width := 0;
    while pulse = '1' loop
      wait until rising_edge(clk);
      wait for 1 ns;
      width := width + 1;
    end loop;
    check_eq(width, PULSE_CYCLES, "retrigger reloads the full width");

    test_summary("counter_timer");
  end process;

  watchdog : process is
  begin
    wait for TIMEOUT;
    fail("counter/timer testbench timeout");
  end process;

end architecture;
