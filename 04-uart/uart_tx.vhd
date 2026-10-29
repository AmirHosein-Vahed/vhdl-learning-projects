-- =============================================================================
-- uart_tx -- 8N1 UART transmitter
--
-- One start bit, eight data bits (LSB first), one stop bit, no parity.  The
-- bit period is derived from CLK_HZ/BAUD; both generics must match the real
-- clock for the requested baud rate.
--
-- ready_o is high while idle.  A one-cycle valid_i starts a transaction; the
-- caller must not present another byte until ready_o returns high.
-- =============================================================================
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.uart_pkg.all;

entity uart_tx is
  generic (
    CLK_HZ : positive := 50_000_000;
    BAUD   : positive := 115_200
  );
  port (
    clk_i   : in  std_logic;
    rst_i   : in  std_logic;
    data_i  : in  std_logic_vector(7 downto 0);
    valid_i : in  std_logic;
    ready_o : out std_logic;
    tx_o    : out std_logic
  );
end entity;

architecture rtl of uart_tx is

  constant BIT_PERIOD : positive := calc_bit_period(CLK_HZ, BAUD);

  type state_t is (IDLE, START, DATA, STOP);

  signal state    : state_t := IDLE;
  signal shift    : std_logic_vector(7 downto 0) := (others => '0');
  signal bit_idx  : natural range 0 to 7 := 0;
  signal baud_cnt : natural range 0 to BIT_PERIOD - 1 := 0;
  signal tx_r     : std_logic := '1';

begin

  process (clk_i) is
  begin
    if rising_edge(clk_i) then
      if rst_i = '1' then
        state    <= IDLE;
        shift    <= (others => '0');
        bit_idx  <= 0;
        baud_cnt <= 0;
        tx_r     <= '1';
      else
        case state is
          when IDLE =>
            tx_r     <= '1';
            baud_cnt <= 0;
            if valid_i = '1' then
              shift <= data_i;
              state <= START;
            end if;

          when START =>
            -- Drive the start bit for exactly one bit period.
            tx_r <= '0';
            if baud_cnt = BIT_PERIOD - 1 then
              baud_cnt <= 0;
              bit_idx  <= 0;
              state    <= DATA;
            else
              baud_cnt <= baud_cnt + 1;
            end if;

          when DATA =>
            -- shift(0) is the next LSB; the shift happens at the bit boundary.
            tx_r <= shift(0);
            if baud_cnt = BIT_PERIOD - 1 then
              baud_cnt <= 0;
              if bit_idx = 7 then
                state <= STOP;
              else
                bit_idx <= bit_idx + 1;
                shift   <= shift(1) & shift(7 downto 1);
              end if;
            else
              baud_cnt <= baud_cnt + 1;
            end if;

          when STOP =>
            tx_r <= '1';
            if baud_cnt = BIT_PERIOD - 1 then
              baud_cnt <= 0;
              state    <= IDLE;
            else
              baud_cnt <= baud_cnt + 1;
            end if;
        end case;
      end if;
    end if;
  end process;

  ready_o <= '1' when state = IDLE else '0';
  tx_o    <= tx_r;

end architecture;
