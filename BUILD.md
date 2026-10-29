# Building shared_ui

## Toolchain and dependencies

| What | Version used | How to get it |
|---|---|---|
| clang (Apple) | Xcode command-line tools | `xcode-select --install` |
| macOS SDK | 14.0 deployment target (the apps') | with the tools |

The module is Objective-C with ARC against Cocoa, UniformTypeIdentifiers,
EventKit (the calendar) and Carbon (the system-wide hotkey) only: no GLib,
no SQLite, nothing from MacPorts.

## Targets

| Target | Does |
|---|---|
| `make` | compiles every `src/*.m` to `build/` with the apps' flags (zero warnings, made fatal) and builds `build/shared_ui_test` |
| `make test` | runs the tests: colours, glyphs, image views, tag labels, formatting, saved orders, the favorite buttons' row and drag, the table's activation rule, the split controller's width report, the command table |
| `make clean` | removes `build/` |
| `make run`, `make install` | not applicable (a library); print a note |

## How the apps use it

Each app's Makefile has `SHARED_UI_DIR ?= $(CURDIR)/../shared_ui`, adds
`-I $(SHARED_UI_DIR)/src` to its compile flags, and compiles
`$(SHARED_UI_DIR)/src/*.m` into its own `build/` beside its sources.  A
header here is included by its bare name (`#import "shared_ui.h"`).

## Platform notes

The day planner is exercised by the apps' `make ui-check` (it needs a
delegate), not by this module's tests; nor is the calendar, which is the
user's real one: no test turns it on.

The hero strip's symbol, the glyphs and the emoji slot's picker are the
system's (SF Symbols, the Character Viewer); the tool panel is a utility
window and floats, so `make test` does not need a screen but the apps'
`make ui-check` does.
