-- =============================================================================
-- uart_tb -- loopback, framing-error, and false-start tests
--
-- Generics are scaled down so simulation stays fast: 1 MHz clock and
-- 62.5 kbaud give exactly 16 clocks per bit.  The loopback path connects the
-- transmitter directly to the receiver; the error tests drive the receiver
-- from a hand-built serial waveform instead.
-- =============================================================================
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;

library work;
use work.tb_pkg.all;

entity uart_tb is
end entity;

architecture sim of uart_tb is

  constant CLK_HZ    : positive := 1_000_000;
  constant BAUD      : positive := 62_500;
  constant CLK_PERIOD : time := 1 us;
  constant BIT_TIME   : time := 16 us;
  constant TIMEOUT    : time := 5 ms;

  signal clk        : std_logic := '0';
  signal rst        : std_logic := '1';

  signal tx_data    : std_logic_vector(7 downto 0) := (others => '0');
  signal tx_valid   : std_logic := '0';
  signal tx_ready   : std_logic;
  signal tx_line    : std_logic;

  signal loopback   : std_logic := '1';
  signal host_line  : std_logic := '1';
  signal rx_line    : std_logic;

  signal rx_data    : std_logic_vector(7 downto 0);
  signal rx_valid   : std_logic;
  signal rx_frame   : std_logic;

  signal valid_count : natural := 0;
  signal frame_count : natural := 0;
  signal last_rx     : std_logic_vector(7 downto 0) := (others => '0');

begin

  clk <= not clk after CLK_PERIOD / 2;

  rx_line <= tx_line when loopback = '1' else host_line;

  dut_tx : entity work.uart_tx
    generic map (
      CLK_HZ => CLK_HZ,
      BAUD   => BAUD
    )
    port map (
      clk_i   => clk,
      rst_i   => rst,
      data_i  => tx_data,
      valid_i => tx_valid,
      ready_o => tx_ready,
      tx_o    => tx_line
    );

  dut_rx : entity work.uart_rx
    generic map (
      CLK_HZ => CLK_HZ,
      BAUD   => BAUD
    )
    port map (
      clk_i       => clk,
      rst_i       => rst,
      rx_i        => rx_line,
      data_o      => rx_data,
      valid_o     => rx_valid,
      frame_err_o => rx_frame
    );

  -- Count one-cycle receiver pulses.  The raw-frame stimulus can finish after
  -- the pulse, so event counters are safer than waiting on the live flag.
  valid_monitor : process (rx_valid, rst) is
  begin
    if rst = '1' then
      valid_count <= 0;
      last_rx     <= (others => '0');
    elsif rising_edge(rx_valid) then
      valid_count <= valid_count + 1;
      last_rx     <= rx_data;
    end if;
  end process;

  frame_monitor : process (rx_frame, rst) is
  begin
    if rst = '1' then
      frame_count <= 0;
    elsif rising_edge(rx_frame) then
      frame_count <= frame_count + 1;
    end if;
  end process;

  stim : process is
    type byte_array_t is array (0 to 3) of std_logic_vector(7 downto 0);
    constant PATTERN : byte_array_t := (x"55", x"A3", x"00", x"FF");

    -- Send one raw 8N1 frame on host_line.  stop_bit = '0' creates a framing
    -- error; this is also how a break condition looks to the receiver.
    procedure send_raw(data : std_logic_vector(7 downto 0);
                       stop_bit : std_logic) is
    begin
      host_line <= '0';
      wait for BIT_TIME;
      for i in 0 to 7 loop
        host_line <= data(i);
        wait for BIT_TIME;
      end loop;
      host_line <= stop_bit;
      wait for BIT_TIME;
      host_line <= '1';
      wait for BIT_TIME;
    end procedure;
  begin
    report "TC1: reset and idle line" severity note;
    wait_cycles(clk, 3);
    rst <= '0';
    wait_cycles(clk, 2);
    check_eq(tx_ready, '1', "transmitter ready after reset");
    check_eq(tx_line, '1', "idle UART line is high");

    report "TC2: loopback bytes" severity note;
    for i in PATTERN'range loop
      while tx_ready = '0' loop
        wait_cycles(clk, 1);
      end loop;

      tx_data  <= PATTERN(i);
      tx_valid <= '1';
      wait_cycles(clk, 1);
      tx_valid <= '0';

      wait until valid_count = i + 1 for 2 ms;
      wait for 1 ns;
      check_eq(last_rx, PATTERN(i), "loopback byte " & integer'image(i));
      check_eq(frame_count, 0, "no framing error for byte " & integer'image(i));

      -- Wait for the transmitter to return to idle before the next byte.
      while tx_ready = '0' loop
        wait_cycles(clk, 1);
      end loop;
    end loop;

    report "TC3: framing error on a bad stop bit" severity note;
    loopback <= '0';
    wait_cycles(clk, 3);
    send_raw(x"5A", '0');
    wait for 1 ns;
    check_eq(frame_count, 1, "zero stop bit reports framing error");
    check_eq(valid_count, 4, "framing error does not assert valid");
    wait_cycles(clk, 5);

    report "TC4: false start glitch is rejected" severity note;
    host_line <= '0';
    wait for 4 us;  -- shorter than half a bit
    host_line <= '1';
    wait for 3 * BIT_TIME;
    check_eq(rx_valid, '0', "short glitch produces no byte");
    check_eq(rx_frame, '0', "short glitch produces no framing error");
    check_eq(valid_count, 4, "short glitch does not increment valid count");
    check_eq(frame_count, 1, "short glitch does not increment frame count");

    report "TC5: receiver accepts a valid raw frame" severity note;
    send_raw(x"C3", '1');
    wait for 1 ns;
    check_eq(valid_count, 5, "raw frame increments valid count");
    check_eq(last_rx, x"C3", "raw frame data");
    check_eq(frame_count, 1, "raw frame has a valid stop bit");

    test_summary("uart");
  end process;

  watchdog : process is
  begin
    wait for TIMEOUT;
    fail("UART testbench timeout");
  end process;

end architecture;
