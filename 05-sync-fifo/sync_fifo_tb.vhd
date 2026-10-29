-- =============================================================================
-- sync_fifo_tb -- directed tests plus a randomized scoreboard
--
-- The testbench keeps a software queue that mirrors the FIFO.  Every accepted
-- read is compared against the queue head, and the count/flags are checked
-- after each operation.  A 16-bit LFSR makes the stress run deterministic.
--
-- The DUT has a registered read output, so checks happen after the read edge
-- (wait_cycles returns 1 ns after the rising edge).
-- =============================================================================
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;

library work;
use work.tb_pkg.all;
use work.util_pkg.all;

entity sync_fifo_tb is
end entity;

architecture sim of sync_fifo_tb is

  constant WIDTH              : positive := 8;
  constant DEPTH              : positive := 16;
  constant ALMOST_FULL_LEVEL  : natural  := 14;
  constant ALMOST_EMPTY_LEVEL : natural  := 2;
  constant COUNT_WIDTH        : positive := clog2(DEPTH + 1);
  constant CLK_PERIOD         : time     := 10 ns;
  constant TIMEOUT            : time     := 5 ms;

  type queue_t is array (0 to DEPTH - 1) of std_logic_vector(WIDTH - 1 downto 0);

  signal clk          : std_logic := '0';
  signal rst          : std_logic := '1';
  signal wr_en        : std_logic := '0';
  signal rd_en        : std_logic := '0';
  signal din          : std_logic_vector(WIDTH - 1 downto 0) := (others => '0');
  signal dout         : std_logic_vector(WIDTH - 1 downto 0);
  signal full         : std_logic;
  signal empty        : std_logic;
  signal almost_full  : std_logic;
  signal almost_empty : std_logic;
  signal count        : std_logic_vector(COUNT_WIDTH - 1 downto 0);

begin

  clk <= not clk after CLK_PERIOD / 2;

  dut : entity work.sync_fifo
    generic map (
      WIDTH              => WIDTH,
      DEPTH              => DEPTH,
      ALMOST_FULL_LEVEL  => ALMOST_FULL_LEVEL,
      ALMOST_EMPTY_LEVEL => ALMOST_EMPTY_LEVEL
    )
    port map (
      clk_i          => clk,
      rst_i          => rst,
      wr_en_i        => wr_en,
      rd_en_i        => rd_en,
      din_i          => din,
      dout_o         => dout,
      full_o         => full,
      empty_o        => empty,
      almost_full_o  => almost_full,
      almost_empty_o => almost_empty,
      count_o        => count
    );

  stim : process is
    variable queue    : queue_t := (others => (others => '0'));
    variable head     : natural := 0;
    variable tail     : natural := 0;
    variable qcount   : natural := 0;
    variable expected : std_logic_vector(WIDTH - 1 downto 0);
    variable data_v   : std_logic_vector(WIDTH - 1 downto 0);
    variable lfsr     : unsigned(15 downto 0) := x"BEEF";
    variable op       : natural;
    variable do_rd    : boolean;
    variable do_wr    : boolean;

    -- VHDL-2008 conditional expressions are not accepted as procedure
    -- actuals by GHDL, so convert booleans explicitly.
    function to_sl(cond : boolean) return std_logic is
    begin
      if cond then
        return '1';
      else
        return '0';
      end if;
    end function;

    -- Mirror-queue helpers.  They model the FIFO's accept/reject rules so the
    -- scoreboard can predict every accepted operation.
    procedure push(value : std_logic_vector(WIDTH - 1 downto 0)) is
    begin
      assert qcount < DEPTH report "TB queue overflow" severity failure;
      queue(tail) := value;
      tail := (tail + 1) mod DEPTH;
      qcount := qcount + 1;
    end procedure;

    procedure pop(value : out std_logic_vector(WIDTH - 1 downto 0)) is
    begin
      assert qcount > 0 report "TB queue underflow" severity failure;
      value := queue(head);
      head := (head + 1) mod DEPTH;
      qcount := qcount - 1;
    end procedure;

    procedure check_state(message : string) is
    begin
      check_eq(to_integer(unsigned(count)), qcount, message & " count");
      check_eq(full, to_sl(qcount = DEPTH), message & " full");
      check_eq(empty, to_sl(qcount = 0), message & " empty");
      check_eq(almost_full, to_sl(qcount >= ALMOST_FULL_LEVEL),
               message & " almost_full");
      check_eq(almost_empty, to_sl(qcount <= ALMOST_EMPTY_LEVEL),
               message & " almost_empty");
    end procedure;

    procedure write_word(value : std_logic_vector(WIDTH - 1 downto 0)) is
    begin
      din   <= value;
      wr_en <= '1';
      wait_cycles(clk, 1);
      wr_en <= '0';
      push(value);
    end procedure;

    procedure read_word(value : out std_logic_vector(WIDTH - 1 downto 0)) is
    begin
      rd_en <= '1';
      wait_cycles(clk, 1);
      rd_en <= '0';
      pop(value);
    end procedure;

  begin
    report "TC1: reset state" severity note;
    wait_cycles(clk, 3);
    rst <= '0';
    wait_cycles(clk, 1);
    check_state("after reset");
    check_eq(dout, x"00", "dout cleared by reset");

    report "TC2: single write and read" severity note;
    write_word(x"A5");
    check_state("after one write");
    read_word(expected);
    check_eq(dout, x"A5", "single word read data");
    check_state("after one read");

    report "TC3: fill to full and check almost_full" severity note;
    for i in 0 to DEPTH - 1 loop
      write_word(std_logic_vector(to_unsigned(i, WIDTH)));
      check_state("fill " & integer'image(i));
    end loop;
    check_eq(full, '1', "full asserted at DEPTH");
    check_eq(almost_full, '1', "almost_full asserted at DEPTH");

    report "TC4: write while full is ignored" severity note;
    din   <= x"EE";
    wr_en <= '1';
    wait_cycles(clk, 1);
    wr_en <= '0';
    check_state("write while full");

    report "TC5: drain in order" severity note;
    for i in 0 to DEPTH - 1 loop
      read_word(expected);
      check_eq(dout, std_logic_vector(to_unsigned(i, WIDTH)),
               "drain data " & integer'image(i));
      check_state("drain " & integer'image(i));
    end loop;
    check_eq(empty, '1', "empty asserted after drain");
    check_eq(full, '0', "full cleared after drain");

    report "TC6: read while empty is ignored" severity note;
    rd_en <= '1';
    wait_cycles(clk, 1);
    rd_en <= '0';
    check_state("read while empty");
    check_eq(dout, std_logic_vector(to_unsigned(DEPTH - 1, WIDTH)),
             "dout holds the last word when empty");

    report "TC7: simultaneous read and write keeps occupancy" severity note;
    write_word(x"11");
    write_word(x"22");
    write_word(x"33");
    check_state("three words");

    din   <= x"44";
    wr_en <= '1';
    rd_en <= '1';
    wait_cycles(clk, 1);
    wr_en <= '0';
    rd_en <= '0';
    check_eq(dout, x"11", "simultaneous read returns oldest word");
    pop(expected);
    push(x"44");
    check_state("simultaneous 1");

    din   <= x"55";
    wr_en <= '1';
    rd_en <= '1';
    wait_cycles(clk, 1);
    wr_en <= '0';
    rd_en <= '0';
    check_eq(dout, x"22", "simultaneous read returns next word");
    pop(expected);
    push(x"55");
    check_state("simultaneous 2");

    din   <= x"66";
    wr_en <= '1';
    rd_en <= '1';
    wait_cycles(clk, 1);
    wr_en <= '0';
    rd_en <= '0';
    check_eq(dout, x"33", "simultaneous read returns third word");
    pop(expected);
    push(x"66");
    check_state("simultaneous 3");

    read_word(expected);
    check_eq(dout, x"44", "post-simultaneous drain 1");
    check_state("post-simultaneous drain 1");
    read_word(expected);
    check_eq(dout, x"55", "post-simultaneous drain 2");
    check_state("post-simultaneous drain 2");
    read_word(expected);
    check_eq(dout, x"66", "post-simultaneous drain 3");
    check_state("post-simultaneous drain 3");

    report "TC8: full blocks the write but allows the read" severity note;
    for i in 0 to DEPTH - 1 loop
      write_word(std_logic_vector(to_unsigned(i, WIDTH)));
    end loop;
    check_eq(full, '1', "full before backpressure test");

    din   <= x"77";
    wr_en <= '1';
    rd_en <= '1';
    wait_cycles(clk, 1);
    wr_en <= '0';
    rd_en <= '0';
    check_eq(dout, x"00", "read at full returns oldest word");
    pop(expected);                    -- the write was blocked
    check_state("read-at-full");
    check_eq(full, '0', "full clears after the read");

    write_word(x"88");
    check_eq(full, '1', "refilled to full");

    for i in 1 to DEPTH - 1 loop
      read_word(expected);
      check_eq(dout, std_logic_vector(to_unsigned(i, WIDTH)),
               "post-full drain " & integer'image(i));
      check_state("post-full drain " & integer'image(i));
    end loop;
    read_word(expected);
    check_eq(dout, x"88", "new word survives the blocked write");
    check_state("post-full drain last");
    check_eq(empty, '1', "empty after post-full drain");

    report "TC9: randomized read/write scoreboard" severity note;
    rst <= '1';
    wait_cycles(clk, 2);
    rst <= '0';
    wait_cycles(clk, 1);
    head := 0;
    tail := 0;
    qcount := 0;

    for i in 0 to 399 loop
      -- 16-bit Galois LFSR; deterministic and good enough for stimulus.
      lfsr := lfsr(14 downto 0) &
              (lfsr(15) xor lfsr(13) xor lfsr(12) xor lfsr(10));
      op     := to_integer(lfsr(1 downto 0));
      data_v := std_logic_vector(lfsr(7 downto 0));

      din   <= data_v;
      wr_en <= '0';
      rd_en <= '0';
      do_rd := false;
      do_wr := false;

      case op is
        when 0 =>
          if qcount < DEPTH then
            do_wr := true;
          end if;
        when 1 =>
          if qcount > 0 then
            do_rd := true;
          end if;
        when 2 =>
          if qcount > 0 then
            do_rd := true;
          end if;
          if qcount < DEPTH then
            do_wr := true;
          end if;
        when others =>
          null;
      end case;

      if do_rd then
        expected := queue(head);
        rd_en <= '1';
      end if;
      if do_wr then
        wr_en <= '1';
      end if;

      wait_cycles(clk, 1);
      wr_en <= '0';
      rd_en <= '0';

      if do_rd then
        check_eq(dout, expected, "stress read data " & integer'image(i));
        pop(expected);
      end if;
      if do_wr then
        push(data_v);
      end if;

      check_state("stress " & integer'image(i));
    end loop;

    while qcount > 0 loop
      expected := queue(head);
      rd_en <= '1';
      wait_cycles(clk, 1);
      rd_en <= '0';
      check_eq(dout, expected, "final drain data");
      pop(expected);
      check_state("final drain");
    end loop;

    check_eq(empty, '1', "empty after final drain");
    check_eq(count, std_logic_vector(to_unsigned(0, COUNT_WIDTH)),
             "count zero after final drain");

    test_summary("sync_fifo");
  end process;

  watchdog : process is
  begin
    wait for TIMEOUT;
    fail("sync_fifo testbench timeout");
  end process;

end architecture;
