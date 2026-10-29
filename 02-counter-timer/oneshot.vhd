-- =============================================================================
-- oneshot -- retriggerable monostable / pulse stretcher
--
-- A rising edge on trigger_i starts a pulse of PULSE_NS.  Another rising edge
-- while the pulse is active reloads the timer, so the pulse is retriggerable.
-- The input is expected to be already synchronized to clk_i; project 03 shows
-- the 2-flop synchronizer that should sit in front of an asynchronous button.
--
-- The width is defined in nanoseconds and converted to clock cycles with
-- ceiling division, so a pulse is never shorter than requested.  One cycle is
-- the minimum.
-- =============================================================================
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.util_pkg.all;

entity oneshot is
  generic (
    CLK_PERIOD_NS : positive := 10;
    PULSE_NS      : positive := 100
  );
  port (
    clk_i     : in  std_logic;
    rst_i     : in  std_logic;
    trigger_i : in  std_logic;
    pulse_o   : out std_logic
  );
end entity;

architecture rtl of oneshot is

  constant PULSE_CYCLES : positive :=
    (PULSE_NS + CLK_PERIOD_NS - 1) / CLK_PERIOD_NS;
  constant CNT_WIDTH    : positive := clog2(PULSE_CYCLES + 1);

  signal remaining : unsigned(CNT_WIDTH - 1 downto 0) := (others => '0');
  signal trigger_d : std_logic := '0';

begin

  assert PULSE_CYCLES >= 1
    report "oneshot: PULSE_NS must produce at least one clock cycle"
    severity failure;

  process (clk_i) is
  begin
    if rising_edge(clk_i) then
      if rst_i = '1' then
        remaining <= (others => '0');
        trigger_d <= '0';
      else
        trigger_d <= trigger_i;

        -- Edge detect, not level detect: holding the trigger high does not
        -- stretch the pulse forever.
        if trigger_i = '1' and trigger_d = '0' then
          remaining <= to_unsigned(PULSE_CYCLES, CNT_WIDTH);
        elsif remaining /= 0 then
          remaining <= remaining - 1;
        end if;
      end if;
    end if;
  end process;

  pulse_o <= '1' when remaining /= 0 else '0';

end architecture;
