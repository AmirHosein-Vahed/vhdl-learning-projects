-- =============================================================================
-- input_conditioning -- synchronize, debounce, and edge-detect a raw input
--
-- This is the block that should sit between an industrial switch/button and
-- the rest of the FPGA logic.  The order matters:
--   1. synchronize the asynchronous pin,
--   2. remove contact bounce,
--   3. produce one-cycle rise/fall events.
--
-- The debouncer itself is not a safety function.  An emergency stop must use
-- hard-wired safety hardware, not FPGA logic.
-- =============================================================================
library ieee;
use ieee.std_logic_1164.all;

entity input_conditioning is
  generic (
    CLK_PERIOD_NS : positive := 10;
    DEBOUNCE_NS   : positive := 100
  );
  port (
    clk_i     : in  std_logic;
    rst_i     : in  std_logic;
    raw_i     : in  std_logic;
    clean_o   : out std_logic;
    rise_o    : out std_logic;
    fall_o    : out std_logic
  );
end entity;

architecture rtl of input_conditioning is

  signal synchronized : std_logic;
  signal debounced    : std_logic;

begin

  u_sync : entity work.sync_ff
    generic map (STAGES => 2)
    port map (
      clk_i   => clk_i,
      rst_i   => rst_i,
      async_i => raw_i,
      sync_o  => synchronized
    );

  u_debounce : entity work.debounce
    generic map (
      CLK_PERIOD_NS => CLK_PERIOD_NS,
      DEBOUNCE_NS   => DEBOUNCE_NS
    )
    port map (
      clk_i       => clk_i,
      rst_i       => rst_i,
      raw_i       => synchronized,
      debounced_o => debounced
    );

  u_edge : entity work.edge_detect
    port map (
      clk_i   => clk_i,
      rst_i   => rst_i,
      level_i => debounced,
      rise_o  => rise_o,
      fall_o  => fall_o
    );

  clean_o <= debounced;

end architecture;
