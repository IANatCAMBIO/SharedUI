/*
 * shared_ui_test.m — the helpers that need no window: colours, glyphs,
 * image views, tag labels, formatting, the picker kinds, the table's
 * activation rule, the split controller's width report and the command
 * table (items, dispatch, validation).  The apps' own UI probes exercise
 * the panels and tables on screen.
 */

#import "shared_commands.h"
#import "shared_ui.h"
#import "shared_tool_panel.h"

#include "check.h"
#include "shared_order.h"

#include <stdlib.h>
#include <string.h>

/*
 * TestClicks — a button target that counts the clicks it receives.
 */
@interface TestClicks : NSObject
@property (nonatomic, assign) int count;
@end

@implementation TestClicks

/*
 * clicked: — one more.
 *
 * Inputs:
 *   sender — the button (unused)
 */
- (void)
clicked:(id)sender
{
    self.count++;
}

@end

/*
 * mouse — a left-button event over a point of a window, queued for the
 * window's tracking loop (SharedFavoriteButton reads its drags and the
 * release from the queue).
 *
 * Inputs:
 *   type   — down, dragged or up
 *   window — the window
 *   at     — the point, in the window's coordinates
 *
 * Output: the event, also posted.
 */
static NSEvent *
mouse(NSEventType type, NSWindow *window, NSPoint at)
{
    NSEvent *event = [NSEvent mouseEventWithType:type location:at modifierFlags:0
                                       timestamp:NSProcessInfo.processInfo.systemUptime
                                    windowNumber:window.windowNumber context:nil
                                     eventNumber:0 clickCount:1 pressure:1.0];
    [NSApp postEvent:event atStart:NO];
    return event;
}

/* A two-command table, one of each scope, and a module handling it. */
static const shared_command_t test_commands[] = {
    { @"test-new",    @"New Thing",  @"n", NSEventModifierFlagCommand, SharedCommandScopeApp,
      @"plus", @"Make a thing" },
    { @"test-toggle", @"Hide Panel", @"",  0,                          SharedCommandScopeWindow,
      @"eye.slash", nil },
};

static int  runs;           /* how many times a handler ran               */
static id   run_param;      /* the parameter the last run carried         */
static BOOL panel_hidden;   /* the toggle's state                         */

/*
 * run_new — the test's "new" handler: counts, keeps the parameter.
 *
 * Inputs:
 *   target — unused
 *   sender — the item
 */
static void
run_new(id target, id sender)
{
    runs++;
    run_param = shared_command_param(sender);
}

/*
 * run_toggle — the test's toggle handler.
 *
 * Inputs:
 *   target — unused
 *   sender — the item (unused)
 */
static void
run_toggle(id target, id sender)
{
    panel_hidden = !panel_hidden;
}

/*
 * validate_toggle — the toggle's other face while the panel is hidden;
 * disabled when the target says so.
 *
 * Inputs:
 *   target — an NSNumber: NO disables the command
 *   item   — the item (unused)
 *   state  — adjusted
 *
 * Output: whether the command may run.
 */
static BOOL
validate_toggle(id target, id item, SharedCommandState *state)
{
    shared_command_state_set(state, panel_hidden ? @"Show Panel" : nil,
                             panel_hidden ? @"eye" : nil, panel_hidden);
    return [target boolValue];
}

static const shared_command_handler_t test_handlers[] = {
    { @"test-new",    run_new,    NULL            },
    { @"test-toggle", run_toggle, validate_toggle },
};
#define TEST_HANDLER_COUNT (sizeof test_handlers / sizeof test_handlers[0])

/*
 * main — run the checks.
 *
 * Output: 0 when every check passed.
 */
int
main(void)
{
    @autoreleasepool {
        [NSApplication sharedApplication];

        /* Colours: one object per value, resolving per appearance. */
        NSColor *hero = shared_ui_color(shared_look_hero);
        check(hero != nil && shared_ui_color(shared_look_hero) == hero,
              "shared_ui_color keeps one colour per value");
        check(shared_ui_color(shared_look_due_today) != hero, "and another value is another colour");
        check(shared_look_pick(shared_look_due_today, true).r == shared_look_due_today.dark.r &&
              shared_look_pick(shared_look_due_today, false).r == shared_look_due_today.light.r,
              "shared_look_pick takes the dark or the light value");

        /* Glyphs: template images, cached per name and size. */
        NSImage *plus = shared_ui_symbol(@"plus", 0.0);
        check(plus != nil && plus.template && shared_ui_symbol(@"plus", 0.0) == plus,
              "shared_ui_symbol makes a template glyph, once per name and size");
        check(shared_ui_symbol(@"plus", 16.0) != plus, "a sized glyph is another image");
        check(shared_ui_symbol(@"no.such.symbol.shared", 0.0) == nil, "and nil for an unknown name");

        /* An image view is framed before it gets its image. */
        NSImageView *view = shared_ui_image_view(plus, 24, 16);
        check(NSEqualSizes(view.frame.size, NSMakeSize(24, 16)) && view.image == plus,
              "shared_ui_image_view makes its view at the final size");

        /* Tag labels. */
        check([shared_ui_tag_label(@"🛒", @"Errands") isEqualToString:@"🛒  Errands"],
              "tag label: emoji, two spaces, name");
        check([shared_ui_tag_label(@"", @"Someday") isEqualToString:@"Someday"] &&
              [shared_ui_tag_label(nil, @"Someday") isEqualToString:@"Someday"],
              "tag label: the name alone without an emoji");
        check([shared_ui_label_name(@"🛒  Errands") isEqualToString:@"Errands"] &&
              [shared_ui_label_name(@"Someday") isEqualToString:@"Someday"],
              "label name: the name after the emoji, or the whole label");

        /* Formatting. */
        check([shared_ui_format_bytes(0) length] > 0 &&
              [shared_ui_format_bytes(12300000) containsString:@"MB"],
              "format bytes: Finder's style");
        check([shared_ui_format_date(0, shared_ui_date_iso) length] == 10,
              "format date: the ISO pattern is ten characters");

        /* The emoji slot keeps one character and is the shared width. */
        NSTextField *emoji = shared_ui_emoji_field(@"🧪");
        check([emoji.stringValue isEqualToString:@"🧪"] && emoji.editable,
              "the emoji slot starts with the tag's emoji, editable");

        /* Saved orders: the saved ids first, the rest in their order. */
        int64_t ids[] = { 10, 20, 30, 40 };
        int *order = shared_order_permutation(ids, 4, "30,junk,99,10");
        check(order != NULL && order[0] == 2 && order[1] == 0 && order[2] == 1 && order[3] == 3,
              "order: the saved ids first in their sequence, unknown tokens skipped, the rest after");
        free(order);
        check(shared_order_permutation(ids, 4, NULL) == NULL && shared_order_permutation(ids, 4, "") == NULL &&
              shared_order_permutation(ids, 1, "10") == NULL,
              "order: nothing to do without a saved order or a second id");
        char *text = shared_order_text((int64_t[]){ 30, 0, 10 }, 3);
        check(text != NULL && strcmp(text, "30,10") == 0, "order text: comma separated, zero ids skipped");
        free(text);
        check(shared_order_text((int64_t[]){ 0 }, 1) == NULL && shared_order_text(NULL, 0) == NULL,
              "order text: NULL with nothing to store");

        /* Favorite buttons: placed in a row, dragged into another order,
         * clicked when not dragged. */
        NSWindow *bar_window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 400, shared_look_favorites_bar_h)
                                                           styleMask:NSWindowStyleMaskBorderless
                                                             backing:NSBackingStoreBuffered defer:NO];
        NSView *strip = bar_window.contentView;
        SharedFavoriteButton *alpha = [[SharedFavoriteButton alloc] init_with_title:@"Alpha" tag_id:1];
        SharedFavoriteButton *beta  = [[SharedFavoriteButton alloc] init_with_title:@"Beta" tag_id:2];
        SharedFavoriteButton *gamma = [[SharedFavoriteButton alloc] init_with_title:@"A rather long tag name"
                                                                             tag_id:3];
        for (NSView *v in @[alpha, beta, gamma]) [strip addSubview:v];
        CGFloat row_w = shared_ui_place_favorites(@[alpha, beta, gamma], NO);
        check(alpha.tag_id == 1 && NSWidth(alpha.frame) == shared_look_favorite_btn_min_w &&
              NSWidth(gamma.frame) > shared_look_favorite_btn_min_w,
              "a favorite button is at least the least width, wider for a long title");
        check(NSMinX(alpha.frame) == shared_look_favorites_pad &&
              NSMinX(beta.frame) == NSMaxX(alpha.frame) + shared_look_favorite_gap &&
              NSMinX(gamma.frame) == NSMaxX(beta.frame) + shared_look_favorite_gap &&
              row_w == NSMaxX(gamma.frame) + shared_look_favorites_pad &&
              NSMidY(alpha.frame) == shared_look_favorites_bar_h / 2.0,
              "placed in a row from the left, a gap apart, centred");
        __block NSArray<SharedFavoriteButton *> *got = nil;
        TestClicks *clicks = [[TestClicks alloc] init];
        alpha.reordered = ^(NSArray<SharedFavoriteButton *> *row) { got = row; };
        alpha.target    = clicks;
        alpha.action    = @selector(clicked:);
        NSPoint from = NSMakePoint(NSMidX(alpha.frame), NSMidY(alpha.frame));
        NSPoint past = NSMakePoint(NSMaxX(gamma.frame) - 10.0, from.y);
        mouse(NSEventTypeLeftMouseDragged, bar_window, NSMakePoint(from.x + 20.0, from.y));
        mouse(NSEventTypeLeftMouseDragged, bar_window, past);
        mouse(NSEventTypeLeftMouseUp, bar_window, past);
        [alpha mouseDown:mouse(NSEventTypeLeftMouseDown, bar_window, from)];
        check([got isEqualToArray:@[beta, gamma, alpha]] && clicks.count == 0,
              "dragging the first button past the others reports it last, and is no click");
        check_spin(shared_look_favorite_slide_s * 2);
        check(NSMinX(beta.frame) == shared_look_favorites_pad && NSMinX(alpha.frame) > NSMinX(gamma.frame),
              "and the row slides into the new order");
        got = nil;
        from = NSMakePoint(NSMidX(alpha.frame), NSMidY(alpha.frame));
        mouse(NSEventTypeLeftMouseDragged, bar_window, NSMakePoint(from.x + 1.0, from.y));
        mouse(NSEventTypeLeftMouseUp, bar_window, NSMakePoint(from.x + 1.0, from.y));
        [alpha mouseDown:mouse(NSEventTypeLeftMouseDown, bar_window, from)];
        check(got == nil && clicks.count == 1 && alpha.state == NSControlStateValueOn,
              "a press that hardly moves is a click: the action, the button lit");

        /* The table: Return with a selection sends the double action. */
        SharedTable *table = [[SharedTable alloc] initWithFrame:NSMakeRect(0, 0, 100, 100)];
        check(!table.by_key && shared_ui_activated_rows(table).count == 0,
              "activated rows: none for a double-click on no row");

        /* The split controller reports its sidebar's width once shown. */
        SharedSplitController *split = [[SharedSplitController alloc] init];
        __block NSInteger reported = -1, reported_index = -1;
        split.width_changed = ^(NSInteger index, NSInteger width) {
            reported_index = index;
            reported       = width;
        };
        NSView *side = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 200, 100)];
        NSView *rest = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 400, 100)];
        NSSplitViewItem *side_item = shared_ui_pane_item(side, 160);
        side_item.holdingPriority = NSLayoutPriorityDefaultLow + 1;   /* the rest absorbs resizes */
        [split addSplitViewItem:side_item];
        [split addSplitViewItem:shared_ui_pane_item(rest, 100)];
        split.view.frame = NSMakeRect(0, 0, 600, 100);
        [split.view layoutSubtreeIfNeeded];
        [split.splitView setPosition:233 ofDividerAtIndex:0];
        [split.view layoutSubtreeIfNeeded];
        check(reported == 233 && reported_index == 0, "the split controller reports the sidebar's width");
        split.splitViewItems.firstObject.collapsed = YES;
        reported = -1;
        [split.splitView setPosition:0 ofDividerAtIndex:0];
        check(reported == -1, "and nothing while the sidebar is collapsed");
        NSView *panel = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 200, 100)];
        NSSplitViewItem *panel_item = shared_ui_pane_item(panel, 100);
        panel_item.holdingPriority = NSLayoutPriorityDefaultLow + 1;
        [split addSplitViewItem:panel_item];
        [split.view layoutSubtreeIfNeeded];
        [split.splitView setPosition:420 ofDividerAtIndex:1];
        [split.view layoutSubtreeIfNeeded];
        check(reported_index == 2 && reported == 600 - 420 - split.splitView.dividerThickness,
              "a panel at the right reports its width under its index");

        /* The command table: items made from it, dispatch and validation
         * through a handler table. */
        shared_commands_install(test_commands, sizeof test_commands / sizeof test_commands[0]);
        size_t n = 0;
        check(shared_commands_table(&n) == test_commands && n == 2,
              "shared_commands_table is the installed table");
        check(shared_command_find(@"test-new") == &test_commands[0] &&
              shared_command_find(@"nope") == NULL,
              "shared_command_find: a row by identifier, NULL for an unknown one");
        NSMenuItem *new_item = shared_command_menu_item(@"test-new", @42);
        check([new_item.title isEqualToString:@"New Thing"] &&
              [new_item.keyEquivalent isEqualToString:@"n"] &&
              new_item.keyEquivalentModifierMask == NSEventModifierFlagCommand &&
              new_item.action == @selector(run_app_command:) &&
              [shared_command_ident(new_item) isEqualToString:@"test-new"] &&
              [shared_command_param(new_item) isEqual:@42],
              "a menu item: title, shortcut, the app action, its identifier and parameter");
        NSMenuItem *toggle_item = shared_command_menu_item(@"test-toggle", nil);
        check(toggle_item.target == nil && toggle_item.action == @selector(run_command:),
              "a window-scope item goes up the responder chain");
        NSToolbarItem *bar_item = shared_command_toolbar_item(@"test-new");
        check([bar_item.itemIdentifier isEqualToString:@"test-new"] &&
              [bar_item.toolTip isEqualToString:@"Make a thing"] &&
              bar_item.image == shared_ui_symbol(@"plus", 0.0),
              "a toolbar item: the identifier, the tooltip, the glyph");
        NSButton *button = shared_command_button(@"test-toggle");
        check([shared_command_ident(button) isEqualToString:@"test-toggle"] &&
              [button.toolTip isEqualToString:@"Hide Panel"] && !button.bordered,
              "a button: the identifier, the title as tooltip when there is none");
        check([shared_command_tooltip(@"test-toggle") isEqualToString:@"Hide Panel"],
              "shared_command_tooltip falls back to the title");

        check(shared_command_run(test_handlers, TEST_HANDLER_COUNT, nil, new_item) &&
              runs == 1 && [run_param isEqual:@42],
              "shared_command_run finds the handler and passes the sender");
        check(!shared_command_run(test_handlers, TEST_HANDLER_COUNT, nil, @"not an item") &&
              runs == 1, "and does nothing for anything else");

        BOOL handled = NO;
        check(shared_command_validate(test_handlers, TEST_HANDLER_COUNT, @YES, toggle_item, &handled) &&
              handled && toggle_item.enabled && [toggle_item.title isEqualToString:@"Hide Panel"] &&
              toggle_item.state == NSControlStateValueOff,
              "validate: the table's face while the handler leaves the state alone");
        shared_command_run(test_handlers, TEST_HANDLER_COUNT, nil, toggle_item);
        shared_command_validate(test_handlers, TEST_HANDLER_COUNT, @YES, toggle_item, NULL);
        shared_command_validate(test_handlers, TEST_HANDLER_COUNT, @YES, button, NULL);
        check([toggle_item.title isEqualToString:@"Show Panel"] &&
              toggle_item.state == NSControlStateValueOn &&
              [button.toolTip isEqualToString:@"Show Panel"] &&
              button.image == shared_ui_symbol(@"eye", shared_look_cmd_btn_icon),
              "after a run, the other face on the menu item and the button alike");
        check(!shared_command_validate(test_handlers, TEST_HANDLER_COUNT, @NO, toggle_item, &handled) &&
              handled && !toggle_item.enabled,
              "a handler's NO disables the item");
        SharedCommandState *state = shared_command_state(test_handlers, TEST_HANDLER_COUNT, @YES,
                                                         @"test-toggle");
        check(state.enabled && state.checked && [state.icon isEqualToString:@"eye"],
              "shared_command_state answers without an item");
        check(shared_command_state(test_handlers, TEST_HANDLER_COUNT, @YES, @"nope") == nil,
              "and nil for a command the table lacks");
        NSMenuItem *titled = shared_command_menu_item(@"test-toggle", @1);
        titled.title = @"A Tag";
        shared_command_validate(test_handlers, TEST_HANDLER_COUNT, @YES, titled, NULL);
        check([titled.title isEqualToString:@"A Tag"], "an item with a parameter keeps its title");
        check(shared_command_validate(test_handlers, TEST_HANDLER_COUNT, @YES,
                                      shared_command_menu_item(@"test-new", nil), &handled) &&
              handled, "a command without validate is enabled");
    }
    return check_result();
}
