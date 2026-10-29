#import "shared_day_planner.h"
#import "shared_tool_panel.h"
#import "shared_ui.h"

#include <math.h>
#include <time.h>

/* Snap granularity for time placement, resize and move. */
static const NSInteger snap_minutes  = 15;

/* Height of the date-navigation header above the scroll area. */
static const CGFloat   header_h      = 36.0;

/* Height of the all-day strip under the header, when the day has any
 * all-day events (zero otherwise). */
static const CGFloat   all_day_h     = 20.0;

/* Width of the calendar-coloured bar down a calendar event's left edge. */
static const CGFloat   event_bar_w   = 3.0;

/* ── SharedDayItem ─────────────────────────────────────────────────────── */

static NSString *format_block_time(int64_t start_unix, int duration_min);

/* What the planner adds to an item for drawing it. */
@interface SharedDayItem ()
@property (nonatomic, strong) NSColor *event_fill;  /* an event: its calendar's colour, dimmed */
@property (nonatomic, strong) NSColor *event_bar;   /* an event: the colour itself            */
/* Side-by-side placement among the blocks it overlaps: column `column`
 * of `columns` (layout_columns). */
@property (nonatomic) NSUInteger column;
@property (nonatomic) NSUInteger columns;
/* The "H:MM–H:MM (Xhr Ymin)" line, built when first drawn and again after
 * the start or the duration changes; drawRect runs per frame of a drag. */
@property (nonatomic, readonly) NSString *time_text;
@end

@implementation SharedDayItem {
    NSString *_time_text;
}

- (void)setStart_unix:(int64_t)start_unix { _start_unix = start_unix; _time_text = nil; }
- (void)setDuration:(int)duration         { _duration   = duration;   _time_text = nil; }

/*
 * is_event — see shared_day_planner.h.
 *
 * Output: YES for a calendar event.
 */
- (BOOL)
is_event
{
    return _event_id != nil;
}

/*
 * time_text — the block's time line, made once per start and duration.
 *
 * Output: the text.
 */
- (NSString *)
time_text
{
    if (_time_text == nil) _time_text = format_block_time(_start_unix, _duration);
    return _time_text;
}

@end

/* ── Forward declaration ─────────────────────────────────────────────── */

@class SharedDayCanvas;

/* ── SharedDayPlanner private interface (visible to the canvas below) ── */

@interface SharedDayPlanner ()
@property (nonatomic, weak)   id<SharedDayPlannerDelegate>    delegate;
@property (nonatomic, strong) NSScrollView                    *scroll;
@property (nonatomic, strong) SharedDayCanvas                 *canvas;
@property (nonatomic, strong) NSTimer                         *clock_timer;
@property (nonatomic, strong) NSMutableArray<SharedDayItem *> *items;
@property (nonatomic)         BOOL                             is_shut_down;
@property (nonatomic)         NSInteger                        days_offset; /* 0 = today */
@property (nonatomic, weak)   NSTextField                     *date_label;
@property (nonatomic, weak)   NSButton                        *today_button;
@property (nonatomic, weak)   NSTextField                     *all_day_label;
@property (nonatomic, strong) NSLayoutConstraint              *all_day_height;
- (BOOL)editable;
- (void)committed_block:(SharedDayItem *)item stretched:(BOOL)stretched;
@end

/* ── SharedDayCanvas ───────────────────────────────────────────────────── */

@interface SharedDayCanvas : NSView <NSDraggingDestination>
@property (nonatomic, weak) SharedDayPlanner *planner;
/* Resize tracking */
@property (nonatomic) BOOL    resizing;
@property (nonatomic) BOOL    resize_top;           /* YES = dragging start, NO = dragging end */
@property (nonatomic) int64_t resize_id;
@property (nonatomic) CGFloat resize_start_y;
@property (nonatomic) int     resize_orig_duration;
@property (nonatomic) int64_t resize_orig_start_unix; /* top-edge: original start  */
@property (nonatomic) int64_t resize_orig_end_unix;   /* top-edge: fixed end time  */
/* Move tracking */
@property (nonatomic) BOOL    move_pending;   /* mouseDown seen, drag not yet started */
@property (nonatomic) BOOL    moving;
@property (nonatomic) int64_t move_id;
@property (nonatomic) int64_t move_orig_start_unix;
@property (nonatomic) CGFloat move_start_mouse_y;
/* Drop highlight Y, NAN when no drag is over */
@property (nonatomic) CGFloat drop_y;
/* Where the current-time line was last drawn, for redrawing just it */
@property (nonatomic) CGFloat now_y;
/* Selected task ids */
@property (nonatomic, strong) NSMutableSet<NSNumber *> *selected_ids;
/* The hours shown, [first_h, end_h): business hours widened to fit the
 * day's blocks (fit_hours) */
@property (nonatomic) NSInteger first_h;
@property (nonatomic) NSInteger end_h;
@end

/*
 * day_bounds — the local midnights that bound today + offset days, by the
 * calendar: a day across a clock change is 23 or 25 hours, not 24.
 *
 * Inputs:
 *   offset — days relative to today; 0 = today, 1 = tomorrow, -1 = yesterday
 *   lo     — out: unix seconds of that day's local midnight
 *   hi     — out: unix seconds of the next day's local midnight
 */
static void
day_bounds(NSInteger offset, int64_t *lo, int64_t *hi)
{
    NSCalendar *cal   = NSCalendar.currentCalendar;
    NSDate     *today = [cal startOfDayForDate:[NSDate date]];
    NSDate     *day   = [cal startOfDayForDate:[cal dateByAddingUnit:NSCalendarUnitDay value:offset
                                                              toDate:today options:0]];
    NSDate     *next  = [cal startOfDayForDate:[cal dateByAddingUnit:NSCalendarUnitDay value:1
                                                              toDate:day options:0]];
    *lo = (int64_t)day.timeIntervalSince1970;
    *hi = (int64_t)next.timeIntervalSince1970;
}

/*
 * midnight_for_offset — unix seconds of local midnight for today + offset
 * days (day_bounds).
 *
 * Inputs:
 *   offset — days relative to today
 *
 * Output:
 *   unix seconds of that day's local midnight.
 */
static int64_t
midnight_for_offset(NSInteger offset)
{
    int64_t lo, hi;
    day_bounds(offset, &lo, &hi);
    return lo;
}

@implementation SharedDayCanvas

- (BOOL)isFlipped { return YES; }
- (BOOL)acceptsFirstMouse:(NSEvent *)event { return YES; }

- (void)setFrameSize:(NSSize)size
{
    [super setFrameSize:size];
    [self setNeedsDisplay:YES];
}

/* ── Coordinate helpers ───────────────────────────────────────────────── */

/*
 * y_for_unix: — canvas Y for a unix timestamp on the displayed day.
 *
 * Inputs:
 *   t — unix seconds
 *
 * Output:
 *   Y in flipped canvas coordinates (Y=0 at top).
 */
- (CGFloat)
y_for_unix:(int64_t)t
{
    return [self y_for_unix:t midnight:[self midnight]];
}

/*
 * midnight — the displayed day's local midnight.  A loop over the items
 * takes it once rather than once per item (day_bounds is calendar
 * arithmetic).
 *
 * Output:
 *   unix seconds.
 */
- (int64_t)
midnight
{
    return midnight_for_offset(self.planner ? self.planner.days_offset : 0);
}

/*
 * y_for_unix:midnight: — canvas Y for a unix timestamp, the day's midnight
 * given.
 *
 * Inputs:
 *   t   — unix seconds
 *   mid — the displayed day's local midnight
 *
 * Output:
 *   Y in flipped canvas coordinates (Y=0 at top).
 */
- (CGFloat)
y_for_unix:(int64_t)t midnight:(int64_t)mid
{
    double hours = (double)(t - mid) / 3600.0;
    return shared_look_day_planner_pad_v +
           (hours - (double)self.first_h) * shared_look_day_planner_hour_h;
}

/*
 * unix_for_y: — unix timestamp for a canvas Y coordinate, snapped to
 * snap_minutes and clamped to the visible hour range of the displayed day.
 *
 * Inputs:
 *   y — Y in flipped canvas coordinates
 *
 * Output:
 *   unix seconds within the displayed day.
 */
- (int64_t)
unix_for_y:(CGFloat)y
{
    NSInteger offset   = self.planner ? self.planner.days_offset : 0;
    double    hours    = (y - shared_look_day_planner_pad_v) / shared_look_day_planner_hour_h
                         + (double)self.first_h;
    int total_min = (int)round(hours * 60.0);
    total_min = (total_min / (int)snap_minutes) * (int)snap_minutes;
    int lo_min = (int)self.first_h * 60;
    int hi_min = (int)self.end_h   * 60 - (int)snap_minutes;
    if (total_min < lo_min) total_min = lo_min;
    if (total_min > hi_min) total_min = hi_min;
    return midnight_for_offset(offset) + (int64_t)total_min * 60;
}

/*
 * item_rect:midnight: — canvas rectangle for a block, the day's midnight
 * given.
 *
 * Inputs:
 *   item — the item
 *   mid  — the displayed day's local midnight
 *
 * Output:
 *   block frame in canvas coordinates.
 */
- (NSRect)
item_rect:(SharedDayItem *)item midnight:(int64_t)mid
{
    CGFloat   left = shared_look_day_planner_label_w + shared_look_day_planner_block_inset;
    CGFloat   all  = NSWidth(self.bounds) - left - shared_look_day_planner_block_inset;
    NSUInteger n   = item.columns > 0 ? item.columns : 1;
    CGFloat   w    = all / (CGFloat)n;
    CGFloat   x    = left + w * (CGFloat)item.column;
    if (n > 1) w  -= shared_look_day_planner_block_inset;
    CGFloat y = [self y_for_unix:item.start_unix midnight:mid];
    CGFloat h = (item.duration / 60.0) * shared_look_day_planner_hour_h;
    CGFloat min_h = ((CGFloat)snap_minutes / 60.0) * shared_look_day_planner_hour_h;
    if (h < min_h) h = min_h;
    return NSMakeRect(x, y, w, h);
}

/*
 * item_named: — the item of a task.
 *
 * Inputs:
 *   task_id — the task
 *
 * Output:
 *   the item, or nil when the day has none for it.
 */
- (SharedDayItem *)
item_named:(int64_t)task_id
{
    for (SharedDayItem *item in self.planner.items) {
        if (!item.is_event && item.task_id == task_id) return item;
    }
    return nil;
}

/*
 * item_at:events:midnight: — the task's or the event's block under a
 * point.
 *
 * Inputs:
 *   pt     — canvas coordinates
 *   events — YES for an event's block, NO for a task's
 *   mid    — the displayed day's local midnight
 *
 * Output:
 *   the item, or nil.
 */
- (SharedDayItem *)
item_at:(NSPoint)pt events:(BOOL)events midnight:(int64_t)mid
{
    for (SharedDayItem *item in self.planner.items) {
        if (item.is_event == events && NSPointInRect(pt, [self item_rect:item midnight:mid])) return item;
    }
    return nil;
}

/*
 * redraw_block_from:to: — invalidate what a block's move or resize
 * uncovers and covers: its old frame and its new one, with room for the
 * stroke, rather than the whole canvas per frame of the drag.
 *
 * Inputs:
 *   before — the block's frame before the change
 *   after  — its frame after
 */
- (void)
redraw_block_from:(NSRect)before to:(NSRect)after
{
    [self setNeedsDisplayInRect:NSInsetRect(NSUnionRect(before, after), -2.0, -2.0)];
}

/*
 * set_drop_y: — move the drop indicator, redrawing only where it was and
 * where it is.
 *
 * Inputs:
 *   y — the indicator's canvas Y, or NAN for none
 */
- (void)
set_drop_y:(CGFloat)y
{
    CGFloat w = NSWidth(self.bounds);
    if (!isnan(self.drop_y)) [self setNeedsDisplayInRect:NSMakeRect(0, self.drop_y - 2.0, w, 4.0)];
    self.drop_y = y;
    if (!isnan(y)) [self setNeedsDisplayInRect:NSMakeRect(0, y - 2.0, w, 4.0)];
}

/*
 * redraw_now_line — the clock moved: redraw the current-time line where
 * it was drawn and where it now belongs, and nothing else.
 */
- (void)
redraw_now_line
{
    CGFloat w   = NSWidth(self.bounds);
    CGFloat now = [self y_for_unix:(int64_t)time(NULL)];
    [self setNeedsDisplayInRect:NSMakeRect(0, self.now_y - 6.0, w, 12.0)];
    [self setNeedsDisplayInRect:NSMakeRect(0, now - 6.0, w, 12.0)];
}

/* ── Drawing helpers ──────────────────────────────────────────────────── */

/*
 * format_block_time — build the "H:MM–H:MM (Xhr Ymin)" subtitle string.
 *
 * Inputs:
 *   start_unix   — block start as unix seconds
 *   duration_min — block length in minutes
 *
 * Output:
 *   autoreleased NSString.
 */
static NSString *
format_block_time(int64_t start_unix, int duration_min)
{
    time_t    ts   = (time_t)start_unix;
    time_t    te   = (time_t)(start_unix + (int64_t)duration_min * 60);
    struct tm s    = *localtime(&ts);
    struct tm e    = *localtime(&te);

    int sh = s.tm_hour % 12; if (sh == 0) sh = 12;
    int eh = e.tm_hour % 12; if (eh == 0) eh = 12;

    NSString *start_str = s.tm_min == 0
        ? [NSString stringWithFormat:@"%d", sh]
        : [NSString stringWithFormat:@"%d:%02d", sh, s.tm_min];
    NSString *end_str   = e.tm_min == 0
        ? [NSString stringWithFormat:@"%d", eh]
        : [NSString stringWithFormat:@"%d:%02d", eh, e.tm_min];

    int hrs  = duration_min / 60;
    int mins = duration_min % 60;
    NSString *dur;
    if      (mins == 0) dur = [NSString stringWithFormat:@"%dhr",        hrs];
    else if (hrs  == 0) dur = [NSString stringWithFormat:@"%dmin",       mins];
    else                dur = [NSString stringWithFormat:@"%dhr %dmin",  hrs, mins];

    return [NSString stringWithFormat:@"%@–%@ (%@)", start_str, end_str, dur];
}

/* ── Drawing ──────────────────────────────────────────────────────────── */

/* What every frame draws with, made once: the fonts, the attribute
 * dictionaries, the hour labels and their sizes.  The colours are dynamic
 * (shared_ui_color_dimmed), so one set serves light and dark. */
typedef struct {
    NSFont       *label_font;
    NSDictionary *label_attrs;
    NSDictionary *title_attrs;
    NSDictionary *time_attrs;
    NSDictionary *event_attrs;               /* a calendar event's title */
    NSDictionary *title_compact_attrs;       /* ... a task's and an event's, smaller, */
    NSDictionary *event_compact_attrs;       /* ... for a block too short for two lines */
    CGFloat       title_h;
    CGFloat       time_h;
    CGFloat       compact_h;
    NSArray<NSString *> *hour_labels;         /* indexed by hour, 0-23 */
    CGFloat       hour_label_h;
    NSColor      *acc_fill_n, *acc_bord_n, *done_fill_n, *done_bord_n;
    NSColor      *acc_fill_s, *acc_bord_s, *done_fill_s, *done_bord_s;
} canvas_look_t;

/*
 * canvas_look — the shared drawing resources.
 *
 * Output:
 *   the resources (static storage).
 */
static const canvas_look_t *
canvas_look(void)
{
    static canvas_look_t   look;
    static dispatch_once_t once;

    dispatch_once(&once, ^{
        look.label_font = [NSFont monospacedDigitSystemFontOfSize:10.0
                                                           weight:NSFontWeightRegular];
        look.label_attrs = @{ NSFontAttributeName:            look.label_font,
                              NSForegroundColorAttributeName: NSColor.secondaryLabelColor };
        NSFont *title_font = [NSFont systemFontOfSize:shared_look_ui_font];
        NSFont *time_font  = [NSFont systemFontOfSize:shared_look_ui_font - 1.0];
        look.title_attrs = @{ NSFontAttributeName:            title_font,
                              NSForegroundColorAttributeName: NSColor.labelColor };
        look.time_attrs  = @{ NSFontAttributeName:            time_font,
                              NSForegroundColorAttributeName: NSColor.secondaryLabelColor };
        look.event_attrs = @{ NSFontAttributeName:            title_font,
                              NSForegroundColorAttributeName: NSColor.secondaryLabelColor };
        NSFont *compact_font = [NSFont systemFontOfSize:shared_look_ui_font - 2.0];
        look.title_compact_attrs = @{ NSFontAttributeName:            compact_font,
                                      NSForegroundColorAttributeName: NSColor.labelColor };
        look.event_compact_attrs = @{ NSFontAttributeName:            compact_font,
                                      NSForegroundColorAttributeName: NSColor.secondaryLabelColor };
        look.compact_h = compact_font.ascender - compact_font.descender + compact_font.leading;
        look.title_h = title_font.ascender - title_font.descender + title_font.leading;
        look.time_h  = time_font.ascender  - time_font.descender  + time_font.leading;

        NSMutableArray<NSString *> *labels = [NSMutableArray array];
        /* The 24-hour clock, as the apps show every time. */
        for (NSInteger h = 0; h < 24; h++) [labels addObject:[NSString stringWithFormat:@"%02ld:00", (long)h]];
        look.hour_labels  = [labels copy];
        look.hour_label_h = [labels.firstObject sizeWithAttributes:look.label_attrs].height;

        /* Task blocks — two tones: normal and selected (darker) */
        NSColor *accent = NSColor.controlAccentColor;
        NSColor *second = NSColor.secondaryLabelColor;
        look.acc_fill_n  = shared_ui_color_dimmed(accent, 18);
        look.acc_bord_n  = shared_ui_color_dimmed(accent, 55);
        look.done_fill_n = shared_ui_color_dimmed(second, 10);
        look.done_bord_n = shared_ui_color_dimmed(second, 28);
        look.acc_fill_s  = shared_ui_color_dimmed(accent, 38);
        look.acc_bord_s  = shared_ui_color_dimmed(accent, 82);
        look.done_fill_s = shared_ui_color_dimmed(second, 22);
        look.done_bord_s = shared_ui_color_dimmed(second, 52);
    });
    return &look;
}

/*
 * draw_block_text — a block's title, with its time under it when there is
 * room.  A block too short for a full title line (a 15-minute one) gets
 * the title alone, in the smaller font, centred on the block.
 *
 * Inputs:
 *   item          — the task or event
 *   r             — the block's frame
 *   left_extra    — extra inset on the left (an event's colour bar)
 *   title_attrs   — the title's attributes
 *   compact_attrs — the title's attributes for a short block
 *   look          — the shared drawing resources
 */
static void
draw_block_text(SharedDayItem *item, NSRect r, CGFloat left_extra,
                NSDictionary *title_attrs, NSDictionary *compact_attrs,
                const canvas_look_t *look)
{
    NSRect content = NSInsetRect(r, 4.0, 3.0);
    content.origin.x   += left_extra;
    content.size.width -= left_extra;

    if (NSHeight(content) < look->title_h) {
        NSRect line = NSMakeRect(content.origin.x, NSMinY(r) + (NSHeight(r) - look->compact_h) / 2.0,
                                 content.size.width, look->compact_h);
        [item.title drawInRect:line withAttributes:compact_attrs];
        return;
    }
    NSRect title_rect = NSMakeRect(content.origin.x, content.origin.y,
                                   content.size.width, look->title_h);
    [item.title drawInRect:title_rect withAttributes:title_attrs];
    NSRect time_rect = NSMakeRect(content.origin.x, NSMaxY(title_rect) + 1.0,
                                  content.size.width, look->time_h);
    if (NSMaxY(time_rect) <= NSMaxY(content))
        [item.time_text drawInRect:time_rect withAttributes:look->time_attrs];
}

/*
 * drawRect: — draw hour grid, task blocks, drop indicator, current time line.
 * Only what meets the dirty rectangle is laid out or drawn.
 *
 * Inputs:
 *   dirty — the rectangle to redraw
 */
- (void)
drawRect:(NSRect)dirty
{
    const canvas_look_t *look = canvas_look();
    NSInteger start_h = self.first_h;
    NSInteger end_h   = self.end_h;
    CGFloat   hour_h  = shared_look_day_planner_hour_h;
    CGFloat   pad     = shared_look_day_planner_pad_v;
    CGFloat   label_w = shared_look_day_planner_label_w;
    int64_t   mid     = [self midnight];

    [NSColor.textBackgroundColor setFill];
    NSRectFill(dirty);

    /* Thin separator between label column and block area */
    NSRect col_rule = NSMakeRect(label_w - 0.5, 0, 1.0, NSHeight(self.bounds));
    if (NSIntersectsRect(col_rule, dirty)) {
        [NSColor.separatorColor setFill];
        NSRectFill(col_rule);
    }

    for (NSInteger h = start_h; h <= end_h; h++) {
        CGFloat y = pad + (h - start_h) * hour_h;

        NSRect line = NSMakeRect(0, y - 0.5, NSWidth(self.bounds), 1.0);
        if (NSIntersectsRect(line, dirty)) {
            [NSColor.separatorColor setFill];
            NSRectFill(line);
        }

        if (h < end_h) {
            NSRect lrec = NSMakeRect(2.0, y - look->hour_label_h - 2.0, label_w - 4.0,
                                     look->hour_label_h);
            if (NSIntersectsRect(lrec, dirty)) {
                [look->hour_labels[(NSUInteger)h] drawInRect:lrec
                                                          withAttributes:look->label_attrs];
            }
        }
    }

    for (SharedDayItem *item in self.planner.items) {
        NSRect r = [self item_rect:item midnight:mid];
        if (!NSIntersectsRect(r, dirty)) continue;

        if (item.is_event) {
            [self draw_event:item in:r look:look];
            continue;
        }

        NSBezierPath *path =
            [NSBezierPath bezierPathWithRoundedRect:NSInsetRect(r, 0.5, 0.5)
                                            xRadius:4.0 yRadius:4.0];
        BOOL sel = [self.selected_ids containsObject:@(item.task_id)];
        if (item.done) {
            [sel ? look->done_fill_s : look->done_fill_n setFill];   [path fill];
            [sel ? look->done_bord_s : look->done_bord_n setStroke]; [path stroke];
        } else {
            [sel ? look->acc_fill_s : look->acc_fill_n setFill];   [path fill];
            [sel ? look->acc_bord_s : look->acc_bord_n setStroke]; [path stroke];
        }

        draw_block_text(item, r, 0.0, look->title_attrs, look->title_compact_attrs, look);
    }

    /* Drop indicator */
    if (!isnan(self.drop_y)) {
        NSRect mark = NSMakeRect(label_w, self.drop_y - 1.0,
                                 NSWidth(self.bounds) - label_w, 2.0);
        [NSColor.controlAccentColor setFill];
        NSRectFill(mark);
    }

    /* Current-time line: only shown when viewing today */
    if (!self.planner || self.planner.days_offset == 0) {
        CGFloat now_y = [self y_for_unix:(int64_t)time(NULL) midnight:mid];
        self.now_y = now_y;
        if (now_y >= pad && now_y <= NSMaxY(self.bounds) - pad) {
            NSRect tl = NSMakeRect(label_w - 5.0,
                                   now_y - shared_look_day_planner_time_w / 2.0,
                                   NSWidth(self.bounds) - label_w + 5.0,
                                   shared_look_day_planner_time_w);
            [[NSColor systemRedColor] setFill];
            NSRectFill(tl);
            /* Small circle at the left edge */
            NSRect dot = NSMakeRect(label_w - 7.0, now_y - 4.0, 8.0, 8.0);
            [[NSBezierPath bezierPathWithOvalInRect:dot] fill];
        }
    }
}

/*
 * draw_event:in:look: — draw a calendar event: a flat tint of its
 * calendar's colour with a solid bar down the left edge, unlike a task's
 * bordered block, so that what can be moved and what cannot tell apart.
 *
 * Inputs:
 *   item — the event
 *   r    — its frame
 *   look — the shared drawing resources
 */
- (void)
draw_event:(SharedDayItem *)item in:(NSRect)r look:(const canvas_look_t *)look
{
    NSRect body = NSInsetRect(r, 0.5, 0.5);
    [item.event_fill setFill];
    [[NSBezierPath bezierPathWithRoundedRect:body xRadius:4.0 yRadius:4.0] fill];
    [item.event_bar setFill];
    NSRectFill(NSMakeRect(NSMinX(body), NSMinY(body) + 1.0, event_bar_w, NSHeight(body) - 2.0));

    draw_block_text(item, r, event_bar_w, look->event_attrs, look->event_compact_attrs, look);
}

/*
 * view:stringForToolTip:point:userData: — a calendar event's tooltip:
 * its title and times (the block may be too short to show them), and the
 * planner's event_hint.
 *
 * Inputs:
 *   view  — this canvas
 *   tag   — the tooltip rectangle (unused)
 *   point — where the pointer is
 *   data  — unused
 *
 * Output:
 *   the text, or nil when no event is under the pointer.
 */
- (NSString *)
view:(NSView *)view stringForToolTip:(NSToolTipTag)tag point:(NSPoint)point userData:(void *)data
{
    SharedDayItem *item = [self item_at:point events:YES midnight:[self midnight]];
    if (item == nil) return nil;
    NSString *text = [NSString stringWithFormat:@"%@\n%@ · Google Calendar", item.title, item.time_text];
    NSString *hint = self.planner.event_hint;
    return hint.length > 0 ? [text stringByAppendingFormat:@"\n%@", hint] : text;
}

/* ── Drag destination ─────────────────────────────────────────────────── */

/*
 * draggingEntered: — a drag entered the canvas: accept if it carries one
 * of the planner's drop_types (the only types it is registered for).
 *
 * Inputs:
 *   info — the dragging session
 *
 * Output:
 *   NSDragOperationLink on acceptance, NSDragOperationNone otherwise.
 */
- (NSDragOperation)
draggingEntered:(id<NSDraggingInfo>)info
{
    NSArray<NSPasteboardType> *types = self.planner.drop_types;
    if (types.count == 0 || [info.draggingPasteboard availableTypeFromArray:types] == nil)
        return NSDragOperationNone;

    NSPoint pt = [self convertPoint:info.draggingLocation fromView:nil];
    [self set_drop_y:[self y_for_unix:[self unix_for_y:pt.y]]];
    return NSDragOperationLink;
}

/*
 * draggingUpdated: — the drag moved; update the indicator line.
 *
 * Inputs:
 *   info — the dragging session
 *
 * Output:
 *   NSDragOperationLink.
 */
- (NSDragOperation)
draggingUpdated:(id<NSDraggingInfo>)info
{
    NSPoint pt = [self convertPoint:info.draggingLocation fromView:nil];
    [self set_drop_y:[self y_for_unix:[self unix_for_y:pt.y]]];
    return NSDragOperationLink;
}

/*
 * draggingExited: — the drag left without dropping; clear the indicator.
 *
 * Inputs:
 *   info — the dragging session (unused)
 */
- (void)
draggingExited:(id<NSDraggingInfo>)info
{
    [self set_drop_y:NAN];
}

- (BOOL)prepareForDragOperation:(id<NSDraggingInfo>)info { return YES; }

/*
 * performDragOperation: — hand the drop and the time under it to the
 * delegate.
 *
 * Inputs:
 *   info — the dragging session
 *
 * Output:
 *   YES when the delegate took it.
 */
- (BOOL)
performDragOperation:(id<NSDraggingInfo>)info
{
    [self set_drop_y:NAN];
    NSPoint pt = [self convertPoint:info.draggingLocation fromView:nil];
    id<SharedDayPlannerDelegate> delegate = self.planner.delegate;
    if (![delegate respondsToSelector:@selector(day_planner:drop:start:)]) return NO;
    return [delegate day_planner:self.planner drop:info start:[self unix_for_y:pt.y]];
}

/*
 * concludeDragOperation: — clear the indicator after the drop.
 *
 * Inputs:
 *   info — the dragging session (unused)
 */
- (void)
concludeDragOperation:(id<NSDraggingInfo>)info
{
    self.drop_y = NAN;
    [self setNeedsDisplay:YES];
}

/* ── Mouse events (block move and resize, double-click to open) ─────── */

/*
 * mouseDown: — a double-click on a block opens it (the delegate's
 * open_task / open_event).  Otherwise, while the planner is editable:
 * select the clicked task's block, then begin a resize on the grip stripe
 * or arm a pending move on the block body; Cmd+click toggles the clicked
 * block into/out of the selection; a plain click in empty space clears
 * the selection.
 *
 * Inputs:
 *   event — the mouse-down event
 */
- (void)
mouseDown:(NSEvent *)event
{
    NSPoint pt        = [self convertPoint:event.locationInWindow fromView:nil];
    self.resize_id    = 0;
    self.resizing     = NO;
    self.move_id      = 0;
    self.move_pending = NO;
    self.moving       = NO;

    int64_t                       mid      = [self midnight];
    SharedDayPlanner             *planner  = self.planner;
    id<SharedDayPlannerDelegate>  delegate = planner.delegate;
    SharedDayItem                *item     = [self item_at:pt events:NO midnight:mid];

    if (event.clickCount == 2) {
        if (item != nil) {
            if ([delegate respondsToSelector:@selector(day_planner:open_task:)])
                [delegate day_planner:planner open_task:item.task_id];
            return;
        }
        SharedDayItem *ev = [self item_at:pt events:YES midnight:mid];
        if (ev != nil && [delegate respondsToSelector:@selector(day_planner:open_event:)]) {
            [delegate day_planner:planner open_event:ev];
            return;
        }
    }
    if (![planner editable]) return;

    if (item == nil) {
        /* Clicked empty space: clear selection */
        if (self.selected_ids.count > 0) {
            [self.selected_ids removeAllObjects];
            [self setNeedsDisplay:YES];
        }
        return;
    }

    /* Update selection */
    NSNumber *tid = @(item.task_id);
    if (event.modifierFlags & NSEventModifierFlagCommand) {
        if ([self.selected_ids containsObject:tid])
            [self.selected_ids removeObject:tid];
        else
            [self.selected_ids addObject:tid];
    } else {
        [self.selected_ids removeAllObjects];
        [self.selected_ids addObject:tid];
    }
    [self setNeedsDisplay:YES];

    NSRect  r        = [self item_rect:item midnight:mid];
    CGFloat ez       = MIN(shared_look_day_planner_resize_h, r.size.height * 0.4);
    NSRect  bot_edge = NSMakeRect(r.origin.x, NSMaxY(r) - ez, r.size.width, ez);
    NSRect  top_edge = NSMakeRect(r.origin.x, r.origin.y,     r.size.width, ez);
    if (NSPointInRect(pt, bot_edge)) {
        self.resizing             = YES;
        self.resize_top           = NO;
        self.resize_id            = item.task_id;
        self.resize_start_y       = pt.y;
        self.resize_orig_duration = item.duration;
    } else if (NSPointInRect(pt, top_edge)) {
        self.resizing               = YES;
        self.resize_top             = YES;
        self.resize_id              = item.task_id;
        self.resize_start_y         = pt.y;
        self.resize_orig_start_unix = item.start_unix;
        self.resize_orig_end_unix   = item.start_unix + (int64_t)item.duration * 60;
    } else {
        /* Block body: arm a pending move; promote to moving in mouseDragged: */
        self.move_pending         = YES;
        self.move_id              = item.task_id;
        self.move_orig_start_unix = item.start_unix;
        self.move_start_mouse_y   = pt.y;
    }
}

/*
 * mouseDragged: — update a block's duration (resize) or start time (move)
 * while the drag is live.
 *
 * Inputs:
 *   event — the mouse-dragged event
 */
- (void)
mouseDragged:(NSEvent *)event
{
    NSPoint pt = [self convertPoint:event.locationInWindow fromView:nil];

    if (self.resizing) {
        CGFloat dy    = pt.y - self.resize_start_y;
        int     delta = (int)round((dy / shared_look_day_planner_hour_h) * 60.0);
        delta = (delta / (int)snap_minutes) * (int)snap_minutes;

        SharedDayItem *item = [self item_named:self.resize_id];
        if (item == nil) return;
        int64_t mid    = [self midnight];
        NSRect  before = [self item_rect:item midnight:mid];

        if (self.resize_top) {
            /* Top edge: move start time, keep end time fixed */
            int64_t new_start = self.resize_orig_start_unix + (int64_t)delta * 60;
            int64_t new_end   = self.resize_orig_end_unix;
            int64_t lo        = mid + (int64_t)self.first_h * 3600;
            if (new_start < lo)
                new_start = lo;
            if (new_start > new_end - (int64_t)snap_minutes * 60)
                new_start = new_end - (int64_t)snap_minutes * 60;
            item.start_unix = new_start;
            item.duration   = (int)((new_end - new_start) / 60);
        } else {
            /* Bottom edge: keep start time fixed, move end time */
            int new_dur = self.resize_orig_duration + delta;
            if (new_dur < (int)snap_minutes) new_dur = (int)snap_minutes;
            if (new_dur > 8 * 60)           new_dur = 8 * 60;
            item.duration = new_dur;
        }
        [self redraw_block_from:before to:[self item_rect:item midnight:mid]];
        return;
    }

    /* Promote a pending move to an active one once the drag clears the threshold. */
    if (self.move_pending && fabs(pt.y - self.move_start_mouse_y) >= 5.0) {
        self.move_pending = NO;
        self.moving       = YES;
    }

    if (self.moving) {
        CGFloat dy        = pt.y - self.move_start_mouse_y;
        int     delta_min = (int)round((dy / shared_look_day_planner_hour_h) * 60.0);
        delta_min = (delta_min / (int)snap_minutes) * (int)snap_minutes;

        SharedDayItem *item = [self item_named:self.move_id];
        if (item == nil) return;
        int64_t mid       = [self midnight];
        NSRect  before    = [self item_rect:item midnight:mid];
        int64_t new_start = self.move_orig_start_unix + (int64_t)delta_min * 60;
        int64_t lo        = mid + (int64_t)self.first_h * 3600;
        int64_t hi        = mid + (int64_t)self.end_h   * 3600
                            - (int64_t)item.duration * 60;
        if (new_start < lo) new_start = lo;
        if (new_start > hi) new_start = hi;
        item.start_unix = new_start;
        [self redraw_block_from:before to:[self item_rect:item midnight:mid]];
        return;
    }
}

/*
 * mouseUp: — commit the new duration (resize) or start time (move): the
 * planner lays the day out again and the delegate writes it.
 *
 * Inputs:
 *   event — the mouse-up event (unused)
 */
- (void)
mouseUp:(NSEvent *)event
{
    if (self.resizing || self.moving) {
        BOOL           stretched = self.resizing;
        SharedDayItem *item      = [self item_named:stretched ? self.resize_id : self.move_id];
        self.resizing  = NO;
        self.moving    = NO;
        self.resize_id = 0;
        self.move_id   = 0;
        if (item != nil) [self.planner committed_block:item stretched:stretched];
        return;
    }

    /* Click that never became a drag — selection was handled in mouseDown. */
    self.move_pending = NO;
    self.move_id      = 0;
}

/*
 * resetCursorRects — while editable, the open hand on block bodies and
 * the resize cursor on their grips; events get their tooltips.
 */
- (void)
resetCursorRects
{
    int64_t mid      = [self midnight];
    BOOL    editable = [self.planner editable];
    [self addCursorRect:self.bounds cursor:NSCursor.arrowCursor];
    [self removeAllToolTips];
    for (SharedDayItem *item in self.planner.items) {
        NSRect  r    = [self item_rect:item midnight:mid];
        if (item.is_event) {
            [self addToolTipRect:r owner:self userData:NULL];
            continue;
        }
        if (!editable) continue;
        CGFloat ez   = MIN(shared_look_day_planner_resize_h, r.size.height * 0.4);
        NSRect  top  = NSMakeRect(r.origin.x, r.origin.y,           r.size.width, ez);
        NSRect  bot  = NSMakeRect(r.origin.x, NSMaxY(r) - ez,       r.size.width, ez);
        CGFloat bh   = r.size.height - 2.0 * ez;
        NSRect  body = NSMakeRect(r.origin.x, r.origin.y + ez,      r.size.width, MAX(bh, 0.0));
        [self addCursorRect:top  cursor:NSCursor.resizeUpDownCursor];
        [self addCursorRect:body cursor:NSCursor.openHandCursor];
        [self addCursorRect:bot  cursor:NSCursor.resizeUpDownCursor];
    }
}

/*
 * menuForEvent: — build the right-click context menu, while the planner
 * is editable and the delegate can unschedule.
 *
 * If the click landed on an unselected block, that block is selected (others
 * deselected) before the menu is shown.  Returns nil for clicks on empty space.
 *
 * Inputs:
 *   event — the right-click event
 *
 * Output:
 *   context menu, or nil.
 */
- (NSMenu *)
menuForEvent:(NSEvent *)event
{
    SharedDayPlanner *planner = self.planner;
    if (![planner editable] ||
        ![planner.delegate respondsToSelector:@selector(day_planner:unschedule_tasks:)])
        return nil;

    NSPoint        pt      = [self convertPoint:event.locationInWindow fromView:nil];
    SharedDayItem *clicked = [self item_at:pt events:NO midnight:[self midnight]];
    if (!clicked) return nil;

    NSNumber *cid = @(clicked.task_id);
    if (![self.selected_ids containsObject:cid]) {
        [self.selected_ids removeAllObjects];
        [self.selected_ids addObject:cid];
        [self setNeedsDisplay:YES];
    }

    NSUInteger n    = self.selected_ids.count;
    NSString  *lbl  = n > 1
        ? [NSString stringWithFormat:@"Remove %lu Items from Schedule", (unsigned long)n]
        : @"Remove from Schedule";

    NSMenu     *menu = [[NSMenu alloc] initWithTitle:@""];
    NSMenuItem *it   = [menu addItemWithTitle:lbl
                                       action:@selector(remove_selected_from_schedule:)
                                keyEquivalent:@""];
    it.target = planner;
    return menu;
}

@end

/* ── Layout ───────────────────────────────────────────────────────────── */

/*
 * layout_columns — place overlapping blocks side by side, the way a
 * calendar does: blocks are taken by start (the longer first on a tie),
 * each goes in the leftmost column free at its start, and every block of
 * a run of mutually overlapping ones shares that run's column count.
 *
 * Inputs:
 *   items — the day's blocks; their column and columns are set
 */
static void
layout_columns(NSArray<SharedDayItem *> *items)
{
    NSArray<SharedDayItem *> *sorted =
        [items sortedArrayUsingComparator:^NSComparisonResult(SharedDayItem *a, SharedDayItem *b) {
            if (a.start_unix != b.start_unix) return a.start_unix < b.start_unix ? NSOrderedAscending
                                                                                 : NSOrderedDescending;
            if (a.duration != b.duration) return a.duration > b.duration ? NSOrderedAscending
                                                                         : NSOrderedDescending;
            return NSOrderedSame;
        }];

    NSMutableArray<NSNumber *>      *col_end = [NSMutableArray array]; /* per column */
    NSMutableArray<SharedDayItem *> *run     = [NSMutableArray array];
    int64_t run_end = INT64_MIN;

    for (SharedDayItem *item in sorted) {
        int64_t end = item.start_unix + (int64_t)MAX(item.duration, 1) * 60;
        if (item.start_unix >= run_end && run.count > 0) {
            for (SharedDayItem *done in run) done.columns = col_end.count;
            [run removeAllObjects];
            [col_end removeAllObjects];
        }
        NSUInteger col = 0;
        while (col < col_end.count && col_end[col].longLongValue > item.start_unix) col++;
        if (col == col_end.count) [col_end addObject:@(end)];
        else                      col_end[col] = @(end);
        item.column = col;
        [run addObject:item];
        run_end = run.count == 1 ? end : MAX(run_end, end);
    }
    for (SharedDayItem *done in run) done.columns = col_end.count;
}

/*
 * calendar_color — a Google calendar's "#rrggbb" colour.
 *
 * Inputs:
 *   hex — the colour, or nil / "" when unknown
 *
 * Output:
 *   the colour; the system blue when it cannot be read.
 */
static NSColor *
calendar_color(NSString *hex)
{
    unsigned int rgb = 0;
    if (hex.length < 7 || [hex characterAtIndex:0] != '#' ||
        sscanf(hex.UTF8String + 1, "%6x", &rgb) != 1)
        return NSColor.systemBlueColor;
    return [NSColor colorWithSRGBRed:((rgb >> 16) & 0xff) / 255.0
                               green:((rgb >> 8) & 0xff) / 255.0
                                blue:(rgb & 0xff) / 255.0
                               alpha:1.0];
}

/* ── SharedDayPlanner ─────────────────────────────────────────────────── */

/*
 * canvas_height — the canvas height for the hours it shows, with the
 * padding above the first hour line and below the last.
 *
 * Inputs:
 *   canvas — the canvas, its first_h and end_h set
 *
 * Output:
 *   height in points.
 */
static CGFloat
canvas_height(SharedDayCanvas *canvas)
{
    return shared_look_day_planner_pad_v * 2.0 +
           (CGFloat)(canvas.end_h - canvas.first_h) * shared_look_day_planner_hour_h;
}

@implementation SharedDayPlanner

/*
 * init_with_delegate: — build the panel.
 * Inputs/output are documented in shared_day_planner.h.
 */
- (instancetype)
init_with_delegate:(id<SharedDayPlannerDelegate>)delegate
{
    self = [super initWithFrame:NSZeroRect];
    if (!self) return nil;

    _delegate    = delegate;
    _items       = [NSMutableArray array];
    _days_offset = 0;

    _canvas         = [[SharedDayCanvas alloc]
                           initWithFrame:NSMakeRect(0, 0, shared_look_day_planner_w, 0)];
    _canvas.first_h      = shared_look_day_planner_start_h;
    _canvas.end_h        = shared_look_day_planner_end_h;
    [_canvas setFrameSize:NSMakeSize(shared_look_day_planner_w, canvas_height(_canvas))];
    _canvas.planner      = self;
    _canvas.drop_y       = NAN;
    _canvas.selected_ids = [NSMutableSet set];

    _scroll                       = [[NSScrollView alloc] initWithFrame:NSZeroRect];
    _scroll.documentView          = _canvas;
    _scroll.hasVerticalScroller   = YES;
    _scroll.hasHorizontalScroller = NO;
    _scroll.autohidesScrollers    = YES;
    _scroll.drawsBackground       = NO;
    _scroll.translatesAutoresizingMaskIntoConstraints = NO;

    /* The clip view is the visible area: the panel minus any scroller that
     * takes space.  Its frame changes when the panel resizes and when the
     * scroller appears, so the canvas follows it rather than the panel. */
    _scroll.contentView.postsFrameChangedNotifications = YES;
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(sync_canvas_width:)
                                                 name:NSViewFrameDidChangeNotification
                                               object:_scroll.contentView];

    [self build_header];
    [self sync_clock_timer];
    return self;
}

/*
 * setDrop_types: — accept drops of these types on the hours.
 *
 * Inputs:
 *   drop_types — the pasteboard types; nil or empty for none
 */
- (void)
setDrop_types:(NSArray<NSPasteboardType> *)drop_types
{
    _drop_types = [drop_types copy];
    [self.canvas unregisterDraggedTypes];
    if (_drop_types.count > 0) [self.canvas registerForDraggedTypes:_drop_types];
}

/*
 * editable — whether task blocks can be selected, moved and stretched:
 * the delegate writes moves.
 *
 * Output:
 *   YES when it does.
 */
- (BOOL)
editable
{
    return [self.delegate respondsToSelector:@selector(day_planner:moved_task:start:duration:stretched:)];
}

/*
 * sync_canvas_width: — make the canvas exactly as wide as the scroll view's
 * visible area, so nothing is laid out under a scroller.  Floored at the
 * hour-label column plus the block insets so item rectangles keep a
 * non-negative width while the panel is collapsed.
 *
 * Inputs:
 *   note — NSViewFrameDidChangeNotification from the clip view (unused)
 */
- (void)
sync_canvas_width:(NSNotification *)note
{
    CGFloat least = shared_look_day_planner_label_w + shared_look_day_planner_block_inset * 2.0;
    CGFloat cw    = MAX(NSWidth(self.scroll.contentView.bounds), least);
    NSRect  cf    = self.canvas.frame;
    if (cf.size.width != cw) {
        cf.size.width = cw;
        self.canvas.frame = cf;
    }
}

/*
 * build_header — add the date navigation bar and the scroll view, wired with
 * Auto Layout.
 *
 * Layout:  [Today][cal]  ·  [date label]  ·  [‹][›]
 *           left-aligned     center            right-aligned
 *
 * Called once from init.
 */
- (void)
build_header
{
    NSView *header = [[NSView alloc] initWithFrame:NSZeroRect];
    header.translatesAutoresizingMaskIntoConstraints = NO;

    /* Left section ─ Today button + calendar icon button */
    NSButton *today       = [NSButton buttonWithTitle:@"Today"
                                               target:self
                                               action:@selector(go_today:)];
    today.controlSize     = NSControlSizeSmall;
    today.bezelStyle      = NSBezelStyleRounded;
    today.translatesAutoresizingMaskIntoConstraints = NO;
    _today_button = today;

    NSImage  *cal_img = [NSImage imageWithSystemSymbolName:@"calendar"
                                      accessibilityDescription:@"Pick a date"];
    NSButton *cal_btn = [NSButton buttonWithImage:cal_img
                                           target:self
                                           action:@selector(pick_displayed_date:)];
    cal_btn.bordered  = NO;
    cal_btn.toolTip   = @"Pick a date";
    cal_btn.translatesAutoresizingMaskIntoConstraints = NO;

    NSView *left = [[NSView alloc] initWithFrame:NSZeroRect];
    left.translatesAutoresizingMaskIntoConstraints = NO;
    [left addSubview:today];
    [left addSubview:cal_btn];
    [NSLayoutConstraint activateConstraints:@[
        [today.leadingAnchor  constraintEqualToAnchor:left.leadingAnchor],
        [today.centerYAnchor  constraintEqualToAnchor:left.centerYAnchor],
        [cal_btn.leadingAnchor constraintEqualToAnchor:today.trailingAnchor constant:2.0],
        [cal_btn.centerYAnchor constraintEqualToAnchor:left.centerYAnchor],
        [cal_btn.trailingAnchor constraintEqualToAnchor:left.trailingAnchor],
        [left.topAnchor       constraintEqualToAnchor:today.topAnchor],
        [left.bottomAnchor    constraintEqualToAnchor:today.bottomAnchor],
    ]];

    /* Center section ─ date label */
    NSTextField *label  = [NSTextField labelWithString:@""];
    label.font          = [NSFont systemFontOfSize:12.0 weight:NSFontWeightMedium];
    label.alignment     = NSTextAlignmentCenter;
    label.translatesAutoresizingMaskIntoConstraints = NO;
    _date_label = label;

    /* Right section ─ prev / next arrows */
    NSButton *prev     = [NSButton buttonWithTitle:@""
                                            target:self
                                            action:@selector(go_prev_day:)];
    prev.image         = [NSImage imageWithSystemSymbolName:@"chevron.left"
                                       accessibilityDescription:nil];
    prev.imagePosition = NSImageOnly;
    prev.controlSize   = NSControlSizeSmall;
    prev.bezelStyle    = NSBezelStyleRounded;
    prev.translatesAutoresizingMaskIntoConstraints = NO;

    NSButton *next     = [NSButton buttonWithTitle:@""
                                            target:self
                                            action:@selector(go_next_day:)];
    next.image         = [NSImage imageWithSystemSymbolName:@"chevron.right"
                                       accessibilityDescription:nil];
    next.imagePosition = NSImageOnly;
    next.controlSize   = NSControlSizeSmall;
    next.bezelStyle    = NSBezelStyleRounded;
    next.translatesAutoresizingMaskIntoConstraints = NO;

    NSView *right = [[NSView alloc] initWithFrame:NSZeroRect];
    right.translatesAutoresizingMaskIntoConstraints = NO;
    [right addSubview:prev];
    [right addSubview:next];
    [NSLayoutConstraint activateConstraints:@[
        [prev.leadingAnchor  constraintEqualToAnchor:right.leadingAnchor],
        [prev.centerYAnchor  constraintEqualToAnchor:right.centerYAnchor],
        [next.leadingAnchor  constraintEqualToAnchor:prev.trailingAnchor constant:0.0],
        [next.centerYAnchor  constraintEqualToAnchor:right.centerYAnchor],
        [next.trailingAnchor constraintEqualToAnchor:right.trailingAnchor],
        [right.topAnchor     constraintEqualToAnchor:prev.topAnchor],
        [right.bottomAnchor  constraintEqualToAnchor:prev.bottomAnchor],
    ]];

    [header addSubview:left];
    [header addSubview:label];
    [header addSubview:right];

    /* Left flush, right flush, label centered — give the center label a
     * lower-priority centering constraint so it yields gracefully when space
     * is tight rather than forcing the side sections to overlap. */
    NSLayoutConstraint *cx = [label.centerXAnchor constraintEqualToAnchor:header.centerXAnchor];
    cx.priority = NSLayoutPriorityDefaultHigh;

    [NSLayoutConstraint activateConstraints:@[
        [left.leadingAnchor   constraintEqualToAnchor:header.leadingAnchor  constant:6.0],
        [left.centerYAnchor   constraintEqualToAnchor:header.centerYAnchor],

        [label.centerYAnchor  constraintEqualToAnchor:header.centerYAnchor],
        [label.leadingAnchor  constraintGreaterThanOrEqualToAnchor:left.trailingAnchor  constant:4.0],
        [label.trailingAnchor constraintLessThanOrEqualToAnchor:right.leadingAnchor constant:-4.0],
        cx,

        [right.trailingAnchor constraintEqualToAnchor:header.trailingAnchor constant:-6.0],
        [right.centerYAnchor  constraintEqualToAnchor:header.centerYAnchor],
    ]];

    /* 1 pt separator below the header */
    NSView *sep = [[NSView alloc] initWithFrame:NSZeroRect];
    sep.wantsLayer = YES;
    sep.layer.backgroundColor = NSColor.separatorColor.CGColor;
    sep.translatesAutoresizingMaskIntoConstraints = NO;

    /* The all-day strip: the day's all-day calendar events, one line,
     * collapsed to nothing on a day without any. */
    NSTextField *all_day = [NSTextField labelWithString:@""];
    all_day.font          = [NSFont systemFontOfSize:NSFont.smallSystemFontSize];
    all_day.textColor     = NSColor.secondaryLabelColor;
    all_day.lineBreakMode = NSLineBreakByTruncatingTail;
    all_day.hidden        = YES;
    all_day.translatesAutoresizingMaskIntoConstraints = NO;
    [all_day setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow
                                      forOrientation:NSLayoutConstraintOrientationHorizontal];
    _all_day_label  = all_day;
    _all_day_height = [all_day.heightAnchor constraintEqualToConstant:0.0];

    [self addSubview:header];
    [self addSubview:all_day];
    [self addSubview:sep];
    [self addSubview:_scroll];

    [NSLayoutConstraint activateConstraints:@[
        [header.topAnchor      constraintEqualToAnchor:self.topAnchor],
        [header.leadingAnchor  constraintEqualToAnchor:self.leadingAnchor],
        [header.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        [header.heightAnchor   constraintEqualToConstant:header_h],

        [all_day.topAnchor      constraintEqualToAnchor:header.bottomAnchor],
        [all_day.leadingAnchor  constraintEqualToAnchor:self.leadingAnchor constant:8.0],
        [all_day.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-8.0],
        _all_day_height,

        [sep.topAnchor         constraintEqualToAnchor:all_day.bottomAnchor],
        [sep.leadingAnchor     constraintEqualToAnchor:self.leadingAnchor],
        [sep.trailingAnchor    constraintEqualToAnchor:self.trailingAnchor],
        [sep.heightAnchor      constraintEqualToConstant:1.0],

        [_scroll.topAnchor     constraintEqualToAnchor:sep.bottomAnchor],
        [_scroll.bottomAnchor  constraintEqualToAnchor:self.bottomAnchor],
        [_scroll.leadingAnchor  constraintEqualToAnchor:self.leadingAnchor],
        [_scroll.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
    ]];

    [self update_header_controls];
}

/*
 * update_header_controls — sync the date label text and Today button enabled
 * state to the current days_offset, and the clock timer with it: the
 * current-time line is drawn on today only.
 */
- (void)
update_header_controls
{
    time_t    t     = (time_t)midnight_for_offset(_days_offset);
    struct tm local = *localtime(&t);
    char      buf[64];
    strftime(buf, sizeof(buf), "%a, %b %-d", &local);
    _date_label.stringValue = @(buf);
    _today_button.enabled   = (_days_offset != 0);
    [self sync_clock_timer];
}

/*
 * sync_clock_timer — run the timer that moves the current-time line only
 * while the line is on screen: the panel shown, today displayed.  A hidden
 * panel's timer dirtied a canvas nobody saw every 30 seconds.  The
 * tolerance lets the system fire it alongside other work.
 */
- (void)
sync_clock_timer
{
    BOOL wanted = !self.hidden && _days_offset == 0 && !self.is_shut_down;

    if (!wanted) {
        [self.clock_timer invalidate];
        self.clock_timer = nil;
        return;
    }
    if (self.clock_timer != nil) return;

    __weak SharedDayPlanner *ws = self;
    self.clock_timer = [NSTimer scheduledTimerWithTimeInterval:30.0
                                                       repeats:YES
                                                         block:^(NSTimer *t) {
        [ws.canvas redraw_now_line];
    }];
    self.clock_timer.tolerance = 5.0;
}

/*
 * setHidden: — the window shows or hides the panel: the clock runs only
 * while it shows.
 *
 * Inputs:
 *   hidden — whether the panel is hidden
 */
- (void)
setHidden:(BOOL)hidden
{
    [super setHidden:hidden];
    [self sync_clock_timer];
}

/*
 * show_day: — show the day `offset` days from today, from an hour before
 * now (today) or 8 AM.
 *
 * Inputs:
 *   offset — days relative to today
 */
- (void)
show_day:(NSInteger)offset
{
    _days_offset = offset;
    [self update_header_controls];
    [self reload];
    [self scroll_to_now];
}

/*
 * pick_displayed_date: — a calendar in a tool panel to jump to any date.
 *
 * Inputs:
 *   sender — the calendar button (unused)
 */
- (void)
pick_displayed_date:(id)sender
{
    time_t        t      = (time_t)midnight_for_offset(_days_offset);
    NSDatePicker *picker = [[NSDatePicker alloc] initWithFrame:NSZeroRect];
    picker.datePickerStyle    = NSDatePickerStyleClockAndCalendar;
    picker.datePickerElements = NSDatePickerElementFlagYearMonthDay;
    picker.dateValue          = [NSDate dateWithTimeIntervalSince1970:(NSTimeInterval)t];
    NSSize size = picker.fittingSize;
    picker.translatesAutoresizingMaskIntoConstraints = NO;
    [picker.widthAnchor  constraintEqualToConstant:size.width].active  = YES;
    [picker.heightAnchor constraintEqualToConstant:size.height].active = YES;

    __weak SharedDayPlanner *ws = self;
    SharedToolPanel *panel = [SharedToolPanel
        panel_with_title:@"Go to Date" headline:@"Go to Date" subtitle:@"" symbol:@"calendar"
                 content:picker buttons:@[@"Go", @"Cancel"] destructive:-1
                 handler:^NSString *(NSInteger index) {
        SharedDayPlanner *s = ws;
        if (!s || index != 0) return nil;
        NSCalendar       *cal    = NSCalendar.currentCalendar;
        NSDate           *today  = [cal startOfDayForDate:[NSDate date]];
        NSDate           *chosen = [cal startOfDayForDate:picker.dateValue];
        NSDateComponents *diff   = [cal components:NSCalendarUnitDay
                                          fromDate:today toDate:chosen options:0];
        [s show_day:(NSInteger)diff.day];
        return nil;
    }];
    [panel show_over:self.window];
}

/*
 * go_prev_day: — navigate one day back.
 *
 * Inputs:
 *   sender — the previous-day button (unused)
 */
- (void)
go_prev_day:(id)sender
{
    [self show_day:_days_offset - 1];
}

/*
 * go_next_day: — navigate one day forward.
 *
 * Inputs:
 *   sender — the next-day button (unused)
 */
- (void)
go_next_day:(id)sender
{
    [self show_day:_days_offset + 1];
}

/*
 * go_today: — jump back to today.
 *
 * Inputs:
 *   sender — the Today button (unused)
 */
- (void)
go_today:(id)sender
{
    [self show_day:0];
}

/*
 * reload — ask the delegate for the displayed day and redraw.
 * Documented in shared_day_planner.h.  Timed events are clipped to the
 * day; all-day ones go to the strip under the header.
 */
- (void)
reload
{
    if (self.is_shut_down) return;

    int64_t lo, hi;
    day_bounds(_days_offset, &lo, &hi);
    NSArray<SharedDayItem *> *day = [self.delegate day_planner:self items_from:lo to:hi];

    /* The old items are the tooltip rectangles' subject: drop those first. */
    [self.canvas removeAllToolTips];
    [self.items removeAllObjects];
    NSMutableArray<NSString *> *all_day = [NSMutableArray array];
    NSMutableSet<NSNumber *>   *present = [NSMutableSet set];
    for (SharedDayItem *item in day) {
        if (!item.is_event) {
            [self.items addObject:item];
            [present addObject:@(item.task_id)];
            continue;
        }
        if (item.title.length == 0) item.title = @"Busy";
        if (item.all_day) {
            [all_day addObject:item.title];
            continue;
        }
        int64_t start = MAX(item.start_unix, lo);
        int64_t end   = MIN(item.start_unix + (int64_t)item.duration * 60, hi);
        NSColor *base = calendar_color(item.color);
        item.start_unix = start;
        item.duration   = (int)MAX((end - start) / 60, 1);
        item.event_fill = shared_ui_color_dimmed(base, 22);
        item.event_bar  = base;
        [self.items addObject:item];
    }

    NSString *text = [all_day componentsJoinedByString:@" · "];
    self.all_day_label.stringValue = text;
    self.all_day_label.toolTip     = all_day.count > 0 ? text : nil;
    self.all_day_label.hidden      = all_day.count == 0;
    self.all_day_height.constant   = all_day.count > 0 ? all_day_h : 0.0;

    [self fit_hours_from:lo];
    layout_columns(self.items);

    /* A reload (a sync finishing, an edit elsewhere) keeps the selection
     * of every block still on the day. */
    [self.canvas.selected_ids intersectSet:present];

    [self.canvas setNeedsDisplay:YES];
    [self.canvas.window invalidateCursorRectsForView:self.canvas];
}

/*
 * fit_hours_from: — show business hours, widened to whole hours that take
 * in every block of the day, and size the canvas to them.  A wider top
 * shifts everything down, so the scroll position follows to keep the same
 * times in view.
 *
 * Inputs:
 *   lo — the day's local midnight
 */
- (void)
fit_hours_from:(int64_t)lo
{
    NSInteger first = shared_look_day_planner_start_h;
    NSInteger end   = shared_look_day_planner_end_h;
    for (SharedDayItem *item in self.items) {
        int64_t from = item.start_unix - lo;
        int64_t to   = from + (int64_t)item.duration * 60;
        first = MIN(first, (NSInteger)MAX(from, 0) / 3600);
        end   = MAX(end, (NSInteger)((MIN(to, 24 * 3600) + 3599) / 3600));
    }

    NSInteger shift = self.canvas.first_h - first;
    if (shift == 0 && end == self.canvas.end_h) return;

    self.canvas.first_h = first;
    self.canvas.end_h   = end;
    NSPoint origin = self.scroll.contentView.bounds.origin;
    [self.canvas setFrameSize:NSMakeSize(NSWidth(self.canvas.frame), canvas_height(self.canvas))];
    origin.y = MAX(0.0, origin.y + shift * shared_look_day_planner_hour_h);
    [self.canvas scrollPoint:origin];
}

/*
 * committed_block:stretched: — a move or a stretch ended: lay the blocks
 * out again (the block may now overlap others, or no longer), then let the
 * delegate write the new session.
 *
 * Inputs:
 *   item      — the task's block, at its new place
 *   stretched — YES for a stretch, NO for a move
 */
- (void)
committed_block:(SharedDayItem *)item stretched:(BOOL)stretched
{
    layout_columns(self.items);
    [self.canvas setNeedsDisplay:YES];
    [self.canvas.window invalidateCursorRectsForView:self.canvas];
    [self.delegate day_planner:self moved_task:item.task_id start:item.start_unix
                      duration:item.duration stretched:stretched];
}

/*
 * scroll_to_now — scroll so the current time (today) or 8 AM (other days) is
 * visible with one hour of lead.
 * Documented in shared_day_planner.h.
 */
- (void)
scroll_to_now
{
    CGFloat scroll_y;
    if (_days_offset == 0) {
        CGFloat now_y = [self.canvas y_for_unix:(int64_t)time(NULL)];
        scroll_y = MAX(0.0, now_y - shared_look_day_planner_hour_h);
    } else {
        int64_t eight_am = midnight_for_offset(_days_offset) + 8 * 3600;
        scroll_y = MAX(0.0, [self.canvas y_for_unix:eight_am] - shared_look_day_planner_hour_h);
    }
    [self.canvas scrollPoint:NSMakePoint(0.0, scroll_y)];
}

/*
 * remove_selected_from_schedule: — hand the selected blocks to the
 * delegate to unschedule, and forget the selection.
 *
 * Inputs:
 *   sender — unused (called from the context menu)
 */
- (void)
remove_selected_from_schedule:(id)sender
{
    NSSet<NSNumber *> *ids = [self.canvas.selected_ids copy];
    [self.canvas.selected_ids removeAllObjects];
    [self.delegate day_planner:self unschedule_tasks:ids];
}

/*
 * shut_down — stop the clock timer and stop watching the scroll view.
 * Idempotent.
 * Documented in shared_day_planner.h.
 */
- (void)
shut_down
{
    if (self.is_shut_down) return;
    self.is_shut_down = YES;
    [[NSNotificationCenter defaultCenter] removeObserver:self
                                                    name:NSViewFrameDidChangeNotification
                                                  object:self.scroll.contentView];
    [self sync_clock_timer];        /* shut down: stops it */
}

@end
