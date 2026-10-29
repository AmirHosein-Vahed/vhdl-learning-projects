-- =============================================================================
-- spi_master -- 8-bit SPI master, CPOL/CPHA modes 0-3, multi-slave CS
--
-- The master shifts MSB first and supports all four SPI modes through the
-- mode_i input: mode_i(1) is CPOL, mode_i(0) is CPHA.
--
--   CPOL = 0: SCLK idles low,  leading edge is rising
--   CPOL = 1: SCLK idles high, leading edge is falling
--   CPHA = 0: sample MISO on the leading edge, change MOSI on the trailing
--   CPHA = 1: change MOSI on the leading edge, sample MISO on the trailing
--
-- A transfer takes 16 half-periods.  CLK_DIV is the number of clk_i cycles in
-- one half-period, so SCLK = clk_i / (2 * CLK_DIV).
--
-- cs_sel_i is one-hot and active high; cs_n_o is its active-low version while
-- a transfer is running.  Selecting no slave leaves all CS lines high.
-- =============================================================================
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity spi_master is
  generic (
    NUM_SLAVES : positive := 2;
    CLK_DIV    : positive := 4
  );
  port (
    clk_i    : in  std_logic;
    rst_i    : in  std_logic;
    start_i  : in  std_logic;
    mode_i   : in  std_logic_vector(1 downto 0);  -- (1)=CPOL, (0)=CPHA
    cs_sel_i : in  std_logic_vector(NUM_SLAVES - 1 downto 0);
    data_i   : in  std_logic_vector(7 downto 0);
    data_o   : out std_logic_vector(7 downto 0);
    sclk_o   : out std_logic;
    mosi_o   : out std_logic;
    miso_i   : in  std_logic;
    cs_n_o   : out std_logic_vector(NUM_SLAVES - 1 downto 0);
    busy_o   : out std_logic;
    done_o   : out std_logic
  );
end entity;

architecture rtl of spi_master is

  type state_t is (IDLE, TRANSFER, HOLD);

  signal state   : state_t := IDLE;
  signal sclk_r  : std_logic := '0';
  signal mosi_r  : std_logic := '0';
  signal cs_n_r  : std_logic_vector(NUM_SLAVES - 1 downto 0) := (others => '1');
  signal mosi_sr : std_logic_vector(7 downto 0) := (others => '0');
  signal miso_sr : std_logic_vector(7 downto 0) := (others => '0');
  signal data_r  : std_logic_vector(7 downto 0) := (others => '0');
  signal phase   : natural range 0 to 15 := 0;
  signal div_cnt : natural range 0 to CLK_DIV - 1 := 0;
  signal busy_r  : std_logic := '0';
  signal done_r  : std_logic := '0';

begin

  assert NUM_SLAVES >= 1
    report "spi_master: NUM_SLAVES must be at least 1"
    severity failure;
  assert CLK_DIV >= 1
    report "spi_master: CLK_DIV must be at least 1"
    severity failure;

  process (clk_i) is
  begin
    if rising_edge(clk_i) then
      if rst_i = '1' then
        state   <= IDLE;
        sclk_r  <= '0';
        mosi_r  <= '0';
        cs_n_r  <= (others => '1');
        mosi_sr <= (others => '0');
        miso_sr <= (others => '0');
        data_r  <= (others => '0');
        phase   <= 0;
        div_cnt <= 0;
        busy_r  <= '0';
        done_r  <= '0';
      else
        -- done_o is a one-cycle pulse; clear it unless this cycle completes.
        done_r <= '0';

        case state is
          when IDLE =>
            busy_r <= '0';
            sclk_r <= mode_i(1);  -- keep the idle level correct if mode changes
            if start_i = '1' then
              cs_n_r  <= not cs_sel_i;
              miso_sr <= (others => '0');
              phase   <= 0;
              div_cnt <= 0;
              busy_r  <= '1';

              if mode_i(0) = '0' then
                -- CPHA=0: the first bit must be valid before the first edge.
                mosi_r  <= data_i(7);
                mosi_sr <= data_i(6 downto 0) & '0';
              else
                -- CPHA=1: the first leading edge launches the first bit.
                mosi_r  <= '0';
                mosi_sr <= data_i;
              end if;

              state <= TRANSFER;
            end if;

          when TRANSFER =>
            busy_r <= '1';
            if div_cnt = CLK_DIV - 1 then
              div_cnt <= 0;

              -- Sample MISO on the sampling edge for this CPHA setting.
              if (mode_i(0) = '0' and phase mod 2 = 0) or
                 (mode_i(0) = '1' and phase mod 2 = 1) then
                miso_sr <= miso_sr(6 downto 0) & miso_i;
              end if;

              -- Change MOSI on the other edge.
              if (mode_i(0) = '0' and phase mod 2 = 1) or
                 (mode_i(0) = '1' and phase mod 2 = 0) then
                mosi_r  <= mosi_sr(7);
                mosi_sr <= mosi_sr(6 downto 0) & '0';
              end if;

              sclk_r <= not sclk_r;

              if phase = 15 then
                state  <= HOLD;
                sclk_r <= mode_i(1);

                -- For CPHA=0 the last bit was sampled at phase 14; for
                -- CPHA=1 it is sampled now, so include miso_i explicitly.
                if mode_i(0) = '1' then
                  data_r <= miso_sr(6 downto 0) & miso_i;
                else
                  data_r <= miso_sr;
                end if;
              else
                phase <= phase + 1;
              end if;
            else
              div_cnt <= div_cnt + 1;
            end if;

          when HOLD =>
            -- Keep CS active for one extra clock after the last SCLK edge so
            -- a slave clocked by SCLK can capture the final bit before the
            -- chip select is released.
            cs_n_r <= (others => '1');
            sclk_r <= mode_i(1);
            busy_r <= '0';
            done_r <= '1';
            state  <= IDLE;
        end case;
      end if;
    end if;
  end process;

  data_o  <= data_r;
  sclk_o  <= sclk_r;
  mosi_o  <= mosi_r;
  cs_n_o  <= cs_n_r;
  busy_o  <= busy_r;
  done_o  <= done_r;

end architecture;
