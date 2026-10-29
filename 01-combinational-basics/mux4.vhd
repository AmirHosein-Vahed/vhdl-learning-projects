-- =============================================================================
-- mux4 -- parameterized 4:1 multiplexer
--
-- A selected signal assignment is the clearest way to express a small mux.
-- Note the "when others" branch: it keeps the logic total even though the
-- select type has exactly four values.  Synthesis maps this to LUTs, and the
-- same pattern scales to wider buses.
-- =============================================================================
library ieee;
use ieee.std_logic_1164.all;

entity mux4 is
  generic (
    WIDTH : positive := 8
  );
  port (
    sel_i : in  std_logic_vector(1 downto 0);
    d0_i  : in  std_logic_vector(WIDTH - 1 downto 0);
    d1_i  : in  std_logic_vector(WIDTH - 1 downto 0);
    d2_i  : in  std_logic_vector(WIDTH - 1 downto 0);
    d3_i  : in  std_logic_vector(WIDTH - 1 downto 0);
    y_o   : out std_logic_vector(WIDTH - 1 downto 0)
  );
end entity;

architecture rtl of mux4 is
begin

  with sel_i select
    y_o <= d0_i when "00",
           d1_i when "01",
           d2_i when "10",
           d3_i when others;

end architecture;
