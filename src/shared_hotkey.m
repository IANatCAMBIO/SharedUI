#import "shared_hotkey.h"

static const shared_hotkey_t *spec;          /* NULL until started     */
static EventHandlerRef handler_ref;          /* NULL until started     */
static EventHotKeyRef  hotkey_ref;           /* NULL while unregistered */
static void (^fire_block)(void);

/*
 * on_hotkey — Carbon's callback for a hotkey press: run the block if the
 * press is ours.
 *
 * Inputs:
 *   call  — the handler chain (unused)
 *   event — the kEventHotKeyPressed event
 *   data  — unused
 *
 * Output:
 *   noErr when handled, eventNotHandledErr for another hotkey.
 */
static OSStatus
on_hotkey(EventHandlerCallRef call, EventRef event, void *data)
{
    EventHotKeyID id = { 0, 0 };
    GetEventParameter(event, kEventParamDirectObject, typeEventHotKeyID, NULL,
                      sizeof id, NULL, &id);
    if (spec == NULL || id.signature != spec->signature || fire_block == nil)
        return eventNotHandledErr;
    fire_block();
    return noErr;
}

/*
 * shared_hotkey_start — install the handler, then match the setting.
 * Inputs/output are documented in shared_hotkey.h.
 */
BOOL
shared_hotkey_start(const shared_hotkey_t *hotkey, void (^fire)(void))
{
    if (handler_ref == NULL) {
        EventTypeSpec types = { kEventClassKeyboard, kEventHotKeyPressed };
        InstallApplicationEventHandler(on_hotkey, 1, &types, NULL, &handler_ref);
    }
    spec       = hotkey;
    fire_block = fire;
    return shared_hotkey_apply();
}

/*
 * shared_hotkey_apply — register or unregister to match the setting.
 * Output is documented in shared_hotkey.h.
 */
BOOL
shared_hotkey_apply(void)
{
    if (handler_ref == NULL) return YES;

    BOOL wanted = spec->wanted();
    if (!wanted && hotkey_ref != NULL) {
        UnregisterEventHotKey(hotkey_ref);
        hotkey_ref = NULL;
    } else if (wanted && hotkey_ref == NULL) {
        EventHotKeyID id = { spec->signature, 1 };
        if (RegisterEventHotKey(spec->key_code, spec->modifiers, id, GetApplicationEventTarget(),
                                0, &hotkey_ref) != noErr) {
            hotkey_ref = NULL;
            return NO;
        }
    }
    return YES;
}

/*
 * shared_hotkey_stop — unregister, remove the handler, drop the block.
 */
void
shared_hotkey_stop(void)
{
    if (hotkey_ref != NULL) UnregisterEventHotKey(hotkey_ref);
    if (handler_ref != NULL) RemoveEventHandler(handler_ref);
    hotkey_ref  = NULL;
    handler_ref = NULL;
    spec        = NULL;
    fire_block  = nil;
}
