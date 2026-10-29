-- =============================================================================
-- sync_fifo -- parameterized synchronous FIFO with count and almost flags
--
-- Both ports are synchronous.  A write is accepted when wr_en_i is high and
-- full_o is low; a read is accepted when rd_en_i is high and empty_o is low.
-- The read data is registered, so dout_o is valid on the cycle *after* the
-- read edge.  That one-cycle latency is the usual "standard FIFO" contract
-- and maps cleanly to block RAM.
--
-- DEPTH must be a power of two so the pointers wrap naturally at 2**ADDR_WIDTH
-- and the full/empty comparison only needs the element count.  Simultaneous
-- read and write is supported: the count stays constant, the oldest word is
-- returned, and the new word is stored.
-- =============================================================================
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.util_pkg.all;

entity sync_fifo is
  generic (
    WIDTH              : positive := 8;
    DEPTH              : positive := 16;
    -- Thresholds are inclusive: almost_full_o asserts when count >= level.
    -- The defaults assume DEPTH >= 4; override them for shallower FIFOs.
    ALMOST_FULL_LEVEL  : natural  := DEPTH - 2;
    ALMOST_EMPTY_LEVEL : natural  := 2
  );
  port (
    clk_i          : in  std_logic;
    rst_i          : in  std_logic;
    wr_en_i        : in  std_logic;
    rd_en_i        : in  std_logic;
    din_i          : in  std_logic_vector(WIDTH - 1 downto 0);
    dout_o         : out std_logic_vector(WIDTH - 1 downto 0);
    full_o         : out std_logic;
    empty_o        : out std_logic;
    almost_full_o  : out std_logic;
    almost_empty_o : out std_logic;
    count_o        : out std_logic_vector(clog2(DEPTH + 1) - 1 downto 0)
  );
end entity;

architecture rtl of sync_fifo is

  constant ADDR_WIDTH  : positive := clog2(DEPTH);
  constant COUNT_WIDTH : positive := clog2(DEPTH + 1);

  type mem_t is array (0 to DEPTH - 1) of std_logic_vector(WIDTH - 1 downto 0);

  -- The memory itself is intentionally not reset.  Block RAMs do not have a
  -- reset, and the empty flag prevents reading unwritten locations.
  signal mem    : mem_t := (others => (others => '0'));
  signal wr_ptr : unsigned(ADDR_WIDTH - 1 downto 0) := (others => '0');
  signal rd_ptr : unsigned(ADDR_WIDTH - 1 downto 0) := (others => '0');
  signal count  : unsigned(COUNT_WIDTH - 1 downto 0) := (others => '0');
  signal dout_r : std_logic_vector(WIDTH - 1 downto 0) := (others => '0');

  signal full_s  : std_logic;
  signal empty_s : std_logic;
  signal wr_ok   : std_logic;
  signal rd_ok   : std_logic;

begin

  assert WIDTH >= 1
    report "sync_fifo: WIDTH must be at least 1"
    severity failure;
  assert DEPTH >= 2
    report "sync_fifo: DEPTH must be at least 2"
    severity failure;
  assert is_power_of_two(DEPTH)
    report "sync_fifo: DEPTH must be a power of two"
    severity failure;
  assert ALMOST_FULL_LEVEL >= 1 and ALMOST_FULL_LEVEL <= DEPTH
    report "sync_fifo: ALMOST_FULL_LEVEL must be in 1..DEPTH"
    severity failure;
  assert ALMOST_EMPTY_LEVEL <= DEPTH
    report "sync_fifo: ALMOST_EMPTY_LEVEL must be in 0..DEPTH"
    severity failure;

  -- Flags are combinational functions of the registered element count, so
  -- they are stable for the whole cycle and can drive backpressure directly.
  full_s  <= '1' when count = DEPTH else '0';
  empty_s <= '1' when count = 0 else '0';

  -- A request is only "ok" when the opposite flag allows it.  Computing these
  -- once keeps the write, read, and count updates consistent.
  wr_ok <= '1' when wr_en_i = '1' and full_s = '0' else '0';
  rd_ok <= '1' when rd_en_i = '1' and empty_s = '0' else '0';

  process (clk_i) is
  begin
    if rising_edge(clk_i) then
      if rst_i = '1' then
        wr_ptr <= (others => '0');
        rd_ptr <= (others => '0');
        count  <= (others => '0');
        dout_r <= (others => '0');
      else
        if wr_ok = '1' then
          mem(to_integer(wr_ptr)) <= din_i;
          wr_ptr <= wr_ptr + 1;
        end if;

        if rd_ok = '1' then
          -- Read-before-write: on a simultaneous access while full, the write
          -- is blocked, but the read still returns the oldest word before the
          -- slot is reused.
          dout_r <= mem(to_integer(rd_ptr));
          rd_ptr <= rd_ptr + 1;
        end if;

        -- Count changes only when exactly one side moves.  Simultaneous
        -- read/write leaves the occupancy unchanged.
        if wr_ok = '1' and rd_ok = '0' then
          count <= count + 1;
        elsif rd_ok = '1' and wr_ok = '0' then
          count <= count - 1;
        end if;
      end if;
    end if;
  end process;

  dout_o         <= dout_r;
  count_o        <= std_logic_vector(count);
  full_o         <= full_s;
  empty_o        <= empty_s;
  almost_full_o  <= '1' when count >= ALMOST_FULL_LEVEL else '0';
  almost_empty_o <= '1' when count <= ALMOST_EMPTY_LEVEL else '0';

end architecture;
