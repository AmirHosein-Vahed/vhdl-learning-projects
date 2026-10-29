-- =============================================================================
-- seven_seg -- hexadecimal to active-low 7-segment decoder
--
-- Output bit order is "g f e d c b a" (bit 6 = g, bit 0 = a).  A '0' in a bit
-- turns that segment on, which is the usual common-anode wiring.  Keeping the
-- table as a case statement makes it obvious and lets synthesis build a small
-- ROM/LUT; it also avoids doing arithmetic on segment patterns.
-- =============================================================================
library ieee;
use ieee.std_logic_1164.all;

entity seven_seg is
  port (
    hex_i : in  std_logic_vector(3 downto 0);
    seg_o : out std_logic_vector(6 downto 0)  -- g f e d c b a, active low
  );
end entity;

architecture rtl of seven_seg is
begin

  with hex_i select
    seg_o <= "1000000" when x"0",  -- 0
             "1111001" when x"1",  -- 1
             "0100100" when x"2",  -- 2
             "0110000" when x"3",  -- 3
             "0011001" when x"4",  -- 4
             "0010010" when x"5",  -- 5
             "0000010" when x"6",  -- 6
             "1111000" when x"7",  -- 7
             "0000000" when x"8",  -- 8
             "0010000" when x"9",  -- 9
             "0001000" when x"A",  -- A
             "0000011" when x"B",  -- b
             "1000110" when x"C",  -- C
             "0100001" when x"D",  -- d
             "0000110" when x"E",  -- E
             "0001110" when others; -- F

end architecture;
