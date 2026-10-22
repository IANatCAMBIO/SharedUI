/*
 * shared_hotkey — an app's system-wide shortcut: pressed in any app, it
 * runs a block in this one.  Only while the app is running.  Tasks'
 * Quick Task (⌃⌥⌘T) and Notes' New Note (⌃⌥⌘N) use it.
 *
 * Registered through Carbon's RegisterEventHotKey, the one system-wide
 * shortcut API that needs no Accessibility permission.  The app's menu
 * item shows the same shortcut; while the hotkey is registered it takes
 * the key first, so the two never both run.  The app's own setting says
 * whether the shortcut is wanted.
 *
 * One shortcut per process.  Main thread only; the handler runs on the
 * main thread.
 */

#import <Cocoa/Cocoa.h>
#import <Carbon/Carbon.h>

/*
 * shared_hotkey_t — what the shortcut is and when it is wanted.
 *
 *   key_code  — a virtual key code (kVK_ANSI_T)
 *   modifiers — Carbon modifier bits (controlKey | optionKey | cmdKey)
 *   signature — four characters naming this app's hotkey
 *   wanted    — reads the app's setting: YES when the shortcut is on
 */
typedef struct {
    UInt32   key_code;
    UInt32   modifiers;
    OSType   signature;
    BOOL   (*wanted)(void);
} shared_hotkey_t;

/*
 * shared_hotkey_start — install the handler and register the shortcut if
 * it is wanted.  Call once at launch.
 *
 * Inputs:
 *   hotkey — the shortcut; a STATIC value, kept by reference
 *   fire   — what a press does; kept until shared_hotkey_stop
 *
 * Output:
 *   NO when the shortcut is wanted but could not be registered (another
 *   app holds it); YES otherwise.
 */
BOOL shared_hotkey_start(const shared_hotkey_t *hotkey, void (^fire)(void));

/*
 * shared_hotkey_apply — register or unregister the shortcut to match the
 * setting (Settings calls this when the checkbox changes).  Does nothing
 * before shared_hotkey_start.
 *
 * Output:
 *   NO when the shortcut is wanted but could not be registered; YES
 *   otherwise.
 */
BOOL shared_hotkey_apply(void);

/*
 * shared_hotkey_stop — unregister the shortcut, remove the handler and let
 * go of the block.  Called at quit; idempotent.
 */
void shared_hotkey_stop(void);
