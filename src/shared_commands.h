/*
 * shared_commands — THE way Notes and Tasks name, dispatch and validate
 * their commands.  An app installs ONE table of its commands at launch;
 * menu items, toolbar items, context-menu items and bar buttons are all
 * made FROM it, so a command's wording, shortcut, glyph and tooltip are
 * written once — the table is the app's keyboard map.
 *
 * A command is a stable string identifier ("new-note", "toggle-sidebar")
 * with a title, a key equivalent with its FULL modifier mask, a scope, and
 * the glyph (an SF Symbol) and tooltip of its buttons.
 *
 * WHO RUNS A COMMAND.  Each command has a scope:
 *
 *   app     the command works from whichever window is in front (New Note,
 *           Settings…).  Its items target the app delegate's
 *           run_app_command:, which runs it (or hands it to the library).
 *   window  the command belongs to the window in front (Find…, Bold).  Its
 *           items have no target: AppKit sends run_command: up the
 *           responder chain, where the key window's controller picks it
 *           up.  The same shortcut can therefore mean different things in
 *           two windows, and an item whose window does not handle the
 *           command is disabled.
 *
 * A module that implements commands declares a static table of
 * shared_command_handler_t and runs or validates through it
 * (shared_command_run / shared_command_validate) from its run_command: /
 * run_app_command: and validateUserInterfaceItem:.  A command nobody has
 * a handler for is simply disabled.
 *
 * HOW A COMMAND LOOKS.  Validation builds a SharedCommandState from the
 * table (enabled, the table's title, icon and tooltip, no check mark),
 * lets the handler adjust it (a toggle's other face, a count in the
 * title, a check mark) and applies it to the item, so a menu item and its
 * button twins cannot disagree.  A toggling command's title, icon and
 * tooltip name what a click WILL DO ("Hide Completed" while they are
 * shown).  A menu item that carries a PARAMETER keeps the title it was
 * built with (a tag's name): validation changes only whether it is
 * enabled.
 *
 * The standard Edit items (Undo, Redo, Cut, Copy, Paste, Select All) are
 * NOT commands: they use AppKit's own selectors with no target, so they
 * work in every text field.
 */

#import <Cocoa/Cocoa.h>

/* Where a command's items send it. */
typedef NS_ENUM(NSInteger, SharedCommandScope) {
    SharedCommandScopeApp,
    SharedCommandScopeWindow,
};

/* One command.  A row of the app's table. */
typedef struct {
    NSString * __unsafe_unretained ident;   /* stable id, e.g. @"new-note"            */
    NSString * __unsafe_unretained title;   /* menu title; a toggle's first face      */
    NSString * __unsafe_unretained key;     /* key equivalent; @"" = none             */
    NSEventModifierFlags           mods;    /* the shortcut's modifiers, the full mask */
    SharedCommandScope             scope;
    NSString * __unsafe_unretained icon;    /* SF Symbol of its buttons (shared_ui_symbol);
                                               nil = never a button                   */
    NSString * __unsafe_unretained tooltip; /* its buttons' hover text, saying what it
                                               does; nil = the title                  */
} shared_command_t;

/*
 * SharedCommandState — how a command looks right now: the table's values
 * (shared_command_default_state), adjusted by the command's handler.
 */
@interface SharedCommandState : NSObject
@property (nonatomic, assign) BOOL      enabled;
@property (nonatomic, assign) BOOL      checked;    /* menu check mark        */
@property (nonatomic, copy)   NSString *title;
@property (nonatomic, copy)   NSString *icon;       /* SF Symbol name, or nil */
@property (nonatomic, copy)   NSString *tooltip;    /* or nil                 */
@end

/* One command's implementation, in the module that owns it.
 *   run      — do it.  `target` is the object the dispatcher passes (the
 *              library, a window controller); `sender` is the item, whose
 *              parameter shared_command_param reads.
 *   validate — may the command run now?  It may also adjust `state` for
 *              the current look (shared_command_state_set: a check mark,
 *              "Hide Sidebar" vs "Show Sidebar", the list/grid icon).
 *              `item` is the item being validated, or nil when only the
 *              state is asked for.  NULL = always enabled. */
typedef struct {
    NSString * __unsafe_unretained ident;
    void (*run)(id target, id sender);
    BOOL (*validate)(id target, id item, SharedCommandState *state);
} shared_command_handler_t;

/*
 * shared_commands_install — the app's command table, once at launch,
 * before any item is made from it.
 *
 * Inputs:
 *   table — the commands (static storage; kept by reference)
 *   n     — how many
 */
void shared_commands_install(const shared_command_t *table, size_t n);

/*
 * shared_commands_table — the installed table, for a probe that checks
 * every command has a place in the menu bar.
 *
 * Inputs:
 *   n — receives how many rows
 *
 * Output: the table; NULL before one is installed.
 */
const shared_command_t *shared_commands_table(size_t *n);

/*
 * shared_command_find — a command's row.
 *
 * Inputs:
 *   ident — the command's identifier
 *
 * Output: the row, or NULL for an unknown identifier.
 */
const shared_command_t *shared_command_find(NSString *ident);

/*
 * shared_command_ident — which command an item stands for.
 *
 * Inputs:
 *   item — a menu item, toolbar item or control made by the functions
 *          below, or a control whose identifier is set to the command's
 *
 * Output: the command's identifier, or nil for any other object.
 */
NSString *shared_command_ident(id item);

/*
 * shared_command_param — a command's parameter: what a menu item carries
 * in its representedObject (a tag id, a flag's direction).
 *
 * Inputs:
 *   sender — the item
 *
 * Output: the parameter, or nil.
 */
id shared_command_param(id sender);

/*
 * shared_command_tooltip — the hover help of a control that runs a
 * command: its tooltip, else its title.
 *
 * Inputs:
 *   ident — the command's identifier (must be in the table)
 *
 * Output: the text.
 */
NSString *shared_command_tooltip(NSString *ident);

/*
 * shared_command_menu_item — a menu item for a command: title, shortcut,
 * target and action per its scope, the parameter in representedObject.
 * For the main menu and context menus alike.
 *
 * Inputs:
 *   ident — the command's identifier (must be in the table)
 *   param — the command's parameter, or nil
 *
 * Output: a new menu item.
 */
NSMenuItem *shared_command_menu_item(NSString *ident, id param);

/*
 * shared_command_toolbar_item — a toolbar item for a command: its glyph
 * (an SF Symbol template, sized by the toolbar), its title as label and
 * its tooltip, target and action per its scope.  The item's identifier is
 * the command's.
 *
 * Inputs:
 *   ident — the command's identifier (must be in the table, with an icon)
 *
 * Output: a new toolbar item.
 */
NSToolbarItem *shared_command_toolbar_item(NSString *ident);

/*
 * shared_command_button — an icon-only, borderless button for a command,
 * for controls that sit over a pane (Compact mode's floating pair): its
 * glyph (shared_look_cmd_btn_icon points) and tooltip from the table,
 * target and action per its scope, its identifier the command's.  Nothing
 * validates such a button by itself: its owner applies a state to it with
 * shared_command_apply.
 *
 * Inputs:
 *   ident — the command's identifier (must be in the table, with an icon)
 *
 * Output: a new button, shared_look_cmd_btn points square.
 */
NSButton *shared_command_button(NSString *ident);

/*
 * shared_command_default_state — the state the table gives a command:
 * enabled, unchecked, with the table's title, icon and tooltip.
 *
 * Inputs:
 *   ident — the command's identifier
 *
 * Output: a new state; disabled and empty for an unknown identifier.
 */
SharedCommandState *shared_command_default_state(NSString *ident);

/*
 * shared_command_state_set — a handler's shorthand for the current look.
 * A title given here is also the buttons' tooltip (a toggle's other face
 * names what a click will do); a handler wanting other hover text sets
 * state.tooltip after.
 *
 * Inputs:
 *   state   — the state being adjusted
 *   title   — a title for this state; nil keeps the table's
 *   icon    — an SF Symbol name for this state; nil keeps the table's
 *   checked — YES to show a check mark (menu items)
 */
void shared_command_state_set(SharedCommandState *state, NSString *title, NSString *icon, BOOL checked);

/*
 * shared_command_apply — make a control show a command's state.  Only
 * what differs is set: AppKit validates after every event, and a toolbar
 * item given an image (even the same one) is redrawn; glyphs are cached,
 * so an unchanged one is the same object.
 *
 * Inputs:
 *   state — the state to show
 *   item  — an NSMenuItem (title, enabled, check mark), an NSToolbarItem
 *           or an NSButton (glyph, tooltip, enabled)
 */
void shared_command_apply(SharedCommandState *state, id item);

/*
 * shared_command_run — run the command an item stands for, if a table has
 * it.
 *
 * Inputs:
 *   table  — a module's handlers
 *   n      — how many
 *   target — passed to the handler
 *   sender — the item
 *
 * Output: YES when a handler was found and run.
 */
BOOL shared_command_run(const shared_command_handler_t *table, size_t n, id target, id sender);

/*
 * shared_command_state — how a command looks right now, per a table: the
 * table's defaults adjusted by the handler's validate.
 *
 * Inputs:
 *   table  — a module's handlers
 *   n      — how many
 *   target — passed to the handler
 *   ident  — the command's identifier
 *
 * Output: the state, or nil when the table does not have the command.
 */
SharedCommandState *shared_command_state(const shared_command_handler_t *table, size_t n,
                                         id target, NSString *ident);

/*
 * shared_command_validate — whether an item's command can run now, per a
 * table, applying the command's current look to the item.  An item that
 * carries a parameter keeps its title.
 *
 * Inputs:
 *   table   — a module's handlers
 *   n       — how many
 *   target  — passed to the handler
 *   item    — the item being validated
 *   handled — receives YES when the table has the item's command; may be
 *             NULL
 *
 * Output: YES when the command is in the table and enabled.
 */
BOOL shared_command_validate(const shared_command_handler_t *table, size_t n, id target, id item,
                             BOOL *handled);
