/*
 * shared_calendar — the macOS Calendar (EventKit), as both apps' day
 * planners use it.  The apps never talk to Google or any other calendar
 * service: the accounts are the ones set up in the Calendar app (Google,
 * iCloud, Exchange, …), which keeps them in sync.  This module holds the
 * one EKEventStore, asks for access, lists the calendars, reads a day's
 * events for the planner, reports changes, and builds the Calendar
 * section both Settings windows show.
 *
 * THE SETTINGS are shared by Notes and Tasks: one switch, one choice of
 * shown calendars, one calendar for Tasks' sessions, kept in the shared
 * database's shared_settings under the SHARED_CALENDAR_* keys below.  This
 * module reads and writes them through the app's SharedCalendarSettings
 * object (the shared database is the app's).
 *
 * PRIVACY.  Nothing here touches EventKit until the switch is on: no store
 * is made and no access is asked for, so an app that never turns the
 * calendar on never shows the system's prompt.  Access is asked for when
 * the switch is turned on; the bundle's Info.plist says why
 * (NSCalendarsFullAccessUsageDescription).
 *
 * Main thread only.
 */

#import <Cocoa/Cocoa.h>
#import <EventKit/EventKit.h>

#import "shared_day_planner.h"

/* The shared_settings keys (shared_db.h's table; this module owns them). */
#define SHARED_CALENDAR_ENABLED "calendar_enabled"  /* "1": the planners show the calendar,
                                                     * and Tasks writes its sessions to it */
#define SHARED_CALENDAR_SHOWN   "calendar_shown"    /* the shown calendars' identifiers, one
                                                     * per line; unset: every calendar     */
#define SHARED_CALENDAR_TASKS   "calendar_tasks"    /* the calendar Tasks' sessions go to;
                                                     * unset, gone or read-only: Calendar's
                                                     * default for new events             */

/*
 * SharedCalendarSettings — the app's access to the shared settings: the
 * module never opens the shared database itself.
 */
@protocol SharedCalendarSettings <NSObject>

/*
 * calendar_setting: — read one setting.
 *
 * Inputs:
 *   key — a SHARED_CALENDAR_* key
 *
 * Output: the value, or nil when it is unset or cannot be read.
 */
- (NSString *)calendar_setting:(const char *)key;

/*
 * set_calendar_setting:value: — write one setting.
 *
 * Inputs:
 *   key   — a SHARED_CALENDAR_* key
 *   value — the value; nil removes it
 */
- (void)set_calendar_setting:(const char *)key value:(NSString *)value;

@end

/* Whether the app may read the calendar. */
typedef NS_ENUM(NSInteger, SharedCalendarAccess) {
    SharedCalendarAccessUnasked,     /* the system has not asked yet           */
    SharedCalendarAccessGranted,     /* full access                            */
    SharedCalendarAccessDenied,      /* refused, restricted, or write-only     */
};

/*
 * shared_calendar_access — what the system allows now.  Never prompts.
 *
 * Output: the access.
 */
SharedCalendarAccess shared_calendar_access(void);

/*
 * shared_calendar_request_access — ask for full access (the system's
 * prompt, the first time only).
 *
 * Inputs:
 *   done — called on the main thread with whether access is granted
 */
void shared_calendar_request_access(void (^done)(BOOL granted));

/*
 * shared_calendar_on — whether the calendar is in use: the switch is on
 * and access is granted.
 *
 * Inputs:
 *   settings — the app's settings
 *
 * Output: YES when it is.
 */
BOOL shared_calendar_on(id<SharedCalendarSettings> settings);

/*
 * shared_calendar_store — THE event store, made on first use.
 *
 * Output: the store, or nil without full access.
 */
EKEventStore *shared_calendar_store(void);

/*
 * shared_calendar_for_tasks — the calendar Tasks' sessions go to: the
 * SHARED_CALENDAR_TASKS setting's while it exists and can be written,
 * else Calendar's default for new events.
 *
 * Inputs:
 *   settings — the app's settings
 *
 * Output: the calendar, or nil without access or a writable calendar.
 */
EKCalendar *shared_calendar_for_tasks(id<SharedCalendarSettings> settings);

/*
 * shared_calendar_day_events — the events of the shown calendars that
 * overlap [lo, hi), as planner items: their ids, occurrence, title,
 * times, all-day flag, calendar colour and attendees.  Cancelled events,
 * and invitations the account's own attendee declined, are left out.
 *
 * Inputs:
 *   settings — the app's settings
 *   lo, hi   — the window, unix seconds
 *   skip     — event identifiers to leave out (Tasks' own session
 *              events, drawn as the tasks they are); may be nil
 *
 * Output: the items; empty while the calendar is not on.
 */
NSArray<SharedDayItem *> *shared_calendar_day_events(id<SharedCalendarSettings> settings,
                                                     int64_t lo, int64_t hi,
                                                     NSSet<NSString *> *skip);

/*
 * shared_calendar_observe — call a block whenever the calendar changes:
 * an event or a calendar added, edited or deleted, here, in the Calendar
 * app, or by its sync with an account (EKEventStoreChangedNotification).
 * The block runs on the main thread.
 *
 * Inputs:
 *   changed — the block
 *
 * Output: the observation, for shared_calendar_unobserve.
 */
id shared_calendar_observe(void (^changed)(void));

/*
 * shared_calendar_unobserve — stop an observation.  nil is ignored.
 *
 * Inputs:
 *   token — what shared_calendar_observe returned
 */
void shared_calendar_unobserve(id token);

/*
 * SharedCalendarSection — the Calendar section of both Settings windows
 * (the app adds the heading): a word on where the accounts come from, the
 * switch, what to do when access is refused, and, while the calendar is
 * on, the shown calendars by account; for Tasks also the calendar its
 * sessions go to.  It rebuilds itself when the calendars change.
 */
@interface SharedCalendarSection : NSObject

/*
 * init_with_settings:tasks:width:changed: — build the section.
 *
 * Inputs:
 *   settings — the app's settings (held)
 *   tasks    — YES to offer the calendar Tasks' sessions go to
 *   width    — the width its explanations wrap at
 *   changed  — called after the user changed a setting, and after the
 *              section rebuilt itself (it may have changed height)
 *
 * Output: the section.
 */
- (instancetype)init_with_settings:(id<SharedCalendarSettings>)settings
                             tasks:(BOOL)tasks
                             width:(CGFloat)width
                           changed:(void (^)(void))changed NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

/* The section's rows, in one vertical stack. */
@property (nonatomic, readonly) NSStackView *view;

/*
 * shut_down — stop watching the calendar.  Call when the window closes.
 */
- (void)shut_down;

@end
