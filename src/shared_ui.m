/*
 * shared_ui.m — see shared_ui.h.  Most of these are the Files app's
 * util.m helpers, as Notes and Tasks carried them under their own
 * prefixes before they were made one.
 */

#import "shared_ui.h"
#import "shared_tool_panel.h"

/* The app icon is rendered at this many pixels per point: sharp on a Retina
 * display, and still small on a 1x one. */
static const CGFloat icon_scale = 2.0;

/* ── The app ────────────────────────────────────────────────────────────── */

/*
 * shared_ui_app_name — the bundle's name, else the process's.
 * Inputs/output are documented in shared_ui.h.
 */
NSString *
shared_ui_app_name(void)
{
    NSString *name = NSBundle.mainBundle.infoDictionary[@"CFBundleName"];
    return name.length > 0 ? name : NSProcessInfo.processInfo.processName;
}

/* ── Appearance ─────────────────────────────────────────────────────────── */

/*
 * shared_ui_is_dark — dark appearance test.
 * Inputs/output are documented in shared_ui.h.
 */
BOOL
shared_ui_is_dark(NSView *view)
{
    NSAppearanceName match = [view.effectiveAppearance
        bestMatchFromAppearancesWithNames:@[NSAppearanceNameAqua, NSAppearanceNameDarkAqua]];
    return [match isEqualToString:NSAppearanceNameDarkAqua];
}

/*
 * fixed_color — one appearance's colour as an sRGB NSColor.
 *
 * Inputs:
 *   c — the colour
 *
 * Output: the colour.
 */
static NSColor *
fixed_color(shared_rgba_t c)
{
    return [NSColor colorWithSRGBRed:c.r green:c.g blue:c.b alpha:c.a];
}

/*
 * shared_ui_color — appearance-following NSColor for a look colour, one
 * per value.
 * Inputs/output are documented in shared_ui.h.
 */
NSColor *
shared_ui_color(shared_color_t color)
{
    static NSMutableDictionary<NSString *, NSColor *> *cache;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ cache = [NSMutableDictionary dictionary]; });

    NSString *key = [NSString stringWithFormat:@"%g,%g,%g,%g/%g,%g,%g,%g",
                     color.light.r, color.light.g, color.light.b, color.light.a,
                     color.dark.r, color.dark.g, color.dark.b, color.dark.a];
    NSColor *known = cache[key];
    if (known) return known;

    NSColor *light = fixed_color(color.light);
    NSColor *dark  = fixed_color(color.dark);
    NSColor *made  = [NSColor colorWithName:nil dynamicProvider:^NSColor *(NSAppearance *appearance) {
        NSAppearanceName match = [appearance
            bestMatchFromAppearancesWithNames:@[NSAppearanceNameAqua, NSAppearanceNameDarkAqua]];
        return [match isEqualToString:NSAppearanceNameDarkAqua] ? dark : light;
    }];
    cache[key] = made;
    return made;
}

/* ── Images ─────────────────────────────────────────────────────────────── */

/*
 * cached_image — the image kept under a name and size, made on first use.
 * Glyphs are asked for on every toolbar validation, so each is built once.
 * Bounded by construction: a few dozen names, a handful of sizes.
 *
 * Inputs:
 *   name — the image's name (a symbol name, or the app icon's file name)
 *   size — its size in points
 *   make — builds the image when it is not cached yet; may return nil,
 *          which is not cached
 *
 * Output: the shared image, or nil when `make` could not build it.
 */
static NSImage *
cached_image(NSString *name, CGFloat size, NSImage *(^make)(void))
{
    static NSMutableDictionary<NSString *, NSImage *> *cache;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ cache = [NSMutableDictionary dictionary]; });

    NSString *key   = [NSString stringWithFormat:@"%@@%g", name, size];
    NSImage  *image = cache[key];
    if (!image) {
        image = make();
        if (image) cache[key] = image;
    }
    return image;
}

/*
 * shared_ui_symbol — SF Symbol template image, cached.
 * Inputs/output are documented in shared_ui.h.
 */
NSImage *
shared_ui_symbol(NSString *name, CGFloat points)
{
    return cached_image(name, points, ^NSImage *{
        NSImage *image = [NSImage imageWithSystemSymbolName:name accessibilityDescription:nil];
        if (image && points > 0.0) {
            image = [image imageWithSymbolConfiguration:
                        [NSImageSymbolConfiguration configurationWithPointSize:points
                                                                        weight:NSFontWeightRegular]];
        }
        return image;
    });
}

/*
 * scaled_bitmap — a copy of an image holding ONE bitmap of size x size
 * points at icon_scale, so the full-size source can be let go.
 *
 * Inputs:
 *   source — the image as loaded from the bundle
 *   size   — edge length in points
 *
 * Output: new NSImage, or nil if the bitmap cannot be created.
 */
static NSImage *
scaled_bitmap(NSImage *source, CGFloat size)
{
    NSInteger pixels = (NSInteger)ceil(size * icon_scale);
    NSBitmapImageRep *rep =
        [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL
                                                pixelsWide:pixels
                                                pixelsHigh:pixels
                                             bitsPerSample:8
                                           samplesPerPixel:4
                                                  hasAlpha:YES
                                                  isPlanar:NO
                                            colorSpaceName:NSCalibratedRGBColorSpace
                                               bytesPerRow:0
                                              bitsPerPixel:0];
    if (!rep) return nil;
    rep.size = NSMakeSize(size, size);

    [NSGraphicsContext saveGraphicsState];
    NSGraphicsContext *ctx = [NSGraphicsContext graphicsContextWithBitmapImageRep:rep];
    ctx.imageInterpolation = NSImageInterpolationHigh;
    NSGraphicsContext.currentContext = ctx;
    [source drawInRect:NSMakeRect(0, 0, size, size)
              fromRect:NSZeroRect
             operation:NSCompositingOperationCopy
              fraction:1.0];
    [NSGraphicsContext restoreGraphicsState];

    NSImage *icon = [[NSImage alloc] initWithSize:NSMakeSize(size, size)];
    [icon addRepresentation:rep];
    return icon;
}

/*
 * shared_ui_app_icon — the app's artwork, scaled once and cached.
 * Inputs/output are documented in shared_ui.h.
 */
NSImage *
shared_ui_app_icon(NSString *resource, CGFloat size)
{
    return cached_image(resource, size, ^NSImage *{
        /* Loaded from its file rather than with imageNamed:, which would
         * keep the full-size image in AppKit's named-image cache for good. */
        NSString *path   = [NSBundle.mainBundle pathForResource:resource ofType:@"png"];
        NSImage  *source = path ? [[NSImage alloc] initWithContentsOfFile:path] : nil;
        return source ? scaled_bitmap(source, size) : nil;
    });
}

/*
 * shared_ui_image_view — image view created at its final size.
 * Inputs/output are documented in shared_ui.h.
 */
NSImageView *
shared_ui_image_view(NSImage *image, CGFloat width, CGFloat height)
{
    NSImageView *view = [[NSImageView alloc] initWithFrame:NSMakeRect(0, 0, width, height)];
    view.imageScaling = NSImageScaleProportionallyDown;
    view.translatesAutoresizingMaskIntoConstraints = NO;
    [view.widthAnchor constraintEqualToConstant:width].active   = YES;
    [view.heightAnchor constraintEqualToConstant:height].active = YES;
    view.image = image;              /* last: the view already has its frame */
    return view;
}

/* ── Dialogs ────────────────────────────────────────────────────────────── */

/*
 * shared_ui_notice — an OK tool panel.
 * Inputs are documented in shared_ui.h.
 */
void
shared_ui_notice(NSWindow *parent, NSString *title, NSString *message, void (^done)(void))
{
    [SharedToolPanel show_message:title message:message symbol:@"info.circle.fill"
                          buttons:@[@"OK"] destructive:-1 over:parent
                          handler:^(NSInteger index) { (void)index; if (done) done(); }];
}

/*
 * shared_ui_confirm — a Cancel (default) / action tool panel.
 * Inputs are documented in shared_ui.h.
 */
void
shared_ui_confirm(NSWindow *parent, NSString *title, NSString *message, NSString *action,
                  BOOL destructive, void (^done)(BOOL confirmed))
{
    if (message == nil && destructive) message = @"This cannot be undone.";
    [SharedToolPanel show_message:title message:message
                           symbol:destructive ? @"exclamationmark.triangle.fill"
                                              : @"questionmark.circle.fill"
                          buttons:@[@"Cancel", action]   /* [0] = default (Return) */
                      destructive:destructive ? 1 : -1
                             over:parent
                          handler:^(NSInteger index) { done(index == 1); }];
}

/*
 * shared_ui_pick_path — open or save panel.
 * Inputs are documented in shared_ui.h.
 */
void
shared_ui_pick_path(SharedPickKind kind, NSString *message, NSString *prompt,
                    NSArray<UTType *> *types, NSString *start_dir, void (^done)(NSString *path))
{
    NSSavePanel *panel;
    if (kind == SharedPickSaveFile) {
        panel = [NSSavePanel savePanel];
    } else {
        NSOpenPanel *open            = [NSOpenPanel openPanel];
        open.canChooseFiles          = kind == SharedPickOpenFile;
        open.canChooseDirectories    = kind == SharedPickFolder;
        open.canCreateDirectories    = kind == SharedPickFolder;
        open.allowsMultipleSelection = NO;
        panel = open;
    }
    panel.message = message;
    panel.prompt  = prompt;
    if (types) panel.allowedContentTypes = types;
    if (start_dir) panel.directoryURL = [NSURL fileURLWithPath:start_dir isDirectory:YES];

    done([panel runModal] == NSModalResponseOK ? panel.URL.path : nil);
}

/* ── Windows ────────────────────────────────────────────────────────────── */

/*
 * shared_ui_place_lower_right — a window to a screen's lower-right corner.
 * Inputs are documented in shared_ui.h.
 */
void
shared_ui_place_lower_right(NSWindow *window, NSScreen *screen)
{
    if (screen == nil) return;

    NSRect area = screen.visibleFrame;
    NSSize size = window.frame.size;
    [window setFrameOrigin:NSMakePoint(
        MAX(NSMaxX(area) - size.width - shared_look_screen_margin, NSMinX(area)),
        MIN(NSMinY(area) + shared_look_screen_margin, NSMaxY(area) - size.height))];
}

/*
 * shared_ui_pane_item — a split-view item around a view.
 * Inputs/output are documented in shared_ui.h.
 */
NSSplitViewItem *
shared_ui_pane_item(NSView *view, CGFloat min_width)
{
    NSViewController *controller = [[NSViewController alloc] init];
    controller.view = view;
    NSSplitViewItem *item = [NSSplitViewItem splitViewItemWithViewController:controller];
    item.minimumThickness = min_width;
    return item;
}

@implementation SharedSplitController

/*
 * splitViewDidResizeSubviews: — the divider moved: report the sidebar's
 * width, unless the sidebar is collapsed (its width is then no width) or
 * narrower than its least width (a layout pass before the window has its
 * size).
 *
 * Inputs:
 *   note — the notification
 */
- (void)
splitViewDidResizeSubviews:(NSNotification *)note
{
    [super splitViewDidResizeSubviews:note];
    NSSplitViewItem *sidebar = self.splitViewItems.firstObject;
    if (sidebar.collapsed || !self.width_changed) return;
    NSInteger width = (NSInteger)round(NSWidth(sidebar.viewController.view.frame));
    if (width >= sidebar.minimumThickness) self.width_changed(width);
}

@end

/* ── Controls ───────────────────────────────────────────────────────────── */

/*
 * SharedStatusLabel — a status bar's label (shared_ui_status_label): its
 * own class only so that shared_ui_use_ui_font can tell it apart.
 */
@interface SharedStatusLabel : NSTextField
@end

@implementation SharedStatusLabel
@end

/*
 * shared_ui_status_label — a status bar label, centred on its capitals.
 * Inputs/output are documented in shared_ui.h.
 */
NSTextField *
shared_ui_status_label(NSView *bar, NSLayoutYAxisAnchor *middle, NSTextAlignment alignment)
{
    SharedStatusLabel *label = [SharedStatusLabel labelWithString:@""];
    label.font          = [NSFont systemFontOfSize:shared_look_status_font];
    label.textColor     = NSColor.secondaryLabelColor;
    label.alignment     = alignment;
    label.lineBreakMode = NSLineBreakByTruncatingMiddle;
    label.translatesAutoresizingMaskIntoConstraints = NO;
    [label setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow
                                    forOrientation:NSLayoutConstraintOrientationHorizontal];
    [bar addSubview:label];
    /* y grows downward for anchors: the baseline sits half a cap height
     * below the middle, so the capitals straddle it. */
    [label.firstBaselineAnchor constraintEqualToAnchor:middle
                                              constant:round(label.font.capHeight / 2.0)].active = YES;
    return label;
}

/*
 * shared_ui_use_ui_font — the apps' text size under a view.
 * Inputs are documented in shared_ui.h.
 */
void
shared_ui_use_ui_font(NSView *root)
{
    if ([root isKindOfClass:NSTableView.class]) return;         /* cells set their own fonts */
    if ([root isKindOfClass:SharedStatusLabel.class]) return;   /* so do the status bars     */
    NSFontManager *fm = NSFontManager.sharedFontManager;
    if ([root isKindOfClass:NSControl.class]) {
        NSControl *c = (NSControl *)root;
        if (c.font) c.font = [fm convertFont:c.font toSize:shared_look_ui_font];
        BOOL labelled = [c isKindOfClass:NSButton.class] && ((NSButton *)c).title.length > 0;
        BOOL editable = [c isKindOfClass:NSTextField.class] && ((NSTextField *)c).editable;
        if (labelled || editable || [c isKindOfClass:NSPopUpButton.class] || [c isKindOfClass:NSStepper.class])
            c.controlSize = NSControlSizeSmall;
    } else if ([root isKindOfClass:NSTextView.class]) {
        NSTextView *t = (NSTextView *)root;
        if (t.font) t.font = [fm convertFont:t.font toSize:shared_look_ui_font];
    }
    for (NSView *v in root.subviews) shared_ui_use_ui_font(v);
}

/*
 * vetted_selection — the selection a click on one row would make, after
 * the delegate's say.
 *
 * Inputs:
 *   table — the table
 *   row   — the clicked row, >= 0
 *
 * Output: the rows to select; empty when the delegate refuses.
 */
static NSIndexSet *
vetted_selection(NSTableView *table, NSInteger row)
{
    NSIndexSet *rows = [NSIndexSet indexSetWithIndex:(NSUInteger)row];
    id          d    = table.delegate;
    if ([d respondsToSelector:@selector(selectionShouldChangeInTableView:)] &&
        ![d selectionShouldChangeInTableView:table]) return [NSIndexSet indexSet];
    if ([d respondsToSelector:@selector(tableView:selectionIndexesForProposedSelection:)])
        return [d tableView:table selectionIndexesForProposedSelection:rows];
    if ([d respondsToSelector:@selector(tableView:shouldSelectRow:)] &&
        ![d tableView:table shouldSelectRow:row]) return [NSIndexSet indexSet];
    return rows;
}

/*
 * shared_ui_select_on_mouse_down — select the clicked row before super
 * tracks.
 * Inputs are documented in shared_ui.h.
 */
void
shared_ui_select_on_mouse_down(NSTableView *table, NSEvent *event)
{
    NSEventModifierFlags mods = event.modifierFlags & (NSEventModifierFlagCommand |
                                                       NSEventModifierFlagShift |
                                                       NSEventModifierFlagControl);
    NSInteger row = [table rowAtPoint:[table convertPoint:event.locationInWindow fromView:nil]];
    if (mods != 0 || event.clickCount != 1 || row < 0 || [table isRowSelected:row]) return;
    NSView *hit = [table hitTest:[table.superview convertPoint:event.locationInWindow fromView:nil]];
    if ([hit isKindOfClass:NSButton.class]) return;
    NSIndexSet *rows = vetted_selection(table, row);
    if (rows.count > 0) [table selectRowIndexes:rows byExtendingSelection:NO];
}

/*
 * activation_is_key — is this key event Return or keypad Enter, with no
 * Command, Option or Control?
 *
 * Inputs:
 *   event — a key-down event
 *
 * Output: YES for an activating key.
 */
static BOOL
activation_is_key(NSEvent *event)
{
    NSEventModifierFlags mods = event.modifierFlags &
        (NSEventModifierFlagCommand | NSEventModifierFlagOption | NSEventModifierFlagControl);
    NSString *chars = event.charactersIgnoringModifiers;
    if (mods != 0 || chars.length != 1) return NO;
    unichar c = [chars characterAtIndex:0];
    return c == '\r' || c == NSEnterCharacter;
}

@implementation SharedTable

/*
 * mouseDown: — a plain click selects its row at once
 * (shared_ui_select_on_mouse_down); NSTableView then tracks the click as
 * usual (drags, double-clicks).
 *
 * Inputs:
 *   event — the mouse event
 */
- (void)
mouseDown:(NSEvent *)event
{
    shared_ui_select_on_mouse_down(self, event);
    [super mouseDown:event];
}

/*
 * keyDown: — Return or Enter with a selection sends the doubleAction;
 * every other key goes to NSTableView.
 *
 * Inputs:
 *   event — the key event
 */
- (void)
keyDown:(NSEvent *)event
{
    if (activation_is_key(event) && self.selectedRowIndexes.count > 0 && self.doubleAction) {
        _by_key = YES;
        [self sendAction:self.doubleAction to:self.target];
        _by_key = NO;
        return;
    }
    [super keyDown:event];
}

@end

/*
 * shared_ui_activated_rows — the rows a doubleAction applies to.
 * Inputs/output are documented in shared_ui.h.
 */
NSIndexSet *
shared_ui_activated_rows(SharedTable *table)
{
    if (table.by_key) return table.selectedRowIndexes;
    if (table.clickedRow >= 0) return [NSIndexSet indexSetWithIndex:(NSUInteger)table.clickedRow];
    return [NSIndexSet indexSet];         /* a double-click on empty space */
}

@implementation SharedFlippedView

/*
 * isFlipped — y grows downward.
 *
 * Output: YES.
 */
- (BOOL)
isFlipped
{
    return YES;
}

@end

/*
 * shared_ui_spacer — a stack view's room-taker.
 * Output is documented in shared_ui.h.
 */
NSView *
shared_ui_spacer(void)
{
    NSView *spacer = [[NSView alloc] initWithFrame:NSZeroRect];
    [spacer setContentHuggingPriority:NSLayoutPriorityDefaultLow - 1
                       forOrientation:NSLayoutConstraintOrientationHorizontal];
    [spacer setContentHuggingPriority:NSLayoutPriorityDefaultLow - 1
                       forOrientation:NSLayoutConstraintOrientationVertical];
    return spacer;
}

/*
 * shared_ui_pin_edges — four edges on another view's.
 * Inputs are documented in shared_ui.h.
 */
void
shared_ui_pin_edges(NSView *view, NSView *to)
{
    [NSLayoutConstraint activateConstraints:@[
        [view.topAnchor      constraintEqualToAnchor:to.topAnchor],
        [view.bottomAnchor   constraintEqualToAnchor:to.bottomAnchor],
        [view.leadingAnchor  constraintEqualToAnchor:to.leadingAnchor],
        [view.trailingAnchor constraintEqualToAnchor:to.trailingAnchor],
    ]];
}

/*
 * shared_ui_heading — a bold heading.
 * Inputs/output are documented in shared_ui.h.
 */
NSTextField *
shared_ui_heading(NSString *text)
{
    NSTextField *label = [NSTextField labelWithString:text];
    label.font = [NSFont boldSystemFontOfSize:shared_look_ui_font];
    return label;
}

/*
 * shared_ui_note — wrapped secondary text.
 * Inputs/output are documented in shared_ui.h.
 */
NSTextField *
shared_ui_note(NSString *text, CGFloat width)
{
    NSTextField *label = [NSTextField wrappingLabelWithString:text ?: @""];
    label.font                    = [NSFont systemFontOfSize:shared_look_ui_font];
    label.textColor               = NSColor.secondaryLabelColor;
    label.selectable              = NO;
    label.preferredMaxLayoutWidth = width;
    return label;
}

/*
 * shared_ui_copy_link — a "copy" link.
 * Inputs/output are documented in shared_ui.h.
 */
NSButton *
shared_ui_copy_link(id target, SEL action)
{
    NSButton *button = [NSButton buttonWithTitle:@"" target:target action:action];
    button.bordered        = NO;
    button.attributedTitle = [[NSAttributedString alloc] initWithString:@"copy" attributes:@{
        NSForegroundColorAttributeName: shared_ui_color(shared_look_link),
        NSFontAttributeName:            [NSFont systemFontOfSize:shared_look_ui_font],
    }];
    return button;
}

/*
 * shared_ui_select_radio — one radio of a group on.
 * Inputs are documented in shared_ui.h.
 */
void
shared_ui_select_radio(NSArray<NSButton *> *group, NSButton *chosen)
{
    for (NSButton *b in group) b.state = b == chosen ? NSControlStateValueOn : NSControlStateValueOff;
}

/*
 * SharedEmojiField — the emoji slot behind shared_ui_emoji_field: a text
 * field that keeps one character and opens the emoji picker when clicked.
 *
 * In its compact form (the one Ctrl+Cmd+Space shows) the picker closes
 * itself once an emoji is chosen; the slot then ends its edit, so the
 * expanded Character Viewer window, which has no API to close it, types
 * nowhere until the slot is clicked again.
 */
@interface SharedEmojiField : NSTextField
@end

@implementation SharedEmojiField

/*
 * mouseDown: — a click starts editing as usual, selects what is there so
 * that the chosen emoji replaces it, and opens the system's emoji picker
 * over the slot.
 *
 * Inputs:
 *   event — the mouse-down
 */
- (void)
mouseDown:(NSEvent *)event
{
    [super mouseDown:event];
    [self.currentEditor selectAll:nil];
    [NSApp orderFrontCharacterPalette:nil];
}

/*
 * textDidChange: — keep only the last character entered, then give up the
 * keyboard.
 *
 * "Character" is a composed sequence: an emoji with a skin tone or a flag
 * is several code points and must stay whole.  Editing ends once there is
 * a character because a field that is still being edited does not see the
 * next click (its editor does), and so could not open the picker again.
 * That happens on the next run-loop pass: ending an edit from inside the
 * editor's own change notification re-enters it.
 *
 * Inputs:
 *   note — NSTextDidChangeNotification; its object is the field editor
 */
- (void)
textDidChange:(NSNotification *)note
{
    NSText   *editor = note.object;
    NSString *text   = editor.string;

    if (text.length > 0) {
        NSRange last = [text rangeOfComposedCharacterSequenceAtIndex:text.length - 1];
        if (last.location > 0) editor.string = [text substringWithRange:last];

        __weak SharedEmojiField *ws = self;
        dispatch_async(dispatch_get_main_queue(), ^{
            SharedEmojiField *s = ws;
            if (s.currentEditor) [s.window makeFirstResponder:nil];
        });
    }
    [super textDidChange:note];
}

@end

/*
 * shared_ui_emoji_field — the emoji slot, filled in.
 * Inputs/output are documented in shared_ui.h.
 */
NSTextField *
shared_ui_emoji_field(NSString *emoji)
{
    SharedEmojiField *field = [[SharedEmojiField alloc] initWithFrame:NSZeroRect];
    field.stringValue       = emoji ?: @"";
    field.placeholderString = @"…";
    field.toolTip           = @"Optional emoji — click to pick";
    field.alignment         = NSTextAlignmentCenter;
    field.font              = [NSFont systemFontOfSize:shared_look_ui_font + 3];
    field.translatesAutoresizingMaskIntoConstraints = NO;
    [field.widthAnchor constraintEqualToConstant:shared_look_tool_emoji_w].active = YES;
    return field;
}

/* ── Tags ───────────────────────────────────────────────────────────────── */

/*
 * shared_ui_tag_label — a tag's emoji and name.
 * Inputs/output are documented in shared_ui.h.
 */
NSString *
shared_ui_tag_label(NSString *emoji, NSString *name)
{
    return emoji.length > 0 ? [NSString stringWithFormat:@"%@  %@", emoji, name] : name;
}

/*
 * shared_ui_label_name — the name after a label's "emoji  " prefix.
 * Inputs/output are documented in shared_ui.h.
 */
NSString *
shared_ui_label_name(NSString *label)
{
    NSRange gap = [label rangeOfString:@"  "];
    return gap.location == NSNotFound ? label : [label substringFromIndex:NSMaxRange(gap)];
}

/* ── The About panel ────────────────────────────────────────────────────── */

/* The credits' links: the apps are camb.io's, under the BSD license. */
static NSString * const about_site_url    = @"https://camb.io";
static NSString * const about_license_url = @"https://opensource.org/license/bsd-3-clause";

/*
 * shared_ui_show_about — the About panel with the credits, icon and build
 * date.
 * Inputs are documented in shared_ui.h.
 */
void
shared_ui_show_about(NSString *lead, NSImage *icon, NSString *stamp_key)
{
    NSMutableParagraphStyle *centred = [[NSMutableParagraphStyle alloc] init];
    centred.alignment = NSTextAlignmentCenter;
    NSDictionary *plain = @{
        NSFontAttributeName:            [NSFont systemFontOfSize:shared_look_ui_font],
        NSForegroundColorAttributeName: NSColor.labelColor,
        NSParagraphStyleAttributeName:  centred,
    };
    NSArray<NSArray<NSString *> *> *links = @[
        @[@"camb.io",     about_site_url],
        @[@"BSD License", about_license_url],
    ];
    NSMutableAttributedString *credits = [[NSMutableAttributedString alloc]
        initWithString:[lead stringByAppendingString:@"\n\n"] attributes:plain];
    for (NSArray<NSString *> *link in links) {
        if (link != links.firstObject) {
            [credits appendAttributedString:
                [[NSAttributedString alloc] initWithString:@"  ·  " attributes:plain]];
        }
        NSMutableDictionary *attrs = [plain mutableCopy];
        attrs[NSLinkAttributeName] = [NSURL URLWithString:link[1]];
        [credits appendAttributedString:
            [[NSAttributedString alloc] initWithString:link[0] attributes:attrs]];
    }

    NSMutableDictionary *options = [NSMutableDictionary dictionary];
    options[NSAboutPanelOptionCredits] = credits;
    if (icon) options[NSAboutPanelOptionApplicationIcon] = icon;
    NSString *stamp = NSBundle.mainBundle.infoDictionary[stamp_key];
    NSDate   *built = stamp ? [[[NSISO8601DateFormatter alloc] init] dateFromString:stamp] : nil;
    if (built) {
        options[NSAboutPanelOptionApplicationVersion] =
            [@"built " stringByAppendingString:
                [NSDateFormatter localizedStringFromDate:built
                                               dateStyle:NSDateFormatterMediumStyle
                                               timeStyle:NSDateFormatterShortStyle]];
    }
    [NSApp orderFrontStandardAboutPanelWithOptions:options];
}

/* ── Formatting ─────────────────────────────────────────────────────────── */

/*
 * shared_ui_format_bytes — Finder-style byte count via one shared formatter.
 * Inputs/output are documented in shared_ui.h.
 */
NSString *
shared_ui_format_bytes(int64_t bytes)
{
    static NSByteCountFormatter *fmt;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        fmt = [[NSByteCountFormatter alloc] init];
        fmt.countStyle = NSByteCountFormatterCountStyleFile;
    });
    return [fmt stringFromByteCount:bytes];
}

NSString *const shared_ui_date_list = @"MMM d, yyyy HH:mm";
NSString *const shared_ui_date_day  = @"MMM d, yyyy";
NSString *const shared_ui_date_iso  = @"yyyy-MM-dd";

/*
 * shared_ui_format_date — a date via the shared formatter for its pattern.
 * Inputs/output are documented in shared_ui.h.
 */
NSString *
shared_ui_format_date(int64_t unix_time, NSString *format)
{
    static NSMutableDictionary<NSString *, NSDateFormatter *> *formatters;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ formatters = [NSMutableDictionary dictionary]; });
    NSDateFormatter *fmt;
    @synchronized (formatters) {
        fmt = formatters[format];
        if (fmt == nil) {
            fmt = [[NSDateFormatter alloc] init];
            fmt.dateFormat = format;
            formatters[format] = fmt;
        }
    }
    return [fmt stringFromDate:[NSDate dateWithTimeIntervalSince1970:(NSTimeInterval)unix_time]];
}
