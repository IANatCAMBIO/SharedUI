/* ===========================================================================
 * shared_look.h — the look Notes and Tasks share: the sizes and colours of
 * the interface elements both apps build the same way (shared_ui.h,
 * shared_tool_panel.h), defined ONCE here so the two cannot drift.
 *
 * Each app keeps its own look.h for what only it has (Notes' editor and
 * image viewer, Tasks' Kanban board and day planner).  A value here is
 * used under this name in both apps; no app defines a copy or an alias.
 *
 * COLOURS.  Every colour has a light and a dark value.  Drawing code
 * picks with shared_look_pick(colour, dark); AppKit code asks
 * shared_ui_color for an NSColor that follows the appearance by itself.
 * Chrome that AppKit draws — windows, sidebars, table rows, selection,
 * labels — uses the system's semantic colours and has no entry here.
 *
 * SIZES are in points, TIMES in seconds.
 *
 * Plain C, so an app's C code (Notes' layout engine) can use it.
 * =========================================================================== */

#ifndef SHARED_LOOK_H
#define SHARED_LOOK_H

#include <stdbool.h>

/* One colour, components 0..1. */
typedef struct {
    double r, g, b, a;
} shared_rgba_t;

/* A colour as the apps define it: one value per appearance. */
typedef struct {
    shared_rgba_t light;
    shared_rgba_t dark;
} shared_color_t;

/*
 * shared_look_pick — the value of a colour for an appearance.
 *
 * Inputs:
 *   color — the colour
 *   dark  — true under a dark appearance
 *
 * Output: the colour to draw with.
 */
static inline shared_rgba_t
shared_look_pick(shared_color_t color, bool dark)
{
    return dark ? color.dark : color.light;
}

/* ── Type ─────────────────────────────────────────────────────────────────── */

/* THE size of an app's own text: labels, buttons, fields, table cells,
 * status bars, tool panels (shared_ui_use_ui_font applies it to a
 * window).  The sidebars (the system font) and a note's own text keep
 * other sizes. */
static const double shared_look_ui_font     = 11.0;

/* ── Status bars ──────────────────────────────────────────────────────────── */

static const double shared_look_status_font  = 11.0;   /* the Files app's status size            */
static const double shared_look_status_h     = 20.0;   /* the bar, under a 1 pt separator        */
static const double shared_look_status_inset = 8.0;    /* its labels, from either edge           */
static const double shared_look_status_hold  = 3.0;    /* a status message stays this long ...   */
static const double shared_look_status_fade  = 1.0;    /* ... then fades out over this           */

/* ── The blue hero strip (the Tasks reminders window) and tool panels ──────── */

static const shared_color_t shared_look_hero         = { { 0.000, 0.447, 0.776, 1 }, { 0.000, 0.447, 0.776, 1 } };  /* the strip's fill (white text) */
static const shared_color_t shared_look_hero_sub     = { { 0.880, 0.880, 0.880, 1 }, { 0.880, 0.880, 0.880, 1 } };  /* its second line               */
static const shared_color_t shared_look_hero_problem = { { 1.000, 0.920, 0.550, 1 }, { 1.000, 0.920, 0.550, 1 } };  /* ... when it reports a problem */

static const double shared_look_hero_h          = 43.0;   /* the strip                             */
static const double shared_look_hero_pad        = 16.0;   /* its left and right inset              */
static const double shared_look_hero_gap        = 3.0;    /* title to subtitle                     */
static const double shared_look_hero_icon       = 22.0;   /* its symbol                            */
static const double shared_look_hero_icon_gap   = 10.0;   /* symbol to the text                    */
static const double shared_look_head_icon       = 28.0;   /* a tool panel's symbol, centred at its top */
static const double shared_look_head_gap        = 6.0;    /* symbol to title, title to subtitle        */
static const double shared_look_tool_min_w      = 340.0;  /* a panel's least width                 */
static const double shared_look_tool_pad        = 16.0;   /* around the caller's controls          */
static const double shared_look_tool_bar_h      = 40.0;   /* the button bar                        */
static const double shared_look_tool_btn_h      = 25.0;
static const double shared_look_tool_btn_w      = 83.0;   /* narrowest button                      */
static const double shared_look_tool_btn_gap    = 8.0;
static const double shared_look_tool_btn_margin = 12.0;   /* to the window edge                    */
static const double shared_look_tool_btn_pad    = 24.0;   /* a long title to its button's edges    */
static const double shared_look_tool_msg_font   = 10.0;   /* the message's text, under the headline */
static const double shared_look_tool_msg_w      = 388.0;  /* wrapped message text                  */
static const double shared_look_tool_msg_max_h  = 240.0;  /* taller messages scroll                */
static const double shared_look_tool_emoji_w    = 44.0;   /* Edit Tag's emoji slot                 */

/* ── Sidebar and Favorites bar ────────────────────────────────────────────── */

static const double shared_look_sidebar_w        = 180.0;  /* initial, until dragged (Files')      */
static const double shared_look_sidebar_min_w    = 160.0;  /* the narrowest drag                   */
static const double shared_look_sidebar_row_h    = 26.0;   /* a sidebar row                        */
static const double shared_look_sidebar_text_pad = 4.0;    /* a row's text, from the left          */
static const double shared_look_sidebar_count_pad = 6.0;   /* its count, from the right            */
static const double shared_look_favorites_bar_h  = 28.0;   /* the button strip; a 1 pt rule under it */
static const double shared_look_favorite_btn_h   = 24.0;   /* a favorite tag's button in it        */
static const double shared_look_favorite_btn_min_w = 60.0;
static const double shared_look_favorite_text_pad = 16.0;  /* a button's title to its edges        */
static const double shared_look_favorite_gap     = 4.0;    /* between buttons                      */
static const double shared_look_favorites_pad    = 6.0;    /* the strip's first button, from the left */
static const double shared_look_favorite_slide_s = 0.15;   /* a button sliding aside for a drag    */
static const double shared_look_drag_slop        = 4.0;    /* a press moving less is a click       */

/* ── Text ─────────────────────────────────────────────────────────────────── */

static const shared_color_t shared_look_link = { { 0.110, 0.443, 0.847, 1 }, { 0.471, 0.682, 0.929, 1 } };  /* a clickable word: "copy", "Advanced", "Show all" */

/* ── Due dates ────────────────────────────────────────────────────────────── */

static const shared_color_t shared_look_due_overdue = { { 0.753, 0.110, 0.157, 1 }, { 0.965, 0.380, 0.318, 1 } };
static const shared_color_t shared_look_due_today   = { { 0.820, 0.604, 0.000, 1 }, { 0.973, 0.894, 0.361, 1 } };
static const shared_color_t shared_look_due_ahead   = { { 0.149, 0.635, 0.412, 1 }, { 0.341, 0.890, 0.537, 1 } };

/* ── Lists ────────────────────────────────────────────────────────────────── */

static const double shared_look_check_col_w = 28.0;    /* a list's done-checkbox column        */
static const double shared_look_cell_pad_h  = 4.0;     /* a list cell's text, from either edge */
static const double shared_look_label_inset = 2.0;     /* an NSTextField draws its text this
                                                        * far inside its frame                 */
static const double shared_look_header_fit_pad   = 10.0; /* a fitted column's header title to
                                                          * the column's edges                 */
static const double shared_look_sort_indicator_w = 22.0; /* ... plus this when it sorts        */
static const long   shared_look_fit_rows_max     = 2000; /* rows measured to fit a column      */

/* ── Editors ──────────────────────────────────────────────────────────────── */

static const double shared_look_autosave_delay = 0.6;   /* typing pauses this long before an
                                                         * editor saves                        */
static const int    shared_look_tag_suggestions_max = 8; /* tag names offered while typing one */
static const double shared_look_tag_popup_row_h = 20.0;  /* the tag suggestion list (shared_tag_popup.h): a row ... */
static const double shared_look_tag_popup_min_w = 120.0; /* ... its least width ... */
static const double shared_look_tag_popup_pad   = 10.0;  /* ... and its text's inset, each side */
static const double shared_look_popup_radius    = 5.0;   /* a pop-up list's corners, as the windows' */

/* ── Command buttons (shared_commands.h) ──────────────────────────────────── */

static const double shared_look_cmd_btn      = 32.0;   /* an icon-only command button over a
                                                        * pane (Compact mode's floating pair):
                                                        * its edge ...                         */
static const double shared_look_cmd_btn_icon = 16.0;   /* ... and its glyph's point size (the
                                                        * toolbar sizes its own)               */

/* ── Windows ──────────────────────────────────────────────────────────────── */

static const double shared_look_screen_margin    = 12.0;   /* a window placed in the screen's
                                                            * lower-right corner (a new editor,
                                                            * Quick Task), this clear of the work
                                                            * area's edges                         */
static const double shared_look_toolbar_search_w = 220.0;  /* the library toolbar's search field   */

#endif /* SHARED_LOOK_H */
