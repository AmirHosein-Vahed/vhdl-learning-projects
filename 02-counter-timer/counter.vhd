-- =============================================================================
-- counter -- loadable, enabled, up/down counter
--
-- Priority is reset > load > enable > hold.  That ordering is a deliberate
-- design decision: a synchronous load must win over counting, otherwise a
-- loader and the free-running counter can disagree for one cycle.  The
-- terminal output is combinational and tells the surrounding logic that the
-- *next* enabled edge would wrap.
-- =============================================================================
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity counter is
  generic (
    WIDTH : positive := 8
  );
  port (
    clk_i      : in  std_logic;
    rst_i      : in  std_logic;
    en_i       : in  std_logic;
    up_i       : in  std_logic;  -- '1' = count up, '0' = count down
    load_i     : in  std_logic;
    load_val_i : in  std_logic_vector(WIDTH - 1 downto 0);
    count_o    : out std_logic_vector(WIDTH - 1 downto 0);
    terminal_o : out std_logic
  );
end entity;

architecture rtl of counter is

  constant ALL_ONES  : unsigned(WIDTH - 1 downto 0) := (others => '1');
  constant ALL_ZEROS : unsigned(WIDTH - 1 downto 0) := (others => '0');

  signal count : unsigned(WIDTH - 1 downto 0) := (others => '0');

begin

  process (clk_i) is
  begin
    if rising_edge(clk_i) then
      if rst_i = '1' then
        count <= (others => '0');
      elsif load_i = '1' then
        count <= unsigned(load_val_i);
      elsif en_i = '1' then
        if up_i = '1' then
          count <= count + 1;  -- unsigned wraps modulo 2**WIDTH
        else
          count <= count - 1;
        end if;
      end if;
    end if;
  end process;

  count_o <= std_logic_vector(count);

  -- "terminal" means the counter is at the end it is currently counting
  -- toward.  It is not a registered flag, so it changes immediately after a
  -- load or a wrap.
  terminal_o <= '1' when (up_i = '1' and count = ALL_ONES) or
                         (up_i = '0' and count = ALL_ZEROS)
                else '0';

end architecture;
