-- =============================================================================
-- uart_rx -- 8N1 UART receiver with 16x oversampling
--
-- The external rx_i is asynchronous, so it is synchronized with two flops
-- before any logic uses it.  A free-running tick counter divides the clock by
-- TICK_DIV; os_cnt counts 0..15 ticks per bit, and the data is sampled at
-- os_cnt = 8, i.e. in the middle of the bit.
--
-- valid_o and frame_err_o are one-clock pulses.  data_o holds the last good
-- byte.  A zero stop bit is reported as a framing error and does not assert
-- valid_o.
-- =============================================================================
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.uart_pkg.all;

entity uart_rx is
  generic (
    CLK_HZ : positive := 50_000_000;
    BAUD   : positive := 115_200
  );
  port (
    clk_i       : in  std_logic;
    rst_i       : in  std_logic;
    rx_i        : in  std_logic;
    data_o      : out std_logic_vector(7 downto 0);
    valid_o     : out std_logic;
    frame_err_o : out std_logic
  );
end entity;

architecture rtl of uart_rx is

  constant TICK_DIV : positive := calc_tick_divisor(CLK_HZ, BAUD);

  type state_t is (IDLE, START, DATA, STOP);

  signal state       : state_t := IDLE;
  signal rx_meta     : std_logic := '1';
  signal rx_sync     : std_logic := '1';
  signal clk_cnt     : natural range 0 to TICK_DIV - 1 := 0;
  signal tick        : std_logic := '0';
  signal os_cnt      : natural range 0 to OVERSAMPLE - 1 := 0;
  signal bit_idx     : natural range 0 to 7 := 0;
  signal shift       : std_logic_vector(7 downto 0) := (others => '0');
  signal data_r      : std_logic_vector(7 downto 0) := (others => '0');

begin

  process (clk_i) is
  begin
    if rising_edge(clk_i) then
      if rst_i = '1' then
        state       <= IDLE;
        rx_meta     <= '1';
        rx_sync     <= '1';
        clk_cnt     <= 0;
        tick        <= '0';
        os_cnt      <= 0;
        bit_idx     <= 0;
        shift       <= (others => '0');
        data_r      <= (others => '0');
        data_o      <= (others => '0');
        valid_o     <= '0';
        frame_err_o <= '0';
      else
        -- Two-flop synchronizer for the asynchronous receive pin.
        rx_meta <= rx_i;
        rx_sync <= rx_meta;

        -- Free-running 16x tick.  Resetting clk_cnt when a start edge is
        -- found aligns the first sample to the middle of the start bit.
        if clk_cnt = TICK_DIV - 1 then
          clk_cnt <= 0;
          tick    <= '1';
        else
          clk_cnt <= clk_cnt + 1;
          tick    <= '0';
        end if;

        -- Defaults make both flags exactly one clock wide.
        valid_o     <= '0';
        frame_err_o <= '0';

        case state is
          when IDLE =>
            if rx_sync = '0' then
              state   <= START;
              clk_cnt <= 0;
              os_cnt  <= 0;
            end if;

          when START =>
            if tick = '1' then
              if os_cnt = OVERSAMPLE - 1 then
                os_cnt <= 0;
              else
                os_cnt <= os_cnt + 1;
              end if;

              -- Half a bit after the falling edge: verify it is a real start
              -- bit and not a short glitch.
              if os_cnt = OVERSAMPLE / 2 then
                if rx_sync = '0' then
                  state   <= DATA;
                  bit_idx <= 0;
                else
                  state <= IDLE;
                end if;
              end if;
            end if;

          when DATA =>
            if tick = '1' then
              if os_cnt = OVERSAMPLE - 1 then
                os_cnt <= 0;
              else
                os_cnt <= os_cnt + 1;
              end if;

              if os_cnt = OVERSAMPLE / 2 then
                shift(bit_idx) <= rx_sync;  -- LSB arrives first
                if bit_idx = 7 then
                  state <= STOP;
                else
                  bit_idx <= bit_idx + 1;
                end if;
              end if;
            end if;

          when STOP =>
            if tick = '1' then
              if os_cnt = OVERSAMPLE - 1 then
                os_cnt <= 0;
              else
                os_cnt <= os_cnt + 1;
              end if;

              if os_cnt = OVERSAMPLE / 2 then
                if rx_sync = '1' then
                  data_o  <= shift;
                  valid_o <= '1';
                else
                  frame_err_o <= '1';
                end if;
                state <= IDLE;
              end if;
            end if;
        end case;
      end if;
    end if;
  end process;

end architecture;
