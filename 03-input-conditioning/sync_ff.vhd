-- =============================================================================
-- sync_ff -- multi-stage synchronizer for a single asynchronous input
--
-- Two flops are the usual minimum for a single-bit control signal crossing
-- into a clock domain.  The first flop may go metastable; the second one gives
-- the metastability a full clock period to resolve before downstream logic
-- sees it.  This does not make the signal safe for multi-bit buses: use a
-- handshake or a FIFO for those (see project 05).
-- =============================================================================
library ieee;
use ieee.std_logic_1164.all;

entity sync_ff is
  generic (
    STAGES : positive := 2
  );
  port (
    clk_i   : in  std_logic;
    rst_i   : in  std_logic;
    async_i : in  std_logic;
    sync_o  : out std_logic
  );
end entity;

architecture rtl of sync_ff is

  signal chain : std_logic_vector(STAGES - 1 downto 0) := (others => '0');

begin

  assert STAGES >= 2
    report "sync_ff: at least two stages are required"
    severity failure;

  process (clk_i) is
  begin
    if rising_edge(clk_i) then
      if rst_i = '1' then
        chain <= (others => '0');
      else
        chain(0) <= async_i;
        for i in 1 to STAGES - 1 loop
          chain(i) <= chain(i - 1);
        end loop;
      end if;
    end if;
  end process;

  sync_o <= chain(STAGES - 1);

end architecture;
