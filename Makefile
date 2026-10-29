# Top-level orchestration for the VHDL learning projects.
#
# Every project folder has its own small Makefile which includes
# mk/project.mk.  These targets add aggregate management on top.
SHELL := /bin/bash

GHDL    ?= ghdl
GTKWAVE ?= gtkwave
LOG_DIR := .logs

# Numeric prefixes keep the folders ordered and make discovery predictable.
PROJECTS := $(notdir $(patsubst %/Makefile,%,$(wildcard [0-9][0-9]-*/Makefile)))

.DEFAULT_GOAL := help
.PHONY: help check list test lint wave clean new fmt

help:
	@echo "VHDL learning projects"
	@echo
	@echo "  make check                          verify tools and show versions"
	@echo "  make list                           list projects and descriptions"
	@echo "  make test                           run every project testbench"
	@echo "  make test PROJECT=04-uart           run one project testbench"
	@echo "  make lint                           analyze every project (-Wall)"
	@echo "  make wave PROJECT=04-uart           run and open GTKWave"
	@echo "  make wave PROJECT=04-uart GTKW=my.gtkw"
	@echo "                                          use a saved GTKWave layout"
	@echo "  make clean                          remove all build outputs"
	@echo "  make clean PROJECT=04-uart          clean one project"
	@echo "  make fmt PROJECT=04-uart            format that project with ghdl fmt"
	@echo "  make new NAME=15-watchdog TITLE=\"Watchdog timer\""
	@echo "                                          scaffold a new project"
	@echo
	@echo "Per-project: make -C 04-uart test|analyze|wave|clean|fmt"

check:
	@command -v $(GHDL) >/dev/null 2>&1 || { echo "error: GHDL not found"; exit 1; }
	@command -v $(GTKWAVE) >/dev/null 2>&1 || { echo "error: GTKWave not found"; exit 1; }
	@command -v make >/dev/null 2>&1 || { echo "error: GNU Make not found"; exit 1; }
	@printf 'GHDL:    '; $(GHDL) --version | head -n 1
	@printf 'GTKWave: '; $(GTKWAVE) --version | head -n 1
	@printf 'Make:    '; make --version | head -n 1
	@echo "OK"

list:
	@printf '%-26s %s\n' "PROJECT" "DESCRIPTION"
	@for p in $(PROJECTS); do \
		desc=$$(sed -n '1s/^# //p' "$$p/README.md" 2>/dev/null); \
		printf '%-26s %s\n' "$$p" "$$desc"; \
	done

ifneq ($(strip $(PROJECT)),)
test:
	@$(MAKE) --no-print-directory -C $(PROJECT) test
else
test:
	@mkdir -p $(LOG_DIR)
	@passed=0; failed=0; failed_projects=""; \
	for p in $(PROJECTS); do \
		if $(MAKE) --no-print-directory -C $$p test > $(LOG_DIR)/$$p.log 2>&1; then \
			printf '  PASS  %-28s\n' "$$p"; passed=$$((passed+1)); \
		else \
			printf '  FAIL  %-28s\n' "$$p"; failed=$$((failed+1)); \
			failed_projects="$$failed_projects $$p"; \
		fi; \
	done; \
	printf '\n%d passed, %d failed\n' "$$passed" "$$failed"; \
	if [ "$$failed" -ne 0 ]; then \
		for p in $$failed_projects; do \
			echo; echo "--- $$p (last 25 lines) ---"; \
			tail -n 25 $(LOG_DIR)/$$p.log; \
		done; \
		exit 1; \
	fi
endif

ifneq ($(strip $(PROJECT)),)
lint:
	@$(MAKE) --no-print-directory -C $(PROJECT) analyze
else
lint:
	@mkdir -p $(LOG_DIR)
	@failed=0; failed_projects=""; \
	for p in $(PROJECTS); do \
		if $(MAKE) --no-print-directory -C $$p analyze > $(LOG_DIR)/lint-$$p.log 2>&1 \
		   && ! grep -q 'warning:' $(LOG_DIR)/lint-$$p.log; then \
			printf '  CLEAN %-28s\n' "$$p"; \
		else \
			printf '  WARN  %-28s\n' "$$p"; failed=$$((failed+1)); \
			failed_projects="$$failed_projects $$p"; \
		fi; \
	done; \
	if [ "$$failed" -ne 0 ]; then \
		for p in $$failed_projects; do \
			echo; echo "--- $$p ---"; \
			cat $(LOG_DIR)/lint-$$p.log; \
		done; \
		exit 1; \
	fi; \
	printf '\nall projects analyzed cleanly\n'
endif

wave:
	@if [ -z "$(PROJECT)" ]; then \
		echo "usage: make wave PROJECT=04-uart [GTKW=layout.gtkw]"; exit 1; \
	fi
	@$(MAKE) --no-print-directory -C $(PROJECT) wave

ifneq ($(strip $(PROJECT)),)
clean:
	@$(MAKE) --no-print-directory -C $(PROJECT) clean
else
clean:
	@for p in $(PROJECTS); do $(MAKE) --no-print-directory -C $$p clean; done
	@rm -rf $(LOG_DIR)
	@echo "clean: removed project build directories and $(LOG_DIR)/"
endif

fmt:
	@if [ -z "$(PROJECT)" ]; then \
		echo "usage: make fmt PROJECT=04-uart"; exit 1; \
	fi
	@$(MAKE) --no-print-directory -C $(PROJECT) fmt

new:
	@if [ -z "$(NAME)" ]; then \
		echo "usage: make new NAME=15-watchdog [TITLE=\"Watchdog timer\"]"; exit 1; \
	fi
	@bash scripts/new-project.sh "$(NAME)" "$(TITLE)"
