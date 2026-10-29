#!/usr/bin/env bash
# Scaffold a compilable VHDL project folder.
#
# Usage: scripts/new-project.sh 15-watchdog "Watchdog timer"
set -euo pipefail

name="${1:-}"
title="${2:-}"

if [[ -z "$name" ]]; then
  echo "usage: $0 NN-kebab-name [\"Title\"]" >&2
  exit 1
fi

if ! [[ "$name" =~ ^[0-9]{2}-[a-z0-9]+(-[a-z0-9]+)*$ ]]; then
  echo "error: name must look like 15-watchdog (two digits, lowercase, dashes)" >&2
  exit 1
fi

if [[ -e "$name" ]]; then
  echo "error: $name already exists" >&2
  exit 1
fi

base="${name#??-}"
base="${base//-/_}"

if [[ -z "$title" ]]; then
  title="$(printf '%s' "$base" | tr '_' ' ' | sed 's/\b\([a-z]\)/\u\1/g')"
fi

mkdir -p "$name"

cat > "$name/$base.vhd" <<EOF
-- =============================================================================
-- $base -- TODO: one-line description
--
-- Tutorial comments:
--   Explain *why* this block exists, how it is clocked/reset, and any timing
--   or arithmetic rule a reader cannot infer from the code.  Keep the full
--   theory and exercises in README.md.
-- =============================================================================
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity $base is
  port (
    clk_i  : in  std_logic;
    rst_i  : in  std_logic;
    din_i  : in  std_logic;
    dout_o : out std_logic
  );
end entity;

architecture rtl of $base is
begin

  -- A registered passthrough is the smallest useful scaffold: it exercises
  -- clocking, synchronous reset, and a real testbench check.
  process (clk_i) is
  begin
    if rising_edge(clk_i) then
      if rst_i = '1' then
        dout_o <= '0';
      else
        dout_o <= din_i;
      end if;
    end if;
  end process;

end architecture;
EOF

cat > "$name/${base}_tb.vhd" <<EOF
-- =============================================================================
-- ${base}_tb -- self-checking smoke test for the scaffold
-- =============================================================================
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;

library work;
use work.tb_pkg.all;

entity ${base}_tb is
end entity;

architecture sim of ${base}_tb is
  constant CLK_PERIOD : time := 10 ns;
  constant TIMEOUT    : time := 1 ms;

  signal clk    : std_logic := '0';
  signal rst    : std_logic := '1';
  signal din    : std_logic := '0';
  signal dout   : std_logic;
begin

  clk <= not clk after CLK_PERIOD / 2;

  dut : entity work.$base
    port map (
      clk_i  => clk,
      rst_i  => rst,
      din_i  => din,
      dout_o => dout
    );

  stim : process is
  begin
    report "TC1: synchronous reset" severity note;
    wait_cycles(clk, 3);
    rst <= '0';
    wait_cycles(clk, 1);
    check_eq(dout, '0', "output is cleared during reset");

    report "TC2: registered passthrough" severity note;
    din <= '1';
    wait_cycles(clk, 1);
    check_eq(dout, '1', "input is visible one clock later");
    din <= '0';
    wait_cycles(clk, 1);
    check_eq(dout, '0', "input returns low");

    test_summary("$base");
  end process;

  watchdog : process is
  begin
    wait for TIMEOUT;
    fail("simulation timeout");
  end process;

end architecture;
EOF

cat > "$name/Makefile" <<EOF
TOP := ${base}_tb
RTL := $base.vhd
TB  := ${base}_tb.vhd

include ../mk/project.mk
EOF

cat > "$name/README.md" <<EOF
# $name — $title

TODO: replace this scaffold text with the real project description.

## Overview

Describe what the block does and why it matters in an industrial design.

## What you will learn

- TODO

## Block diagram

\`\`\`text
TODO
\`\`\`

## Generics

| Name | Type | Default | Meaning |
|---|---|---|---|
| — | — | — | — |

## Ports

| Name | Direction | Width | Meaning |
|---|---|---|---|
| \`clk_i\` | in | 1 | Clock |
| \`rst_i\` | in | 1 | Synchronous active-high reset |
| \`din_i\` | in | 1 | Input data |
| \`dout_o\` | out | 1 | Registered output |

## Design notes

TODO: timing, arithmetic, protocol details, and pitfalls.

## Files

| File | Purpose |
|---|---|
| \`$base.vhd\` | RTL |
| \`${base}_tb.vhd\` | Self-checking testbench |

## Simulate

\`\`\`sh
make test
make wave
\`\`\`

## Signals to inspect in GTKWave

- \`${base}_tb.clk\`
- \`${base}_tb.rst\`
- \`${base}_tb.din\`
- \`${base}_tb.dout\`

## Testbench strategy

TODO: list the test cases and what each one proves.

## Exercises

1. TODO
EOF

echo "Created $name/"
echo
echo "Next:"
echo "  1. edit $name/README.md and $name/$base.vhd"
echo "  2. make test PROJECT=$name"
echo "  3. add the project to the table in README.md"
