/*
 * shared_ui_test.m — the helpers that need no window: colours, glyphs,
 * image views, tag labels, formatting, the picker kinds, the table's
 * activation rule and the split controller's width report.  The apps'
 * own UI probes exercise the panels and tables on screen.
 */

#import "shared_ui.h"
#import "shared_tool_panel.h"

#include "check.h"

#include <string.h>

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

        /* The table: Return with a selection sends the double action. */
        SharedTable *table = [[SharedTable alloc] initWithFrame:NSMakeRect(0, 0, 100, 100)];
        check(!table.by_key && shared_ui_activated_rows(table).count == 0,
              "activated rows: none for a double-click on no row");

        /* The split controller reports its sidebar's width once shown. */
        SharedSplitController *split = [[SharedSplitController alloc] init];
        __block NSInteger reported = -1;
        split.width_changed = ^(NSInteger width) { reported = width; };
        NSView *side = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 200, 100)];
        NSView *rest = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 400, 100)];
        [split addSplitViewItem:shared_ui_pane_item(side, 160)];
        [split addSplitViewItem:shared_ui_pane_item(rest, 100)];
        split.view.frame = NSMakeRect(0, 0, 600, 100);
        [split.view layoutSubtreeIfNeeded];
        [split.splitView setPosition:233 ofDividerAtIndex:0];
        [split.view layoutSubtreeIfNeeded];
        check(reported == 233, "the split controller reports the sidebar's width");
        split.splitViewItems.firstObject.collapsed = YES;
        reported = -1;
        [split.splitView setPosition:0 ofDividerAtIndex:0];
        check(reported == -1, "and nothing while the sidebar is collapsed");
    }
    return check_result();
}
