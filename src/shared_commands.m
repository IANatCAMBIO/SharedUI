/*
 * shared_commands.m — see shared_commands.h.  Notes' commands.m (the
 * identifiers, the scopes, the handler tables) and Tasks' (the state
 * object, the parameter, the bar button) made one.
 */

#import "shared_commands.h"
#import "shared_ui.h"

#include "shared_look.h"

@implementation SharedCommandState
@end

/* The app's table, installed once. */
static const shared_command_t *commands;
static size_t                  command_count;

/*
 * shared_commands_install — see shared_commands.h.
 */
void
shared_commands_install(const shared_command_t *table, size_t n)
{
    commands      = table;
    command_count = n;
}

/*
 * shared_commands_table — see shared_commands.h.
 */
const shared_command_t *
shared_commands_table(size_t *n)
{
    *n = command_count;
    return commands;
}

/*
 * shared_command_find — see shared_commands.h.
 */
const shared_command_t *
shared_command_find(NSString *ident)
{
    for (size_t i = 0; i < command_count; i++) {
        if ([commands[i].ident isEqualToString:ident]) return &commands[i];
    }
    return NULL;
}

/*
 * command_action — the selector a command's items send: run_app_command:
 * to the app delegate for app scope, run_command: up the responder chain
 * for window scope.
 *
 * Inputs:
 *   command — the command
 *   target  — receives the items' target (nil for the responder chain)
 *
 * Output: the selector.
 */
static SEL
command_action(const shared_command_t *command, id *target)
{
    if (command->scope == SharedCommandScopeApp) {
        *target = NSApp.delegate;
        return @selector(run_app_command:);
    }
    *target = nil;
    return @selector(run_command:);
}

/*
 * shared_command_ident — see shared_commands.h.
 */
NSString *
shared_command_ident(id item)
{
    if ([item isKindOfClass:NSToolbarItem.class]) return ((NSToolbarItem *)item).itemIdentifier;
    if ([item isKindOfClass:NSMenuItem.class] || [item isKindOfClass:NSControl.class])
        return ((id<NSUserInterfaceItemIdentification>)item).identifier;
    return nil;
}

/*
 * shared_command_param — see shared_commands.h.
 */
id
shared_command_param(id sender)
{
    return [sender isKindOfClass:NSMenuItem.class] ? ((NSMenuItem *)sender).representedObject : nil;
}

/*
 * shared_command_tooltip — see shared_commands.h.
 */
NSString *
shared_command_tooltip(NSString *ident)
{
    const shared_command_t *command = shared_command_find(ident);
    NSCAssert(command != NULL, @"unknown command %@", ident);
    return command->tooltip ?: command->title;
}

/*
 * shared_command_menu_item — see shared_commands.h.
 */
NSMenuItem *
shared_command_menu_item(NSString *ident, id param)
{
    const shared_command_t *command = shared_command_find(ident);
    NSCAssert(command != NULL, @"unknown command %@", ident);
    id  target = nil;
    SEL action = command_action(command, &target);
    NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:command->title
                                                  action:action
                                           keyEquivalent:command->key];
    item.keyEquivalentModifierMask = command->mods;
    item.target            = target;
    item.identifier        = command->ident;
    item.representedObject = param;
    return item;
}

/*
 * shared_command_toolbar_item — see shared_commands.h.
 */
NSToolbarItem *
shared_command_toolbar_item(NSString *ident)
{
    const shared_command_t *command = shared_command_find(ident);
    NSCAssert(command != NULL && command->icon != nil, @"no toolbar command %@", ident);
    id  target = nil;
    SEL action = command_action(command, &target);
    NSToolbarItem *item = [[NSToolbarItem alloc] initWithItemIdentifier:command->ident];
    item.label    = command->title;
    item.toolTip  = shared_command_tooltip(ident);
    item.image    = shared_ui_symbol(command->icon, 0.0);
    item.target   = target;
    item.action   = action;
    item.bordered = YES;
    return item;
}

/*
 * shared_command_button — see shared_commands.h.
 */
NSButton *
shared_command_button(NSString *ident)
{
    const CGFloat size = shared_look_cmd_btn;
    const shared_command_t *command = shared_command_find(ident);
    NSCAssert(command != NULL && command->icon != nil, @"no button command %@", ident);
    id  target = nil;
    SEL action = command_action(command, &target);
    NSButton *button = [[NSButton alloc] initWithFrame:NSMakeRect(0, 0, size, size)];
    button.bordered      = NO;
    button.imagePosition = NSImageOnly;
    button.image         = shared_ui_symbol(command->icon, shared_look_cmd_btn_icon);
    button.toolTip       = shared_command_tooltip(ident);
    button.identifier    = command->ident;
    button.target        = target;
    button.action        = action;
    /* A click must not take the keyboard away from the pane under it. */
    button.refusesFirstResponder = YES;
    button.accessibilityLabel    = command->title;
    button.translatesAutoresizingMaskIntoConstraints = NO;
    [button.widthAnchor constraintEqualToConstant:size].active  = YES;
    [button.heightAnchor constraintEqualToConstant:size].active = YES;
    return button;
}

/*
 * shared_command_default_state — see shared_commands.h.
 */
SharedCommandState *
shared_command_default_state(NSString *ident)
{
    const shared_command_t *command = ident ? shared_command_find(ident) : NULL;
    SharedCommandState *state = [[SharedCommandState alloc] init];
    state.enabled = command != NULL;
    if (command) {
        state.title   = command->title;
        state.icon    = command->icon;
        state.tooltip = command->tooltip ?: command->title;
    }
    return state;
}

/*
 * shared_command_state_set — see shared_commands.h.
 */
void
shared_command_state_set(SharedCommandState *state, NSString *title, NSString *icon, BOOL checked)
{
    if (title) {
        state.title   = title;
        state.tooltip = title;
    }
    if (icon) state.icon = icon;
    state.checked = checked;
}

/*
 * shared_command_apply — see shared_commands.h.
 */
void
shared_command_apply(SharedCommandState *state, id item)
{
    if ([item isKindOfClass:NSMenuItem.class]) {
        NSMenuItem *menu_item = item;
        if (![menu_item.title isEqualToString:state.title]) menu_item.title = state.title;
        menu_item.enabled = state.enabled;
        menu_item.state   = state.checked ? NSControlStateValueOn : NSControlStateValueOff;
        return;
    }
    /* A toolbar item or a button: the two answer the same getters and
     * setters.  A toolbar item's glyph has no size of its own; a button's
     * is shared_command_button's. */
    NSImage *icon = nil;
    if (state.icon) {
        icon = [item isKindOfClass:NSToolbarItem.class]
             ? shared_ui_symbol(state.icon, 0.0)
             : shared_ui_symbol(state.icon, shared_look_cmd_btn_icon);
    }
    if ([item image] != icon) [item setImage:icon];
    if ([item isKindOfClass:NSToolbarItem.class] &&
        ![((NSToolbarItem *)item).label isEqualToString:state.title])
        ((NSToolbarItem *)item).label = state.title;
    NSString *tooltip = [item toolTip];
    if (tooltip != state.tooltip && ![tooltip isEqualToString:state.tooltip]) {
        [item setToolTip:state.tooltip];
    }
    if ([item isEnabled] != state.enabled) [item setEnabled:state.enabled];
}

/*
 * handler_for — a command's handler in a table.
 *
 * Inputs:
 *   table — a module's handlers
 *   n     — how many
 *   ident — the command's identifier; nil finds nothing
 *
 * Output: the handler, or NULL when the table does not have the command.
 */
static const shared_command_handler_t *
handler_for(const shared_command_handler_t *table, size_t n, NSString *ident)
{
    if (!ident) return NULL;
    for (size_t i = 0; i < n; i++) {
        if ([table[i].ident isEqualToString:ident]) return &table[i];
    }
    return NULL;
}

/*
 * shared_command_run — see shared_commands.h.
 */
BOOL
shared_command_run(const shared_command_handler_t *table, size_t n, id target, id sender)
{
    const shared_command_handler_t *handler = handler_for(table, n, shared_command_ident(sender));
    if (handler == NULL) return NO;
    handler->run(target, sender);
    return YES;
}

/*
 * state_from — a handler's state for an item (or for none).
 *
 * Inputs:
 *   handler — the handler
 *   target  — passed to its validate
 *   item    — the item being validated, or nil
 *
 * Output: the state.
 */
static SharedCommandState *
state_from(const shared_command_handler_t *handler, id target, id item)
{
    SharedCommandState *state = shared_command_default_state(handler->ident);
    state.enabled = handler->validate == NULL || handler->validate(target, item, state);
    return state;
}

/*
 * shared_command_state — see shared_commands.h.
 */
SharedCommandState *
shared_command_state(const shared_command_handler_t *table, size_t n, id target, NSString *ident)
{
    const shared_command_handler_t *handler = handler_for(table, n, ident);
    return handler ? state_from(handler, target, nil) : nil;
}

/*
 * shared_command_validate — see shared_commands.h.
 */
BOOL
shared_command_validate(const shared_command_handler_t *table, size_t n, id target, id item,
                        BOOL *handled)
{
    const shared_command_handler_t *handler = handler_for(table, n, shared_command_ident(item));
    if (handled) *handled = handler != NULL;
    if (handler == NULL) return NO;
    SharedCommandState *state = state_from(handler, target, item);
    if ([item isKindOfClass:NSMenuItem.class] && ((NSMenuItem *)item).representedObject != nil)
        state.title = ((NSMenuItem *)item).title;    /* a parameter's own wording stays */
    shared_command_apply(state, item);
    return state.enabled;
}
