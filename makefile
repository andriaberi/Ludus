BUILD_DIR := build
CXX       := g++
CXXFLAGS  := -std=c++20 -Wall -Wextra -Iinclude

export BUILD_DIR CXX CXXFLAGS

.PHONY: build run test clean

# `make build` / `make run` open a picker; `make run NAME=tic-tac-toe` skips it.
build run test clean:
	@bash tools/cli.sh $@ $(NAME)
