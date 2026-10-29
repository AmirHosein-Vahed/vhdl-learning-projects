-- =============================================================================
-- spi_slave_model -- simulation-only SPI slave for the project 06 testbench
--
-- This model is clocked by SCLK edges rather than clk_i, which makes it behave
-- like a real SPI peripheral.  It supports all four modes through mode_i and
-- drives MISO to 'Z' while its chip select is inactive, so several instances
-- can share a resolved MISO line.
--
-- It is not synthesizable RTL; it lives only in the testbench build.
-- =============================================================================
library ieee;
use ieee.std_logic_1164.all;

entity spi_slave_model is
  port (
    cs_n_i    : in  std_logic;
    sclk_i    : in  std_logic;
    mosi_i    : in  std_logic;
    miso_o    : out std_logic;
    mode_i    : in  std_logic_vector(1 downto 0);  -- (1)=CPOL, (0)=CPHA
    tx_data_i : in  std_logic_vector(7 downto 0);
    rx_data_o : out std_logic_vector(7 downto 0)
  );
end entity;

architecture sim of spi_slave_model is

  signal tx_sr   : std_logic_vector(7 downto 0) := (others => '0');
  signal rx_sr   : std_logic_vector(7 downto 0) := (others => '0');
  signal rx_data_r : std_logic_vector(7 downto 0) := (others => '0');
  signal miso_r  : std_logic := 'Z';
  signal bit_cnt : natural range 0 to 7 := 0;

begin

  process (all) is
    variable cpol : std_logic;
    variable cpha : std_logic;
    variable rx_next : std_logic_vector(7 downto 0);
  begin
    cpol := mode_i(1);
    cpha := mode_i(0);

    if cs_n_i = '1' then
      -- Deselected: release MISO and prepare for the next frame.
      bit_cnt <= 0;
      rx_sr   <= (others => '0');
      tx_sr   <= (others => '0');
      miso_r  <= 'Z';
    elsif cs_n_i'event then
      -- Chip select just asserted: load the transmit shift register.
      bit_cnt <= 0;
      rx_sr   <= (others => '0');
      tx_sr   <= tx_data_i;
      if cpha = '0' then
        -- CPHA=0: the first bit is valid before the first leading edge.
        miso_r <= tx_data_i(7);
        tx_sr  <= tx_data_i(6 downto 0) & '0';
      else
        -- CPHA=1: the first leading edge launches the first bit.
        miso_r <= '0';
      end if;
    else
      if (cpol = '0' and rising_edge(sclk_i)) or
         (cpol = '1' and falling_edge(sclk_i)) then
        -- Leading edge.
        if cpha = '0' then
          -- Sample MOSI.
          rx_next := rx_sr(6 downto 0) & mosi_i;
          rx_sr   <= rx_next;
          if bit_cnt = 7 then
            rx_data_r <= rx_next;
          else
            bit_cnt <= bit_cnt + 1;
          end if;
        else
          -- Launch the next MISO bit.
          miso_r <= tx_sr(7);
          tx_sr  <= tx_sr(6 downto 0) & '0';
        end if;

      elsif (cpol = '0' and falling_edge(sclk_i)) or
            (cpol = '1' and rising_edge(sclk_i)) then
        -- Trailing edge.
        if cpha = '0' then
          -- Launch the next MISO bit.
          miso_r <= tx_sr(7);
          tx_sr  <= tx_sr(6 downto 0) & '0';
        else
          -- Sample MOSI.
          rx_next := rx_sr(6 downto 0) & mosi_i;
          rx_sr   <= rx_next;
          if bit_cnt = 7 then
            rx_data_r <= rx_next;
          else
            bit_cnt <= bit_cnt + 1;
          end if;
        end if;
      end if;
    end if;
  end process;

  miso_o <= miso_r;
  rx_data_o <= rx_data_r;

end architecture;
