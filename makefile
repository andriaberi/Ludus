BUILD_DIR := build
CXX       := g++
CXXFLAGS  := -std=c++20 -Wall -Wextra -Iinclude

export BUILD_DIR CXX CXXFLAGS

.DEFAULT_GOAL := help
.PHONY: help build run clean test check version bump

# `make build` / `make run` open a picker; `make run NAME=tic-tac-toe` skips it.
build run:
	@bash cli.sh $@ $(NAME)

# `make bump TO=patch|minor|major|1.2.3` (TO defaults to patch).
bump:
	@bash cli.sh bump $(TO)

help clean test check version:
	@bash cli.sh $@
