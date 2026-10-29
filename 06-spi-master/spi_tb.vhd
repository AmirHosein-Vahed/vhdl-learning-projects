-- =============================================================================
-- spi_tb -- all four SPI modes, two slaves, and a spurious-start test
--
-- Two simulation-only slave models share a MISO line.  Each slave sends a
-- different byte so the test can prove that the selected chip select actually
-- routes the right device.  The master sends a different byte in every mode.
-- =============================================================================
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;

library work;
use work.tb_pkg.all;

entity spi_tb is
end entity;

architecture sim of spi_tb is

  constant CLK_PERIOD : time     := 10 ns;
  constant TIMEOUT    : time     := 5 ms;
  constant NUM_SLAVES : positive := 2;
  constant CLK_DIV    : positive := 2;

  constant SLAVE0_TX : std_logic_vector(7 downto 0) := x"A5";
  constant SLAVE1_TX : std_logic_vector(7 downto 0) := x"3C";

  signal clk        : std_logic := '0';
  signal rst        : std_logic := '1';
  signal start      : std_logic := '0';
  signal mode       : std_logic_vector(1 downto 0) := "00";
  signal cs_sel     : std_logic_vector(NUM_SLAVES - 1 downto 0) := "01";
  signal data_in    : std_logic_vector(7 downto 0) := (others => '0');
  signal data_out   : std_logic_vector(7 downto 0);

  signal sclk       : std_logic;
  signal mosi       : std_logic;
  signal miso_line  : std_logic;
  signal miso0      : std_logic;
  signal miso1      : std_logic;
  signal cs_n       : std_logic_vector(NUM_SLAVES - 1 downto 0);
  signal busy       : std_logic;
  signal done       : std_logic;

  signal slave0_rx  : std_logic_vector(7 downto 0);
  signal slave1_rx  : std_logic_vector(7 downto 0);
  signal done_count : natural := 0;

begin

  clk <= not clk after CLK_PERIOD / 2;

  -- Stand-in for a resolved MISO bus: only the selected slave is forwarded.
  miso_line <= miso0 when cs_n(0) = '0' else
               miso1 when cs_n(1) = '0' else
               '0';

  dut : entity work.spi_master
    generic map (
      NUM_SLAVES => NUM_SLAVES,
      CLK_DIV    => CLK_DIV
    )
    port map (
      clk_i    => clk,
      rst_i    => rst,
      start_i  => start,
      mode_i   => mode,
      cs_sel_i => cs_sel,
      data_i   => data_in,
      data_o   => data_out,
      sclk_o   => sclk,
      mosi_o   => mosi,
      miso_i   => miso_line,
      cs_n_o   => cs_n,
      busy_o   => busy,
      done_o   => done
    );

  slave0 : entity work.spi_slave_model
    port map (
      cs_n_i    => cs_n(0),
      sclk_i    => sclk,
      mosi_i    => mosi,
      miso_o    => miso0,
      mode_i    => mode,
      tx_data_i => SLAVE0_TX,
      rx_data_o => slave0_rx
    );

  slave1 : entity work.spi_slave_model
    port map (
      cs_n_i    => cs_n(1),
      sclk_i    => sclk,
      mosi_i    => mosi,
      miso_o    => miso1,
      mode_i    => mode,
      tx_data_i => SLAVE1_TX,
      rx_data_o => slave1_rx
    );

  done_monitor : process (done, rst) is
  begin
    if rst = '1' then
      done_count <= 0;
    elsif rising_edge(done) then
      done_count <= done_count + 1;
    end if;
  end process;

  stim : process is
    variable expected_done : natural;

    procedure do_transfer(slave    : natural;
                          tx_byte  : std_logic_vector(7 downto 0);
                          exp_miso : std_logic_vector(7 downto 0)) is
    begin
      data_in <= tx_byte;
      if slave = 0 then
        cs_sel <= "01";
      else
        cs_sel <= "10";
      end if;
      wait_cycles(clk, 1);

      expected_done := done_count + 1;
      start <= '1';
      wait_cycles(clk, 1);
      start <= '0';
      wait_cycles(clk, 2);

      check_eq(busy, '1', "busy while transferring");
      if slave = 0 then
        check_eq(cs_n, "10", "slave 0 chip select active");
      else
        check_eq(cs_n, "01", "slave 1 chip select active");
      end if;

      wait until done_count = expected_done for 1 ms;
      wait for 1 ns;

      check_eq(busy, '0', "busy clears after done");
      check_eq(cs_n, "11", "all chip selects released");
      check_eq(data_out, exp_miso, "received MISO byte");
    end procedure;

  begin
    report "TC1: reset and idle state" severity note;
    wait_cycles(clk, 3);
    rst <= '0';
    wait_cycles(clk, 1);
    check_eq(busy, '0', "not busy after reset");
    check_eq(done, '0', "no done pulse after reset");
    check_eq(cs_n, "11", "chip selects inactive after reset");
    check_eq(sclk, '0', "SCLK idles low for CPOL=0");
    check_eq(data_out, x"00", "data output cleared by reset");

    report "TC2: mode 0 (CPOL=0, CPHA=0), slave 0" severity note;
    mode <= "00";
    wait_cycles(clk, 2);
    check_eq(sclk, '0', "mode 0 idle SCLK is low");
    do_transfer(0, x"5A", SLAVE0_TX);
    check_eq(slave0_rx, x"5A", "slave 0 received the MOSI byte");
    check_eq(slave1_rx, x"00", "slave 1 stayed deselected");
    check_eq(sclk, '0', "SCLK returned to idle low");

    report "TC3: mode 1 (CPOL=0, CPHA=1), slave 1" severity note;
    mode <= "01";
    wait_cycles(clk, 2);
    check_eq(sclk, '0', "mode 1 idle SCLK is low");
    do_transfer(1, x"C3", SLAVE1_TX);
    check_eq(slave1_rx, x"C3", "slave 1 received the MOSI byte");
    check_eq(slave0_rx, x"5A", "slave 0 data is unchanged");
    check_eq(sclk, '0', "SCLK returned to idle low");

    report "TC4: mode 2 (CPOL=1, CPHA=0), slave 0" severity note;
    mode <= "10";
    wait_cycles(clk, 2);
    check_eq(sclk, '1', "mode 2 idle SCLK is high");
    do_transfer(0, x"0F", SLAVE0_TX);
    check_eq(slave0_rx, x"0F", "slave 0 received the MOSI byte");
    check_eq(slave1_rx, x"C3", "slave 1 data is unchanged");
    check_eq(sclk, '1', "SCLK returned to idle high");

    report "TC5: mode 3 (CPOL=1, CPHA=1), slave 1" severity note;
    mode <= "11";
    wait_cycles(clk, 2);
    check_eq(sclk, '1', "mode 3 idle SCLK is high");
    do_transfer(1, x"F0", SLAVE1_TX);
    check_eq(slave1_rx, x"F0", "slave 1 received the MOSI byte");
    check_eq(slave0_rx, x"0F", "slave 0 data is unchanged");
    check_eq(sclk, '1', "SCLK returned to idle high");

    report "TC6: start is ignored while busy" severity note;
    mode <= "00";
    wait_cycles(clk, 2);

    data_in <= x"11";
    cs_sel  <= "01";
    wait_cycles(clk, 1);

    expected_done := done_count + 1;
    start <= '1';
    wait_cycles(clk, 1);
    start <= '0';
    wait_cycles(clk, 2);

    check_eq(busy, '1', "transfer started");
    check_eq(cs_n, "10", "slave 0 selected for the real transfer");

    -- A second start with a different slave and byte must be ignored.
    data_in <= x"EE";
    cs_sel  <= "10";
    start   <= '1';
    wait_cycles(clk, 1);
    start <= '0';

    check_eq(cs_n, "10", "spurious start did not switch chip select");
    wait_cycles(clk, 2);
    check_eq(busy, '1', "still busy after the spurious start");

    wait until done_count = expected_done for 1 ms;
    wait for 1 ns;

    check_eq(data_out, SLAVE0_TX, "original MISO byte survived");
    check_eq(slave0_rx, x"11", "slave 0 received the original byte");
    check_eq(slave1_rx, x"F0", "slave 1 was not touched");
    check_eq(done_count, expected_done, "exactly one done pulse");
    check_eq(busy, '0', "busy clears after the real transfer");

    test_summary("spi_master");
  end process;

  watchdog : process is
  begin
    wait for TIMEOUT;
    fail("SPI testbench timeout");
  end process;

end architecture;
