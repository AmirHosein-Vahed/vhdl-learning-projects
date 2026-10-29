# Shared build rules for one project folder.
#
# A project Makefile only sets TOP, RTL and TB:
#
#   TOP := uart_tb
#   RTL := uart_pkg.vhd uart_tx.vhd uart_rx.vhd
#   TB  := uart_tb.vhd
#   include ../mk/project.mk
#
# Analysis order is explicit because GHDL does not infer dependencies.
# The shared library is always analyzed first, into this project's workdir.

GHDL     ?= ghdl
GTKWAVE  ?= gtkwave
STD      ?= 08
BUILD    ?= build
LIB      ?= ../lib

ifeq ($(strip $(TOP)),)
$(error TOP is not set in $(CURDIR)/Makefile)
endif
ifeq ($(strip $(TB)),)
$(error TB is not set in $(CURDIR)/Makefile)
endif

LIB_SRCS := $(LIB)/util_pkg.vhd $(LIB)/tb_pkg.vhd
SRCS     := $(LIB_SRCS) $(RTL) $(TB)
WAVE     := $(BUILD)/$(TOP).ghw

GHDLFLAGS ?= --std=$(STD) --workdir=$(BUILD) -Wall
RUNFLAGS  ?= --assert-level=failure

.PHONY: all help analyze elab run test wave clean fmt

all: test

help:
	@echo "Project: $(CURDIR)"
	@echo "  make test      analyze, elaborate, and run $(TOP)"
	@echo "  make analyze   analyze only (syntax/type check)"
	@echo "  make wave      run and open $(WAVE) in GTKWave"
	@echo "  make clean     remove $(BUILD)/"
	@echo "  make fmt       rewrite project sources with ghdl fmt"

$(BUILD):
	@mkdir -p $(BUILD)

analyze: | $(BUILD)
	@$(GHDL) -a $(GHDLFLAGS) $(SRCS)

elab: analyze
	@$(GHDL) -e $(GHDLFLAGS) $(TOP)

run: elab
	@$(GHDL) -r $(GHDLFLAGS) $(TOP) $(RUNFLAGS) --wave=$(WAVE)

test: run

wave: test
	@if [ -n "$(GTKW)" ] && [ ! -f "$(GTKW)" ]; then \
		echo "error: layout $(GTKW) not found"; exit 1; \
	fi
	@if [ -n "$(GTKW)" ]; then \
		echo "Opening $(WAVE) with layout $(GTKW)"; \
		$(GTKWAVE) -a "$(GTKW)" "$(WAVE)" >/dev/null 2>&1 & \
	else \
		echo "Opening $(WAVE)"; \
		$(GTKWAVE) "$(WAVE)" >/dev/null 2>&1 & \
	fi

clean:
	@rm -rf $(BUILD)

fmt:
	@$(GHDL) fmt --std=$(STD) $(RTL) $(TB)
