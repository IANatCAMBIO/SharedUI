/*
 * shared_ui — the AppKit helpers Notes and Tasks share, so each exists
 * exactly once: colours from shared_look.h, glyphs, images at their
 * display size, the dialogs (shared_tool_panel.h), the file picker, status
 * labels, the apps' text size, the table that selects on mouse-down and
 * activates on Return, the split view controller that remembers its
 * sidebar's width, the emoji slot, tag labels, formatting.
 *
 * IMAGES: THE RULE.  An image shown in a view is decoded at the size it is
 * shown, and the view that shows it is created at that size.  An
 * NSImageView created with a zero frame and given a large image before
 * layout makes AppKit render and cache the image's LARGEST representation
 * (4 MB for a 1024 px icon), and its layer keeps a second copy — tens of
 * megabytes for a screenful of icons.  So neither app calls
 * [[NSImageView alloc] init] or +imageViewWithImage:, or hands a
 * full-size NSImage to a small view.  Use shared_ui_app_icon and
 * shared_ui_image_view.
 *
 * Everything here is main-thread only unless it says otherwise.
 */

#import <Cocoa/Cocoa.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

#include "shared_look.h"

/* ── The app ────────────────────────────────────────────────────────────── */

/*
 * shared_ui_app_name — the running app's name, as its tool panels' title
 * bars show it: the bundle's CFBundleName, else the process name.
 *
 * Output: the name.
 */
NSString *shared_ui_app_name(void);

/* ── Appearance ─────────────────────────────────────────────────────────── */

/*
 * shared_ui_is_dark — whether a view is drawn under a dark appearance: the
 * `dark` that shared_look_pick takes.
 *
 * Inputs:
 *   view — the view being drawn
 *
 * Output: YES for a dark appearance.
 */
BOOL shared_ui_is_dark(NSView *view);

/*
 * shared_ui_color — a shared_look.h colour as an NSColor that follows the
 * appearance it is drawn under.  One dynamic colour per value, kept: a
 * colour made of a block is equal to nothing but itself, so callers that
 * compare attributed strings need the same object back.
 *
 * Inputs:
 *   color — the colour
 *
 * Output: the shared dynamic NSColor.
 */
NSColor *shared_ui_color(shared_color_t color);

/* ── Images ─────────────────────────────────────────────────────────────── */

/*
 * shared_ui_symbol — a command's glyph: an SF Symbol, as a TEMPLATE image.
 * A template image is a shape, not a picture: the control showing it draws
 * the shape in its own text colour, so the glyph follows light and dark,
 * the disabled look and a pressed button with no code here.  For toolbar
 * items and the buttons of a window's own bars.  Cached per name and size
 * (the toolbar asks after every event).
 *
 * Inputs:
 *   name   — SF Symbol name: @"plus", @"trash", @"sidebar.left", …
 *   points — the symbol's point size, as a font's (it is drawn about as
 *            tall as text of that size); 0 = no size of its own, for a
 *            toolbar item, which sizes its image itself
 *
 * Output: the image; nil when the system has no symbol of that name.  Do
 *         not modify it (it is shared).
 */
NSImage *shared_ui_symbol(NSString *name, CGFloat points);

/*
 * shared_ui_app_icon — the app's own artwork (the one PNG it bundles) at
 * a size, for the Dock tile, the About panel and the alerts: macOS 26
 * puts a bundle icon that is not its rounded-square shape on a grey
 * backdrop; handing those places the image explicitly shows just the
 * artwork.  The image holds ONE bitmap of `size` points at 2x, scaled
 * once from the file — never the full-size artwork — and is cached per
 * resource and size.
 *
 * Inputs:
 *   resource — the PNG's name in the bundle, without the extension
 *   size     — edge length in points
 *
 * Output: the shared image (do not modify it), or nil when the bundle has
 *         no such file.
 */
NSImage *shared_ui_app_icon(NSString *resource, CGFloat size);

/*
 * shared_ui_image_view — an image view created AT ITS FINAL SIZE (see THE
 * RULE above), scaling its image down proportionally.  The only way the
 * apps make an NSImageView.
 *
 * Inputs:
 *   image  — what to show; may be nil and set later, once the view has
 *            this frame
 *   width  — the view's size in points
 *   height
 *
 * Output: the view, with fixed width and height constraints so Auto Layout
 *         keeps the size.
 */
NSImageView *shared_ui_image_view(NSImage *image, CGFloat width, CGFloat height);

/* ── Dialogs ────────────────────────────────────────────────────────────── */

/*
 * Neither app shows a native dialog (NSAlert, an alert sheet, a custom
 * sheet): every message and question is a tool panel.  These two cover
 * the common cases; anything else builds a SharedToolPanel directly.
 */

/*
 * shared_ui_notice — a message with one OK button, in a tool panel.  How a
 * failure is shown: the title states what failed, the message why.
 *
 * Inputs:
 *   parent  — the window to centre over; nil = the screen
 *   title   — the headline, e.g. @"Could not open the database"
 *   message — the detail; may be nil
 *   done    — called once on the main thread when the panel goes (OK,
 *             Escape or the close box); may be nil.  The panel is not
 *             modal: whatever must wait for the user goes here.
 */
void shared_ui_notice(NSWindow *parent, NSString *title, NSString *message, void (^done)(void));

/*
 * shared_ui_confirm — ask, in a tool panel, before doing something.
 * Cancel is the default button (Return) and Escape dismisses, so a key
 * press never performs the action; the action button is named for it
 * ("Delete", "Clear") and sits to Cancel's left.
 *
 * Inputs:
 *   parent      — the window to centre over; nil = the screen
 *   title       — the question, e.g. @"Delete 3 tasks?"
 *   message     — the consequence; nil for "This cannot be undone." when
 *                 destructive, else nothing
 *   action      — the action button's title
 *   destructive — YES for an action that cannot be undone: a warning
 *                 symbol, and the action button takes the destructive look
 *   done        — called on the main thread with YES when the action
 *                 button was chosen, NO for Cancel, Escape or the close box
 */
void shared_ui_confirm(NSWindow *parent, NSString *title, NSString *message, NSString *action,
                       BOOL destructive, void (^done)(BOOL confirmed));

/* What shared_ui_pick_path asks for. */
typedef NS_ENUM(NSInteger, SharedPickKind) {
    SharedPickOpenFile,              /* an existing file                    */
    SharedPickSaveFile,              /* a file name to write                */
    SharedPickFolder,                /* an existing folder (may create one) */
};

/*
 * shared_ui_pick_path — run an open or save panel and hand over the
 * choice.  The one system panel the apps keep, as in the Files app: a
 * window of its own, app-modal, never a sheet on another window.
 *
 * Inputs:
 *   kind      — what to pick
 *   message   — the panel's message
 *   prompt    — the accept button's title, e.g. @"Open"
 *   types     — content types to allow (e.g. @[UTTypeImage]); nil = any
 *   start_dir — the folder to open in; nil = where the user last was
 *   done      — called on the main thread, once, when the panel closes,
 *               with the chosen path, or nil when it was cancelled
 */
void shared_ui_pick_path(SharedPickKind kind, NSString *message, NSString *prompt,
                         NSArray<UTType *> *types, NSString *start_dir,
                         void (^done)(NSString *path));

/* ── Windows ────────────────────────────────────────────────────────────── */

/*
 * shared_ui_place_lower_right — move a window to the lower-right corner of
 * a screen's work area (what the menu bar and the Dock leave free),
 * shared_look_screen_margin in from its right and bottom edges.  The
 * window keeps its size; a window too big for the corner keeps its title
 * bar on screen.
 *
 * Inputs:
 *   window — the window to move
 *   screen — the screen; nil leaves the window where it is
 */
void shared_ui_place_lower_right(NSWindow *window, NSScreen *screen);

/*
 * shared_ui_pane_item — a split-view item around a pane's view, for a
 * split view controller.
 *
 * Inputs:
 *   view      — the pane
 *   min_width — the narrowest it may be dragged
 *
 * Output: the item.
 */
NSSplitViewItem *shared_ui_pane_item(NSView *view, CGFloat min_width);

/*
 * SharedSplitController — a split view controller whose FIRST item is a
 * sidebar that remembers its width: every time the divider moves while
 * the sidebar shows (a drag, a fit to content), width_changed is told the
 * new width, for the app to save for the next launch.  A collapsed
 * sidebar has no width and reports nothing.
 */
@interface SharedSplitController : NSSplitViewController
@property (nonatomic, copy) void (^width_changed)(NSInteger width);
@end

/* ── Controls ───────────────────────────────────────────────────────────── */

/*
 * shared_ui_status_label — one label of a status bar (a library's, an
 * editor's): shared_look_status_font, secondary colour, truncated in the
 * middle (a path keeps both ends), added to `bar` and centred VISUALLY on
 * `middle` — the middle of its capital letters, not of its frame, which
 * carries room for descenders and would sit the text low.  The caller
 * places it horizontally.  shared_ui_use_ui_font leaves it at its size.
 *
 * Inputs:
 *   bar       — the view it goes in
 *   middle    — the y the text is centred on (the bar's middle)
 *   alignment — its text alignment
 *
 * Output: the label.
 */
NSTextField *shared_ui_status_label(NSView *bar, NSLayoutYAxisAnchor *middle, NSTextAlignment alignment);

/*
 * shared_ui_use_ui_font — give everything under a view the apps' text
 * size (shared_look_ui_font), keeping each font's weight and slant;
 * labelled buttons, check boxes, radios, pop-ups, steppers and editable
 * fields also take the small control size, which is drawn for that size
 * of text.  A table (a sidebar, a list) and what is under it, and status
 * labels (shared_ui_status_label), keep their own: table cells set their
 * fonts themselves.  Called once a window's content is built.
 *
 * Inputs:
 *   root — the view to start at (itself included)
 */
void shared_ui_use_ui_font(NSView *root);

/*
 * shared_ui_select_on_mouse_down — select the row under a plain click on
 * the mouse-DOWN, as Finder does (a stock table selects only on mouse-up,
 * once it knows the click is not a drag).  A table's mouseDown: calls
 * this, then super, whose tracking loop still tells clicks from drags and
 * sends double-clicks (SharedTable does).  An already-selected row is
 * left alone, so a multi-row selection can still be dragged, as are ⌘-,
 * ⇧- and ^-clicks, and a press on a button in a cell (ticking an
 * unselected row's checkbox must not drop the selection).  The delegate
 * is asked first, as a click would ask it (selectionShouldChangeInTableView:,
 * then tableView:selectionIndexesForProposedSelection: or else
 * tableView:shouldSelectRow:), so a row it refuses — a sidebar's Tags
 * header — stays unselectable.
 *
 * Inputs:
 *   table — the table receiving the click
 *   event — its mouse-down event
 */
void shared_ui_select_on_mouse_down(NSTableView *table, NSEvent *event);

/*
 * SharedTable — THE table view of both apps: every list is one (or a
 * subclass of one).  It selects a clicked row on the mouse-down
 * (shared_ui_select_on_mouse_down), and Return or keypad Enter with a
 * selection sends its doubleAction, as a double-click does, so a row that
 * stands for something opens on both.  The action reads which rows it
 * applies to with shared_ui_activated_rows.  A table with a fill column
 * (shared_ui_fit_columns) stays as wide as its pane: when the pane gets
 * narrower under a wider table, the fill column is placed again
 * (shared_ui_place_fill_column).  Everything else is NSTableView's own.
 */
@interface SharedTable : NSTableView
@property (nonatomic, readonly) BOOL by_key;   /* YES while Return/Enter sends */
@end

/*
 * shared_ui_activated_rows — the rows a table's doubleAction applies to:
 * the double-clicked row, or the selection when Return/Enter sent it.
 *
 * Inputs:
 *   table — the table that sent the action
 *
 * Output: the row indexes; empty for a double-click on no row.
 */
NSIndexSet *shared_ui_activated_rows(SharedTable *table);

/*
 * shared_ui_fit_columns — size a table's fitted columns to their content
 * and give its fill column exactly what is left, so the table is as wide
 * as its pane.  A column's role is its resizing mask: THE fill column
 * (Title, Task) autoresizes; a fitted column is resized by the user only;
 * a fixed one (NSTableColumnNoResizing: a checkbox) is left alone.  A
 * fitted column is as wide as its widest cell text (the first
 * shared_look_fit_rows_max rows, in the apps' text size, plus the cell
 * padding) or its header (the title in bold, as the sorted column draws
 * it, plus room for the sort indicator when the column sorts), whichever
 * is wider, never under its minWidth.  Short of room, the fitted columns
 * give back what the fill column's floor needs, the last first, each down
 * to its own floor.  Not laid out yet (no room), the fit runs again on
 * the next turn of the run loop.
 *
 * Inputs:
 *   table — the table, in its scroll view
 *   full  — YES (a navigation, a column shown): every fitted column is
 *           reset to its width, even narrower; NO (a content refresh): one
 *           is only widened, so a column the user widened stays
 *   text  — what a cell shows: the column's and the row's text, nil or
 *           empty for none
 */
void shared_ui_fit_columns(NSTableView *table, BOOL full,
                           NSString *(^text)(NSTableColumn *column, NSInteger row));

/*
 * shared_ui_place_fill_column — give the fill column what the pane has
 * left after the other columns (the last step of shared_ui_fit_columns,
 * on its own): for a pane that was resized under the table.  Nothing
 * happens without a fill column or before the table is laid out.
 *
 * Inputs:
 *   table — the table, in its scroll view
 */
void shared_ui_place_fill_column(NSTableView *table);

/*
 * SharedFlippedView — a plain container whose y grows downward: the
 * document view of a scroll view whose content should start at the top
 * (a scroll view shows a non-flipped document's BOTTOM first).
 */
@interface SharedFlippedView : NSView
@end

/*
 * shared_ui_spacer — an empty view that takes the spare room in a stack
 * view (low hugging priority), so what follows it hugs the far edge.
 *
 * Output: the view.
 */
NSView *shared_ui_spacer(void);

/*
 * shared_ui_pin_edges — lay a view over another: its four edges on that
 * view's (constraints activated).
 *
 * Inputs:
 *   view — the view to place, already in `to`'s view hierarchy and with
 *          translatesAutoresizingMaskIntoConstraints NO
 *   to   — the view whose edges it takes
 */
void shared_ui_pin_edges(NSView *view, NSView *to);

/*
 * shared_ui_heading — a bold section heading in the apps' text size
 * (Settings' "Appearance", an editor's "Notes").
 *
 * Inputs:
 *   text — the heading
 *
 * Output: the label.
 */
NSTextField *shared_ui_heading(NSString *text);

/*
 * shared_ui_note — secondary text that wraps at a width (a setting's
 * explanation, a hint), in the apps' text size, not selectable.  The
 * width is stated because a wrapping label has no fitting height without
 * one, and a window sized from its content's fitting height needs it.
 *
 * Inputs:
 *   text  — the text; may be empty and set later
 *   width — where it wraps, in points
 *
 * Output: the label.
 */
NSTextField *shared_ui_note(NSString *text, CGFloat width);

/*
 * shared_ui_copy_link — a borderless "copy" link to sit beside a value
 * (a path, a digest), as in the Files app's Get Info.
 *
 * Inputs:
 *   target — receives the action
 *   action — sent on a click
 *
 * Output: the button.
 */
NSButton *shared_ui_copy_link(id target, SEL action);

/*
 * shared_ui_select_radio — make radio buttons act as one group: the chosen
 * one on, the others off.
 *
 * Inputs:
 *   group  — the group's buttons
 *   chosen — the one clicked
 */
void shared_ui_select_radio(NSArray<NSButton *> *group, NSButton *chosen);

/*
 * shared_ui_emoji_field — Edit Tag's emoji slot: a small text field that
 * holds at most one character and opens the system's emoji picker when
 * clicked.  The picker is the system's Character Viewer, which types into
 * whatever text is being edited, so the slot has to be a real text field.
 *
 * Inputs:
 *   emoji — the current emoji; empty for none
 *
 * Output: the field, shared_look_tool_emoji_w wide, in the apps' text size.
 */
NSTextField *shared_ui_emoji_field(NSString *emoji);

/* ── Tags ───────────────────────────────────────────────────────────────── */

/*
 * shared_ui_tag_label — a tag as the sidebars, the Favorites bars and the
 * window titles show it: its emoji, two spaces and its name, or the name
 * alone when it has no emoji.
 *
 * Inputs:
 *   emoji — the tag's emoji; empty or nil for none
 *   name  — its name
 *
 * Output: the label.
 */
NSString *shared_ui_tag_label(NSString *emoji, NSString *name);

/*
 * shared_ui_label_name — the bare name in a label of shared_ui_tag_label's
 * form: what follows the emoji and its two spaces, or the whole label when
 * it has none.  For type-select and VoiceOver, which must not start at the
 * emoji.
 *
 * Inputs:
 *   label — the label
 *
 * Output: the name.
 */
NSString *shared_ui_label_name(NSString *label);

/* ── The About panel ────────────────────────────────────────────────────── */

/*
 * shared_ui_show_about — the standard About panel with the apps' credits:
 * a lead line (Notes: the database and its counts; Tasks: its motto),
 * then "camb.io · BSD License", each a link, centred; the app's artwork
 * as its icon; and "built <date>" from the bundle's build stamp as the
 * version line.
 *
 * Inputs:
 *   lead      — the first line(s) of the credits
 *   icon      — the artwork (shared_ui_app_icon); nil for the bundle's
 *   stamp_key — the Info.plist key holding the build date, ISO 8601; a
 *               missing stamp shows no version line
 */
void shared_ui_show_about(NSString *lead, NSImage *icon, NSString *stamp_key);

/* ── Formatting ─────────────────────────────────────────────────────────── */

/*
 * shared_ui_format_bytes — a byte count as Finder shows it ("12.3 MB").
 * Thread-safe.
 *
 * Inputs:
 *   bytes — the count
 *
 * Output: the text.
 */
NSString *shared_ui_format_bytes(int64_t bytes);

/* The dates the apps show, as NSDateFormatter patterns.                     */
extern NSString *const shared_ui_date_list;   /* "Jun 3, 2026 14:05": lists      */
extern NSString *const shared_ui_date_day;    /* "Jun 3, 2026": due dates        */
extern NSString *const shared_ui_date_iso;    /* "2026-06-03": typed, AI prompts */

/*
 * shared_ui_format_date — a UNIX time in local time, in a date pattern (one
 * of the above, or another).  One shared formatter per pattern: never one
 * per table cell.  Thread-safe.
 *
 * Inputs:
 *   unix_time — seconds since the epoch
 *   format    — the NSDateFormatter pattern
 *
 * Output: the text.
 */
NSString *shared_ui_format_date(int64_t unix_time, NSString *format);
