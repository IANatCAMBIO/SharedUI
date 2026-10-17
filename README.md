# shared_ui — the interface Notes and Tasks share

The two sister apps show the same elements built the same way: the tool
panel with its blue hero strip, the sidebar's split view that remembers
its width, the table that selects on mouse-down and opens on Return, the
emoji slot of Edit Tag, status labels, the file picker, glyphs and icons.
This directory holds the module both apps compile in, so each of those
exists once and the apps cannot drift apart:

- `src/shared_look.h` — the sizes and colours of the shared elements
  (plain C, so an app's C code can use it); each app keeps a `look.h`
  for what only it has.
- `src/shared_ui.[hm]` — the helpers: `shared_ui_color`,
  `shared_ui_symbol`, `shared_ui_app_icon`, `shared_ui_image_view`,
  `shared_ui_notice` / `shared_ui_confirm` / `shared_ui_pick_path`,
  `shared_ui_status_label`, `shared_ui_use_ui_font`, `SharedTable`,
  `SharedSplitController`, `shared_ui_emoji_field`, tag labels,
  formatting, and `SharedFavoriteButton`, the Favorites bars' button that
  drags along its strip to reorder (`shared_ui_place_favorites`).
- `src/shared_order.[hm]` — a saved order as a list of ids
  (`shared_order_permutation`, `shared_order_text`): plain C, used by
  both Favorites bars and by Tasks' task orders.
- `src/shared_commands.[hm]` — the command table: an app installs one
  table of its commands (identifier, title, shortcut, scope, glyph,
  tooltip); menu items, toolbar items and bar buttons are made from it,
  and modules run and validate commands through handler tables
  (`shared_command_run`, `shared_command_validate`, `SharedCommandState`).
- `src/shared_tool_panel.[hm]` — `SharedHero` and `SharedToolPanel`, the
  apps' only dialog.

The conventions are the apps': the appearance is followed by dynamic
colours, no `NSAlert` or sheet is ever shown, an image view is created at
its final size before it gets its image, Return never performs a
destructive action.

## Installation

Nothing is installed.  Notes and Tasks compile `src/*.m` into themselves
from `SHARED_UI_DIR` (default `../shared_ui`, this directory checked out
beside them), as they compile the shared database module from
`../shared_data`.  `make test` runs this module's own tests; the apps'
UI probes (`make ui-check` in each) exercise the panels and tables on
screen.  See `BUILD.md`.
