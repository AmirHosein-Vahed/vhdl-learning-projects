-- =============================================================================
-- prio_enc8 -- 8:3 priority encoder, highest input bit wins
--
-- Priority encoders are common in interrupt controllers and arbiters.  The
-- if/elsif chain is intentionally written from bit 7 down to bit 0: the first
-- true branch wins, so no explicit masking is needed.  "valid_o" distinguishes
-- "input 0 is asserted" (index 000, valid 1) from "no input asserted"
-- (index 000, valid 0).
-- =============================================================================
library ieee;
use ieee.std_logic_1164.all;

entity prio_enc8 is
  port (
    din_i   : in  std_logic_vector(7 downto 0);
    valid_o : out std_logic;
    index_o : out std_logic_vector(2 downto 0)
  );
end entity;

architecture rtl of prio_enc8 is
begin

  process (all) is
  begin
    -- Safe defaults prevent a latch and define the all-zero case.
    valid_o <= '0';
    index_o <= "000";

    if din_i(7) = '1' then
      valid_o <= '1';
      index_o <= "111";
    elsif din_i(6) = '1' then
      valid_o <= '1';
      index_o <= "110";
    elsif din_i(5) = '1' then
      valid_o <= '1';
      index_o <= "101";
    elsif din_i(4) = '1' then
      valid_o <= '1';
      index_o <= "100";
    elsif din_i(3) = '1' then
      valid_o <= '1';
      index_o <= "011";
    elsif din_i(2) = '1' then
      valid_o <= '1';
      index_o <= "010";
    elsif din_i(1) = '1' then
      valid_o <= '1';
      index_o <= "001";
    elsif din_i(0) = '1' then
      valid_o <= '1';
      index_o <= "000";
    end if;
  end process;

end architecture;
