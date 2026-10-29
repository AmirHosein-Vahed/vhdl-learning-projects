-- =============================================================================
-- edge_detect -- one-cycle rising/falling pulse generator
--
-- Both outputs are registered/combinational in the clk_i domain.  A one-cycle
-- pulse is convenient for "do this once" actions: loading a counter, starting
-- a transaction, or incrementing a status register.
-- =============================================================================
library ieee;
use ieee.std_logic_1164.all;

entity edge_detect is
  port (
    clk_i   : in  std_logic;
    rst_i   : in  std_logic;
    level_i : in  std_logic;
    rise_o  : out std_logic;
    fall_o  : out std_logic
  );
end entity;

architecture rtl of edge_detect is

  signal level_d : std_logic := '0';

begin

  process (clk_i) is
  begin
    if rising_edge(clk_i) then
      if rst_i = '1' then
        level_d <= '0';
      else
        level_d <= level_i;
      end if;
    end if;
  end process;

  rise_o <= '1' when level_i = '1' and level_d = '0' else '0';
  fall_o <= '1' when level_i = '0' and level_d = '1' else '0';

end architecture;
