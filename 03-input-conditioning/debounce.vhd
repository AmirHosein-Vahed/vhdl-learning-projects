-- =============================================================================
-- debounce -- counter-based switch debouncer
--
-- The output only follows the input after the input has been stable for
-- DEBOUNCE_NS.  Any change restarts the counter, so contact bounce and short
-- glitches never reach the output.  Feed this block a synchronized input
-- (sync_ff) when the switch is asynchronous to clk_i.
-- =============================================================================
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.util_pkg.all;

entity debounce is
  generic (
    CLK_PERIOD_NS : positive := 10;
    DEBOUNCE_NS   : positive := 100
  );
  port (
    clk_i       : in  std_logic;
    rst_i       : in  std_logic;
    raw_i       : in  std_logic;
    debounced_o : out std_logic
  );
end entity;

architecture rtl of debounce is

  constant DEBOUNCE_CYCLES : positive :=
    (DEBOUNCE_NS + CLK_PERIOD_NS - 1) / CLK_PERIOD_NS;
  constant CNT_WIDTH : positive := clog2(DEBOUNCE_CYCLES + 1);
  constant CNT_MAX   : unsigned(CNT_WIDTH - 1 downto 0) :=
    to_unsigned(DEBOUNCE_CYCLES - 1, CNT_WIDTH);

  signal count  : unsigned(CNT_WIDTH - 1 downto 0) := (others => '0');
  signal stable : std_logic := '0';

begin

  assert DEBOUNCE_CYCLES >= 1
    report "debounce: DEBOUNCE_NS must be at least one clock period"
    severity failure;

  process (clk_i) is
  begin
    if rising_edge(clk_i) then
      if rst_i = '1' then
        count  <= (others => '0');
        stable <= '0';
      elsif raw_i = stable then
        -- Same level as the output: nothing to debounce, keep the timer ready.
        count <= (others => '0');
      elsif count = CNT_MAX then
        stable <= raw_i;
        count  <= (others => '0');
      else
        count <= count + 1;
      end if;
    end if;
  end process;

  debounced_o <= stable;

end architecture;
