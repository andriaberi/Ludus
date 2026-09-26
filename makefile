SHELL := /bin/bash

BUILD_DIR := build
EXAMPLES_DIR := $(BUILD_DIR)/examples
CXX := g++
CXXFLAGS := -std=c++20 -Wall -Wextra -Iinclude

LUDUS_SOURCES := $(shell find src -name '*.cpp')

# Interactive picker: `menu "Title" opt1 opt2 ...` sets SELECTED, or exits on Esc.
define MENU
menu() { \
	local title="$$1"; shift; \
	local options=("$$@"); \
	local count=$${#options[@]}; \
	local choice=0; \
	while true; do \
		clear; \
		echo "$$title"; \
		echo; \
		for i in "$${!options[@]}"; do \
			if [ $$i -eq $$choice ]; then \
				printf "\033[32m❯ %s\033[0m\n" "$${options[$$i]}"; \
			else \
				printf "  %s\n" "$${options[$$i]}"; \
			fi; \
		done; \
		echo; \
		echo "Up/Down  Navigate"; \
		echo "Enter    Select"; \
		echo "Esc      Cancel"; \
		IFS= read -rsn1 key; \
		if [ "$$key" = $$'\033' ]; then \
			IFS= read -rsn2 -t 0.1 key2; \
			if [ "$$key2" = "[A" ]; then \
				choice=$$(( (choice - 1 + count) % count )); \
			elif [ "$$key2" = "[B" ]; then \
				choice=$$(( (choice + 1) % count )); \
			else \
				clear; echo "Cancelled."; exit 1; \
			fi; \
		elif [ -z "$$key" ]; then \
			break; \
		fi; \
	done; \
	clear; \
	SELECTED="$${options[$$choice]}"; \
}
endef

EXAMPLES = $$(find examples -mindepth 1 -maxdepth 1 -type d -printf '%f\n' 2>/dev/null | sort)

.PHONY: build test run clean

# `make build` shows a menu; `make build NAME=tic-tac-toe` skips it.
build:
	@$(MENU); \
	SELECTED="$(NAME)"; \
	if [ -z "$$SELECTED" ]; then menu "Build" src $(EXAMPLES); fi; \
	if [ "$$SELECTED" = "src" ]; then \
		cmake -S . -B $(BUILD_DIR) && cmake --build $(BUILD_DIR); \
	else \
		EXAMPLE_DIR="examples/$$SELECTED"; \
		if [ ! -d "$$EXAMPLE_DIR" ]; then echo "No example named '$$SELECTED'."; exit 1; fi; \
		SOURCES=$$(find "$$EXAMPLE_DIR" -name '*.cpp'); \
		mkdir -p "$(EXAMPLES_DIR)"; \
		echo "Building $$SELECTED..."; \
		$(CXX) $(CXXFLAGS) $$SOURCES $(LUDUS_SOURCES) -o "$(EXAMPLES_DIR)/$$SELECTED" || exit 1; \
		echo "Built $(EXAMPLES_DIR)/$$SELECTED"; \
	fi

test:
	clear
	@echo "Tests: NOT IMPLEMENTED"

# `make run` shows a menu; `make run NAME=tic-tac-toe` skips it.
run:
	@$(MENU); \
	SELECTED="$(NAME)"; \
	if [ -z "$$SELECTED" ]; then \
		OPTIONS=$(EXAMPLES); \
		if [ -z "$$OPTIONS" ]; then echo "No examples found"; exit 0; fi; \
		menu "Run" $$OPTIONS; \
	fi; \
	$(MAKE) --no-print-directory build NAME="$$SELECTED" && \
	./$(EXAMPLES_DIR)/"$$SELECTED"

clean:
	rm -rf $(BUILD_DIR)
