# shared_ui — the AppKit elements Notes and Tasks share (compiled into each
# app from SHARED_UI_DIR; see BUILD.md)
#
#   make          compile every src/*.m to build/ (what the apps do, so a
#                 mistake shows here first) and build the test binary
#   make test     run the tests
#   make run      not applicable (a library has nothing to run); says so
#   make install  not applicable (the apps compile src/ into themselves
#                 from SHARED_UI_DIR); says so
#   make clean    remove build/

CC = clang

# The apps' flags: ARC, macOS 14, their warning set made fatal here.
DEPLOY_TARGET = 14.0
CFLAGS  = -fobjc-arc -O2 -Wall -Wextra -Werror -Werror=unguarded-availability \
          -mmacosx-version-min=$(DEPLOY_TARGET) -I src -MMD -MP -Wno-unused-parameter
LDFLAGS = -mmacosx-version-min=$(DEPLOY_TARGET) -framework Cocoa \
          -framework UniformTypeIdentifiers -framework EventKit -framework Carbon

SRCS     = $(wildcard src/*.m)
OBJS     = $(patsubst src/%.m,build/%.o,$(SRCS))
TEST_BIN = build/shared_ui_test

.PHONY: all test run install clean

all: $(OBJS) $(TEST_BIN)

build/%.o: src/%.m Makefile | build
	$(CC) $(CFLAGS) -c -o $@ $<

build/shared_ui_test.o: tests/shared_ui_test.m tests/check.h Makefile | build
	$(CC) $(CFLAGS) -I tests -c -o $@ $<

$(TEST_BIN): build/shared_ui_test.o $(OBJS)
	$(CC) -o $@ $^ $(LDFLAGS)

build:
	mkdir -p build

test: $(TEST_BIN)
	./$(TEST_BIN)

run:
	@echo "shared_ui is a library: there is nothing to run.  Try 'make test'."

install:
	@echo "shared_ui is not installed: Notes and Tasks compile src/*.m into"
	@echo "themselves from SHARED_UI_DIR (default ../shared_ui)."

clean:
	rm -rf build

-include build/*.d
