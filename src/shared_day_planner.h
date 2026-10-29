/*
 * shared_day_planner — THE day planner of both apps: a right-side panel
 * showing the hours of one day, with the day's scheduled tasks as blocks
 * and its Google Calendar events (Tasks' sync caches them in the shared
 * database) as flat calendar-coloured blocks to plan around; all-day
 * events in a strip under the header.  A header steps through the days
 * (Today, a date picker, previous and next); a red line tracks the
 * current time on today.  Overlapping blocks sit side by side, as in a
 * calendar.
 *
 * What the planner shows and what a gesture does are the app's: its
 * DELEGATE loads the day, and the planner offers only the gestures the
 * delegate implements —
 *
 *   - moving and stretching a task's block, selecting blocks and the
 *     "Remove from Schedule" menu: when it implements
 *     day_planner:moved_task:start:duration:stretched: (Tasks); otherwise
 *     the task blocks are drawn and nothing more (Notes);
 *   - dropping onto the hours: when drop_types is set and it implements
 *     day_planner:drop:start:;
 *   - a double-click on a task or on an event: when it implements
 *     day_planner:open_task: or day_planner:open_event:.
 *
 * The planner draws from its own copy of the day (SharedDayItem); a
 * gesture changes that copy at once and the delegate writes the database.
 * After writing outside a gesture (a drop, an unschedule, an edit
 * elsewhere) the app calls reload.
 *
 * Main thread only.
 */

#import <Cocoa/Cocoa.h>

@class SharedDayPlanner;

/*
 * SharedDayItem — one block of the day, as the delegate hands it over: a
 * scheduled TASK (task_id set, event_id nil) or a calendar EVENT (event_id
 * set).  An event's times may run past the day; the planner clips them.
 */
@interface SharedDayItem : NSObject
@property (nonatomic) int64_t task_id;              /* a task's id; 0 for an event       */
@property (nonatomic, copy) NSString *calendar_id;  /* an event's calendar; nil for a task */
@property (nonatomic, copy) NSString *event_id;     /* an event's id; nil for a task     */
@property (nonatomic, copy) NSString *title;        /* an event's may be empty: "Busy"   */
@property (nonatomic) int64_t start_unix;           /* unix seconds                      */
@property (nonatomic) int duration;                 /* minutes                           */
@property (nonatomic) BOOL done;                    /* a task that is Done: drawn grey   */
@property (nonatomic) BOOL all_day;                 /* an all-day event: in the strip    */
@property (nonatomic, copy) NSString *color;        /* an event's calendar's "#rrggbb";
                                                     * nil or "" draws the system blue */
@property (nonatomic, readonly) BOOL is_event;      /* event_id != nil                   */
@end

/*
 * SharedDayPlannerDelegate — the app's side of the planner (above).
 */
@protocol SharedDayPlannerDelegate <NSObject>

/*
 * day_planner:items_from:to: — the day's tasks and events.
 *
 * Inputs:
 *   planner — the planner
 *   lo      — unix seconds of the day's local midnight
 *   hi      — unix seconds of the next local midnight (a day across a
 *             clock change is 23 or 25 hours)
 *
 * Output:
 *   the tasks scheduled in [lo, hi) and the events overlapping it, in
 *   any order; never nil.
 */
- (NSArray<SharedDayItem *> *)day_planner:(SharedDayPlanner *)planner
                               items_from:(int64_t)lo
                                       to:(int64_t)hi;

@optional

/*
 * day_planner:moved_task:start:duration:stretched: — a task's block was
 * moved or stretched (the planner has already redrawn it): write the new
 * session.  Implementing this makes task blocks movable.
 *
 * Inputs:
 *   planner   — the planner
 *   task_id   — the task
 *   start     — its new start, unix seconds
 *   duration  — its new length, minutes
 *   stretched — YES for a stretch from either edge, NO for a move
 */
- (void)day_planner:(SharedDayPlanner *)planner
         moved_task:(int64_t)task_id
              start:(int64_t)start
           duration:(int)duration
          stretched:(BOOL)stretched;

/*
 * day_planner:unschedule_tasks: — "Remove from Schedule" on the selected
 * blocks: clear their sessions, then reload the planner.
 *
 * Inputs:
 *   planner  — the planner
 *   task_ids — NSNumber task ids
 */
- (void)day_planner:(SharedDayPlanner *)planner unschedule_tasks:(NSSet<NSNumber *> *)task_ids;

/*
 * day_planner:drop:start: — something of drop_types was dropped on the
 * hours: schedule it, then reload the planner.
 *
 * Inputs:
 *   planner — the planner
 *   info    — the dragging session
 *   start   — the time under the drop, snapped to a quarter hour
 *
 * Output:
 *   YES when the drop was taken.
 */
- (BOOL)day_planner:(SharedDayPlanner *)planner drop:(id<NSDraggingInfo>)info start:(int64_t)start;

/*
 * day_planner:open_task: — a task's block was double-clicked.
 *
 * Inputs:
 *   planner — the planner
 *   task_id — the task
 */
- (void)day_planner:(SharedDayPlanner *)planner open_task:(int64_t)task_id;

/*
 * day_planner:open_event: — a timed event's block was double-clicked.
 *
 * Inputs:
 *   planner — the planner
 *   event   — the event, as the delegate gave it (its times clipped to
 *             the day)
 */
- (void)day_planner:(SharedDayPlanner *)planner open_event:(SharedDayItem *)event;

@end

/*
 * SharedDayPlanner — the panel (above).  The app's split view owns it; the
 * app keeps its delegate alive (the planner holds it weakly).
 */
@interface SharedDayPlanner : NSView

/*
 * init_with_delegate: — build the panel, on today, empty until reload.
 *
 * Inputs:
 *   delegate — the app's side; held weakly
 *
 * Output:
 *   the view.
 */
- (instancetype)init_with_delegate:(id<SharedDayPlannerDelegate>)delegate NS_DESIGNATED_INITIALIZER;
- (instancetype)initWithFrame:(NSRect)frame NS_UNAVAILABLE;
- (instancetype)initWithCoder:(NSCoder *)coder NS_UNAVAILABLE;

/* The pasteboard types the hours accept as a drop (day_planner:drop:start:);
 * nil or empty: none. */
@property (nonatomic, copy) NSArray<NSPasteboardType> *drop_types;

/* A line added to an event's tooltip, saying what a double-click does; nil
 * for none. */
@property (nonatomic, copy) NSString *event_hint;

/*
 * reload — ask the delegate for the shown day again and redraw, keeping
 * the selection of every block still there.  Call it after any change to
 * what the planner shows, and when it is shown.
 */
- (void)reload;

/*
 * scroll_to_now — scroll so the current time (today) or 8 AM (another
 * day) is in view, with an hour above it.
 */
- (void)scroll_to_now;

/*
 * shut_down — stop the clock timer and stop watching the scroll view.
 * Call before the window goes.  Idempotent.
 */
- (void)shut_down;

@end
