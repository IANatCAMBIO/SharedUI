#import "shared_calendar.h"
#import "shared_ui.h"

/* The Privacy & Security pane's Calendars list, in System Settings. */
static NSString *const privacy_url =
    @"x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars";

/* The one event store; nil until made with access. */
static EKEventStore *store;

/*
 * shared_calendar_access — see shared_calendar.h.
 */
SharedCalendarAccess
shared_calendar_access(void)
{
    switch ([EKEventStore authorizationStatusForEntityType:EKEntityTypeEvent]) {
    case EKAuthorizationStatusNotDetermined: return SharedCalendarAccessUnasked;
    case EKAuthorizationStatusFullAccess:    return SharedCalendarAccessGranted;
    default:                                 return SharedCalendarAccessDenied;
    }
}

/*
 * shared_calendar_store — see shared_calendar.h.
 */
EKEventStore *
shared_calendar_store(void)
{
    if (shared_calendar_access() != SharedCalendarAccessGranted) return nil;
    if (store == nil) store = [[EKEventStore alloc] init];
    return store;
}

/*
 * shared_calendar_request_access — see shared_calendar.h.  A store made
 * before access was granted sees no calendars, so it is let go: the next
 * shared_calendar_store makes a fresh one.
 */
void
shared_calendar_request_access(void (^done)(BOOL granted))
{
    EKEventStore *asker = [[EKEventStore alloc] init];
    [asker requestFullAccessToEventsWithCompletion:^(BOOL granted, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            (void)asker;                 /* kept until the answer comes */
            store = nil;
            done(granted);
        });
    }];
}

/*
 * shared_calendar_on — see shared_calendar.h.
 */
BOOL
shared_calendar_on(id<SharedCalendarSettings> settings)
{
    return [[settings calendar_setting:SHARED_CALENDAR_ENABLED] isEqualToString:@"1"] &&
           shared_calendar_access() == SharedCalendarAccessGranted;
}

/*
 * calendars — every event calendar, by account, then by name.
 *
 * Output: the calendars; empty without access.
 */
static NSArray<EKCalendar *> *
calendars(void)
{
    NSArray<EKCalendar *> *all = [shared_calendar_store() calendarsForEntityType:EKEntityTypeEvent];
    return [all ?: @[] sortedArrayUsingComparator:^NSComparisonResult(EKCalendar *a, EKCalendar *b) {
        NSComparisonResult by_source = [a.source.title localizedStandardCompare:b.source.title];
        return by_source != NSOrderedSame ? by_source : [a.title localizedStandardCompare:b.title];
    }];
}

/*
 * shown_ids — the SHARED_CALENDAR_SHOWN setting.
 *
 * Inputs:
 *   settings — the app's settings
 *
 * Output: the identifiers, or nil when unset (every calendar shows).
 */
static NSSet<NSString *> *
shown_ids(id<SharedCalendarSettings> settings)
{
    NSString *text = [settings calendar_setting:SHARED_CALENDAR_SHOWN];
    return text != nil ? [NSSet setWithArray:[text componentsSeparatedByString:@"\n"]] : nil;
}

/*
 * shared_calendar_for_tasks — see shared_calendar.h.
 */
EKCalendar *
shared_calendar_for_tasks(id<SharedCalendarSettings> settings)
{
    EKEventStore *s = shared_calendar_store();
    if (s == nil) return nil;
    NSString   *id  = [settings calendar_setting:SHARED_CALENDAR_TASKS];
    EKCalendar *cal = id != nil ? [s calendarWithIdentifier:id] : nil;
    if (cal != nil && cal.allowsContentModifications) return cal;
    cal = s.defaultCalendarForNewEvents;
    return cal.allowsContentModifications ? cal : nil;
}

/*
 * declined — whether the account's own attendee declined the event.
 *
 * Inputs:
 *   event — the event
 *
 * Output: YES when it did.
 */
static BOOL
declined(EKEvent *event)
{
    for (EKParticipant *p in event.attendees) {
        if (p.isCurrentUser && p.participantStatus == EKParticipantStatusDeclined) return YES;
    }
    return NO;
}

/*
 * attendee_names — an event's attendees as a note lists them: each by
 * name, by email address when it has none; rooms and other resources are
 * not attendees.
 *
 * Inputs:
 *   event — the event
 *
 * Output: the names, in the calendar's order.
 */
static NSArray<NSString *> *
attendee_names(EKEvent *event)
{
    NSMutableArray<NSString *> *names = [NSMutableArray array];
    for (EKParticipant *p in event.attendees) {
        if (p.participantType == EKParticipantTypeRoom ||
            p.participantType == EKParticipantTypeResource) continue;
        NSString *name = p.name;
        if (name.length == 0 && [p.URL.scheme isEqualToString:@"mailto"])
            name = p.URL.resourceSpecifier;
        if (name.length > 0) [names addObject:name];
    }
    return names;
}

/*
 * shared_calendar_day_events — see shared_calendar.h.
 */
NSArray<SharedDayItem *> *
shared_calendar_day_events(id<SharedCalendarSettings> settings, int64_t lo, int64_t hi,
                           NSSet<NSString *> *skip)
{
    NSMutableArray<SharedDayItem *> *items = [NSMutableArray array];
    if (!shared_calendar_on(settings)) return items;

    NSSet<NSString *>             *shown = shown_ids(settings);
    NSMutableArray<EKCalendar *>  *cals  = [NSMutableArray array];
    for (EKCalendar *c in calendars()) {
        if (shown == nil || [shown containsObject:c.calendarIdentifier]) [cals addObject:c];
    }
    if (cals.count == 0) return items;

    NSPredicate *range = [shared_calendar_store()
        predicateForEventsWithStartDate:[NSDate dateWithTimeIntervalSince1970:(NSTimeInterval)lo]
                                endDate:[NSDate dateWithTimeIntervalSince1970:(NSTimeInterval)hi]
                              calendars:cals];
    for (EKEvent *ev in [shared_calendar_store() eventsMatchingPredicate:range]) {
        if (ev.eventIdentifier == nil || ev.status == EKEventStatusCanceled || declined(ev) ||
            [skip containsObject:ev.eventIdentifier]) continue;
        int64_t start = (int64_t)ev.startDate.timeIntervalSince1970;
        int64_t end   = (int64_t)ev.endDate.timeIntervalSince1970;

        SharedDayItem *item = [[SharedDayItem alloc] init];
        item.calendar_id = ev.calendar.calendarIdentifier;
        item.event_id    = ev.eventIdentifier;
        item.occurrence  = (int64_t)(ev.occurrenceDate ?: ev.startDate).timeIntervalSince1970;
        item.title       = ev.title ?: @"";
        item.start_unix  = start;
        item.duration    = (int)((end - start) / 60);
        item.all_day     = ev.allDay;
        item.color       = ev.calendar.color;
        item.attendees   = attendee_names(ev);
        [items addObject:item];
    }
    return items;
}

/*
 * shared_calendar_observe — see shared_calendar.h.  Any store's change is
 * the calendar's: the notification is not tied to the one store.
 */
id
shared_calendar_observe(void (^changed)(void))
{
    return [NSNotificationCenter.defaultCenter
        addObserverForName:EKEventStoreChangedNotification object:nil
                     queue:NSOperationQueue.mainQueue
                usingBlock:^(NSNotification *note) { changed(); }];
}

/*
 * shared_calendar_unobserve — see shared_calendar.h.
 */
void
shared_calendar_unobserve(id token)
{
    if (token != nil) [NSNotificationCenter.defaultCenter removeObserver:token];
}

/* ── The Settings section ─────────────────────────────────────────────── */

@interface SharedCalendarSection ()
@property (nonatomic, strong) id<SharedCalendarSettings> settings;
@property (nonatomic, assign) BOOL tasks;
@property (nonatomic, assign) CGFloat width;
@property (nonatomic, copy)   void (^changed)(void);
@property (nonatomic, strong) id observer;           /* the calendar's changes */
@property (nonatomic, strong) NSStackView *view;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSButton *> *boxes; /* calendar id →
                                                                                    * its checkbox */
@end

@implementation SharedCalendarSection

/*
 * init_with_settings:tasks:width:changed: — build the section.
 * Inputs/output are documented in shared_calendar.h.
 */
- (instancetype)
init_with_settings:(id<SharedCalendarSettings>)settings tasks:(BOOL)tasks width:(CGFloat)width
           changed:(void (^)(void))changed
{
    self = [super init];
    if (!self) return nil;
    _settings = settings;
    _tasks    = tasks;
    _width    = width;
    _changed  = [changed copy];
    _view     = [NSStackView stackViewWithViews:@[]];
    _view.orientation = NSUserInterfaceLayoutOrientationVertical;
    _view.alignment   = NSLayoutAttributeLeading;
    _view.spacing     = shared_look_settings_row_gap;
    _boxes            = [NSMutableDictionary dictionary];
    __weak SharedCalendarSection *ws = self;
    _observer = shared_calendar_observe(^{
        SharedCalendarSection *s = ws;
        if (s == nil) return;
        [s rebuild];
        s.changed();
    });
    [self rebuild];
    return self;
}

/*
 * shut_down — see shared_calendar.h.
 */
- (void)
shut_down
{
    shared_calendar_unobserve(self.observer);
    self.observer = nil;
}

/*
 * rebuild — the section's rows from the settings and the calendars.
 */
- (void)
rebuild
{
    NSMutableArray<NSView *> *rows = [NSMutableArray array];
    NSString *app = shared_ui_app_name();
    [self.boxes removeAllObjects];
    [rows addObject:shared_ui_note([NSString stringWithFormat:
        @"%@ uses the calendars of the macOS Calendar app, which keeps them in sync with "
        @"your Google, iCloud or Exchange accounts (add them in Calendar → Settings → "
        @"Accounts). Notes and Tasks share these settings.", app], self.width)];

    BOOL      on    = [[self.settings calendar_setting:SHARED_CALENDAR_ENABLED] isEqualToString:@"1"];
    NSString *title = self.tasks ? @"Sync the day planner with Calendar"
                                 : @"Show Calendar events in the day planner";
    NSButton *box   = [NSButton checkboxWithTitle:title target:self action:@selector(toggled:)];
    box.state       = on ? NSControlStateValueOn : NSControlStateValueOff;
    if (self.tasks)
        box.toolTip = @"Tasks scheduled on the day planner become events in your calendar, and "
                      @"moving, stretching or removing them changes the event. Events moved or "
                      @"deleted in Calendar change the planner too.";
    [rows addObject:box];

    if (on && shared_calendar_access() == SharedCalendarAccessDenied) {
        [rows addObject:shared_ui_note([NSString stringWithFormat:
            @"%@ is not allowed to read your calendars. Allow it in System Settings → Privacy "
            @"& Security → Calendars.", app], self.width)];
        [rows addObject:[NSButton buttonWithTitle:@"Open Privacy Settings…" target:self
                                           action:@selector(open_privacy:)]];
    } else if (on && shared_calendar_access() == SharedCalendarAccessGranted) {
        if (self.tasks) [rows addObject:[self tasks_row]];
        [rows addObjectsFromArray:[self shown_rows]];
    }
    [self.view setViews:rows inGravity:NSStackViewGravityTop];
    shared_ui_use_ui_font(self.view);
}

/*
 * tasks_row — "Add scheduled tasks to: [calendar]", the writable
 * calendars under their accounts' names.
 *
 * Output: the row.
 */
- (NSView *)
tasks_row
{
    NSPopUpButton *popup  = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    EKCalendar    *chosen = shared_calendar_for_tasks(self.settings);
    NSString      *source = nil;
    popup.autoenablesItems = NO;
    for (EKCalendar *c in calendars()) {
        if (!c.allowsContentModifications) continue;
        if (![c.source.title isEqualToString:source]) {
            source = c.source.title;
            [popup.menu addItem:[NSMenuItem sectionHeaderWithTitle:source]];
        }
        NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:c.title action:nil keyEquivalent:@""];
        item.representedObject = c.calendarIdentifier;
        item.indentationLevel  = 1;
        [popup.menu addItem:item];
        if ([c.calendarIdentifier isEqualToString:chosen.calendarIdentifier]) [popup selectItem:item];
    }
    popup.target = self;
    popup.action = @selector(tasks_calendar_chosen:);
    NSStackView *row = [NSStackView stackViewWithViews:@[
        [NSTextField labelWithString:@"Add scheduled tasks to:"], popup]];
    row.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    row.alignment   = NSLayoutAttributeFirstBaseline;
    return row;
}

/*
 * shown_rows — "Show events from:", then each account's name and a
 * checkbox per calendar of it.
 *
 * Output: the rows.
 */
- (NSArray<NSView *> *)
shown_rows
{
    NSMutableArray<NSView *> *rows  = [NSMutableArray arrayWithObject:
                                          [NSTextField labelWithString:@"Show events from:"]];
    NSSet<NSString *>        *shown  = shown_ids(self.settings);
    NSString                 *source = nil;
    for (EKCalendar *c in calendars()) {
        if (![c.source.title isEqualToString:source]) {
            source = c.source.title;
            NSTextField *head = [NSTextField labelWithString:source];
            head.textColor = NSColor.secondaryLabelColor;
            [rows addObject:[self indented:head by:shared_look_settings_indent]];
        }
        NSButton *box = [NSButton checkboxWithTitle:c.title target:self action:@selector(shown_toggled:)];
        self.boxes[c.calendarIdentifier] = box;
        box.state      = shown == nil || [shown containsObject:c.calendarIdentifier]
                       ? NSControlStateValueOn : NSControlStateValueOff;
        [rows addObject:[self indented:box by:2 * shared_look_settings_indent]];
    }
    return rows;
}

/*
 * indented:by: — a view moved right in the section.
 *
 * Inputs:
 *   view  — the view
 *   inset — how far
 *
 * Output: a stack holding it.
 */
- (NSView *)
indented:(NSView *)view by:(CGFloat)inset
{
    NSStackView *stack = [NSStackView stackViewWithViews:@[view]];
    stack.edgeInsets = NSEdgeInsetsMake(0, inset, 0, 0);
    return stack;
}

/*
 * settle — a setting was written: show it, and tell the app.
 */
- (void)
settle
{
    [self rebuild];
    self.changed();
}

/*
 * toggled: — the switch: on asks for access when the system has not yet.
 *
 * Inputs:
 *   sender — the checkbox
 */
- (void)
toggled:(NSButton *)sender
{
    BOOL on = sender.state == NSControlStateValueOn;
    [self.settings set_calendar_setting:SHARED_CALENDAR_ENABLED value:on ? @"1" : @"0"];
    if (on && shared_calendar_access() == SharedCalendarAccessUnasked) {
        __weak SharedCalendarSection *ws = self;
        shared_calendar_request_access(^(BOOL granted) { [ws settle]; });
        return;
    }
    [self settle];
}

/*
 * tasks_calendar_chosen: — the calendar Tasks' sessions go to.
 *
 * Inputs:
 *   sender — the popup
 */
- (void)
tasks_calendar_chosen:(NSPopUpButton *)sender
{
    [self.settings set_calendar_setting:SHARED_CALENDAR_TASKS
                                  value:sender.selectedItem.representedObject];
    [self settle];
}

/*
 * shown_toggled: — a calendar's checkbox: the shown set is rewritten from
 * every box; all ticked is stored as unset, so a calendar added later
 * shows too.
 *
 * Inputs:
 *   sender — the checkbox (unused: every box is read)
 */
- (void)
shown_toggled:(NSButton *)sender
{
    NSMutableArray<NSString *> *ids = [NSMutableArray array];
    BOOL all = YES;
    for (NSString *id in self.boxes) {
        if (self.boxes[id].state == NSControlStateValueOn) [ids addObject:id];
        else                                               all = NO;
    }
    [self.settings set_calendar_setting:SHARED_CALENDAR_SHOWN
                                  value:all ? nil : [ids componentsJoinedByString:@"\n"]];
    [self settle];
}

/*
 * open_privacy: — System Settings at the Calendars privacy list.
 *
 * Inputs:
 *   sender — the button (unused)
 */
- (void)
open_privacy:(id)sender
{
    [NSWorkspace.sharedWorkspace openURL:[NSURL URLWithString:privacy_url]];
}

@end
