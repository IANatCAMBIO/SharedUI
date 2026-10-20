/*
 * tag_popup.m — see shared_tag_popup.h.
 */
#import "shared_tag_popup.h"

#include "shared_look.h"

/*
 * SharedTagPanel — the list's window: borderless, and never key, so the
 * owner keeps the keyboard while it shows.
 */
@interface SharedTagPanel : NSPanel
@end

@implementation SharedTagPanel

/*
 * canBecomeKeyWindow — the owner keeps the keys.
 *
 * Output: NO.
 */
- (BOOL)
canBecomeKeyWindow
{
    return NO;
}

@end

@interface SharedTagPopup ()
@property (nonatomic, strong) SharedTagPanel          *panel;
@property (nonatomic, copy)   NSArray<NSString *>    *shown;
@property (nonatomic, strong) NSArray<NSButton *>    *rows;
@property (nonatomic, assign) NSInteger               selected;
@end

@implementation SharedTagPopup

/*
 * style_row: — draw a row selected (accent background, white text) or not.
 *
 * Inputs:
 *   row      — the row's button
 *   selected — YES for the selected row
 */
static void
style_row(NSButton *row, BOOL selected)
{
    row.layer.backgroundColor = selected ? NSColor.selectedContentBackgroundColor.CGColor
                                         : NSColor.clearColor.CGColor;
    NSDictionary *attrs = @{
        NSForegroundColorAttributeName: selected ? NSColor.selectedMenuItemTextColor
                                                 : NSColor.labelColor,
        NSFontAttributeName: [NSFont systemFontOfSize:shared_look_ui_font],
    };
    row.attributedTitle = [[NSAttributedString alloc] initWithString:row.title attributes:attrs];
}

/*
 * row_clicked: — a row was clicked: it is chosen.
 *
 * Inputs:
 *   sender — the row's button (its tag is its index)
 */
- (void)
row_clicked:(NSButton *)sender
{
    NSString *name = (NSUInteger)sender.tag < self.shown.count ? self.shown[(NSUInteger)sender.tag] : nil;
    if (name && self.chosen_handler) self.chosen_handler(name);
}

/*
 * show_names:under:of: — see shared_tag_popup.h.
 */
- (void)
show_names:(NSArray<NSString *> *)names under:(NSRect)rect of:(NSView *)view
{
    if (names.count == 0 || view.window == nil) {
        [self hide];
        return;
    }
    if (self.panel == nil) {
        self.panel = [[SharedTagPanel alloc] initWithContentRect:NSZeroRect
                                                      styleMask:NSWindowStyleMaskBorderless |
                                                                NSWindowStyleMaskNonactivatingPanel
                                                        backing:NSBackingStoreBuffered defer:YES];
        self.panel.hasShadow          = YES;
        self.panel.releasedWhenClosed = NO;
        self.panel.opaque             = NO;
        self.panel.backgroundColor    = NSColor.clearColor;
    }
    self.shown    = [names copy];
    self.selected = self.starts_unselected ? -1 : 0;

    NSMutableArray<NSButton *> *rows = [NSMutableArray array];
    CGFloat w = shared_look_tag_popup_min_w;
    for (NSUInteger i = 0; i < names.count; i++) {
        NSButton *row = [NSButton buttonWithTitle:[@"#" stringByAppendingString:names[i]]
                                           target:self action:@selector(row_clicked:)];
        row.bordered  = NO;
        row.alignment = NSTextAlignmentLeft;
        row.tag       = (NSInteger)i;
        row.wantsLayer = YES;
        row.refusesFirstResponder = YES;
        style_row(row, (NSInteger)i == self.selected);
        w = MAX(w, row.fittingSize.width + 2 * shared_look_tag_popup_pad);
        [rows addObject:row];
    }
    self.rows = rows;

    CGFloat h  = names.count * shared_look_tag_popup_row_h;
    NSView *cv = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, w, h)];
    cv.wantsLayer                = YES;
    cv.layer.cornerRadius        = shared_look_popup_radius;
    cv.layer.masksToBounds       = YES;
    cv.layer.backgroundColor     = NSColor.windowBackgroundColor.CGColor;
    for (NSUInteger i = 0; i < rows.count; i++) {
        rows[i].frame = NSMakeRect(0, h - (i + 1) * shared_look_tag_popup_row_h, w, shared_look_tag_popup_row_h);
        [cv addSubview:rows[i]];
    }
    self.panel.contentView = cv;

    NSRect in_window = [view convertRect:rect toView:nil];
    NSRect on_screen = [view.window convertRectToScreen:in_window];
    [self.panel setFrame:NSMakeRect(NSMinX(on_screen), NSMinY(on_screen) - h - 2, w, h) display:YES];
    if (self.panel.parentWindow != view.window) {
        [self.panel.parentWindow removeChildWindow:self.panel];
        [view.window addChildWindow:self.panel ordered:NSWindowAbove];
    }
    [self.panel orderFront:nil];
    [self.panel invalidateShadow];
}

/*
 * move_selection: — see shared_tag_popup.h.
 */
- (void)
move_selection:(NSInteger)delta
{
    if (self.rows.count == 0) return;
    if (self.selected >= 0) style_row(self.rows[(NSUInteger)self.selected], NO);
    self.selected = self.selected < 0 ? 0
                  : MAX(0, MIN((NSInteger)self.rows.count - 1, self.selected + delta));
    style_row(self.rows[(NSUInteger)self.selected], YES);
}

/*
 * selected_name — see shared_tag_popup.h.
 */
- (NSString *)
selected_name
{
    return [self is_visible] && self.selected >= 0 && (NSUInteger)self.selected < self.shown.count
         ? self.shown[(NSUInteger)self.selected] : nil;
}

/*
 * names — see shared_tag_popup.h.
 */
- (NSArray<NSString *> *)
names
{
    return [self is_visible] ? self.shown : @[];
}

/*
 * is_visible — see shared_tag_popup.h.
 */
- (BOOL)
is_visible
{
    return self.panel.visible;
}

/*
 * hide — see shared_tag_popup.h.
 */
- (void)
hide
{
    [self.panel.parentWindow removeChildWindow:self.panel];
    [self.panel orderOut:nil];
    self.rows  = @[];
    self.shown = @[];
}

@end
