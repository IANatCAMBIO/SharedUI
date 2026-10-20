/*
 * shared_tool_panel.m — see shared_tool_panel.h.  Ported from the Files
 * app's tool_panel.m; Escape dismisses the panel (handler index -1)
 * instead of clicking a button, so Escape never answers a destructive
 * choice.
 */

#import "shared_tool_panel.h"
#import "shared_ui.h"

#include "shared_look.h"

/* ── The hero strip ─────────────────────────────────────────────────── */

@interface SharedHero ()
@property (nonatomic, strong, readwrite) NSTextField *title_label;
@property (nonatomic, strong, readwrite) NSTextField *subtitle_label;
@end

/*
 * header_label — one line of text that truncates rather than widen its
 * container (the hero strip, a tool panel's header).
 *
 * Inputs:
 *   font  — its font
 *   color — its colour
 *
 * Output: new, empty label.
 */
static NSTextField *
header_label(NSFont *font, NSColor *color)
{
    NSTextField *label = [NSTextField labelWithString:@""];

    label.font                 = font;
    label.textColor            = color;
    label.lineBreakMode        = NSLineBreakByTruncatingTail;
    label.maximumNumberOfLines = 1;
    [label setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow
                                    forOrientation:NSLayoutConstraintOrientationHorizontal];
    return label;
}

@implementation SharedHero

/*
 * init_with_symbol: — the strip: the symbol, then the title over the
 * subtitle, centred on the strip's height.
 * Inputs/output are documented in shared_tool_panel.h.
 */
- (instancetype)
init_with_symbol:(NSString *)symbol
{
    self = [super initWithFrame:NSZeroRect];
    if (!self) return nil;
    self.translatesAutoresizingMaskIntoConstraints = NO;

    NSImage *sym = symbol ? [NSImage imageWithSystemSymbolName:symbol accessibilityDescription:nil]
                          : nil;
    sym = [sym imageWithSymbolConfiguration:
           [NSImageSymbolConfiguration configurationWithPointSize:shared_look_hero_icon
                                                           weight:NSFontWeightMedium]];
    NSImageView *icon     = shared_ui_image_view(sym, shared_look_hero_icon, shared_look_hero_icon);
    icon.contentTintColor = NSColor.whiteColor;
    icon.hidden           = sym == nil;

    _title_label    = header_label([NSFont boldSystemFontOfSize:shared_look_ui_font], NSColor.whiteColor);
    _subtitle_label = header_label([NSFont systemFontOfSize:shared_look_ui_font],
                                 shared_ui_color(shared_look_hero_sub));
    _subtitle_label.hidden = YES;

    /* A hidden subtitle leaves the stack, so a lone title is centred. */
    NSStackView *text = [NSStackView stackViewWithViews:@[_title_label, _subtitle_label]];
    text.orientation  = NSUserInterfaceLayoutOrientationVertical;
    text.alignment    = NSLayoutAttributeLeading;
    text.spacing      = shared_look_hero_gap;

    NSStackView *row = [NSStackView stackViewWithViews:@[icon, text]];
    row.orientation  = NSUserInterfaceLayoutOrientationHorizontal;
    row.alignment    = NSLayoutAttributeCenterY;
    row.spacing      = shared_look_hero_icon_gap;
    row.translatesAutoresizingMaskIntoConstraints = NO;
    [self addSubview:row];

    [NSLayoutConstraint activateConstraints:@[
        [self.heightAnchor constraintEqualToConstant:shared_look_hero_h],
        [row.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:shared_look_hero_pad],
        [row.trailingAnchor constraintLessThanOrEqualToAnchor:self.trailingAnchor
                                                     constant:-shared_look_hero_pad],
        [row.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
    ]];
    return self;
}

/*
 * set_title:subtitle: — what the strip says.
 * Inputs are documented in shared_tool_panel.h.
 */
- (void)
set_title:(NSString *)title subtitle:(NSString *)subtitle
{
    self.title_label.stringValue    = title ?: @"";
    self.subtitle_label.stringValue = subtitle ?: @"";
    self.subtitle_label.textColor   = shared_ui_color(shared_look_hero_sub);
    self.subtitle_label.hidden      = subtitle.length == 0;
}

/*
 * show_problem: — a highlighted line in the subtitle's place.
 * Inputs are documented in shared_tool_panel.h.
 */
- (void)
show_problem:(NSString *)problem
{
    self.subtitle_label.stringValue = problem ?: @"";
    self.subtitle_label.textColor   = shared_ui_color(shared_look_hero_problem);
    self.subtitle_label.hidden      = problem.length == 0;
}

/*
 * isOpaque — the strip fills its whole frame.
 *
 * Output: YES.
 */
- (BOOL)
isOpaque
{
    return YES;
}

/*
 * drawRect: — fill the strip with the hero blue.
 *
 * Inputs:
 *   dirtyRect — the area to redraw (unused: the whole strip is filled)
 */
- (void)
drawRect:(NSRect)dirtyRect
{
    (void)dirtyRect;
    [shared_ui_color(shared_look_hero) setFill];
    NSRectFill(self.bounds);
}

@end

/* ── The panel ──────────────────────────────────────────────────────── */

/*
 * SharedToolWindow — the panel's window: Escape closes it, which reports a
 * dismissal to its SharedToolPanel.
 */
@interface SharedToolWindow : NSPanel
@end

@implementation SharedToolWindow

/*
 * cancelOperation: — Escape, from the panel or a field in it: close.
 *
 * Inputs:
 *   sender — the responder that sent it (unused)
 */
- (void)
cancelOperation:(id)sender
{
    (void)sender;
    [self close];
}

@end

@interface SharedToolPanel () <NSWindowDelegate>
@property (nonatomic, strong) SharedToolWindow *panel;
@property (nonatomic, strong) NSTextField      *title_label;     /* the header's bold line */
@property (nonatomic, strong) NSTextField      *subtitle_label;  /* hidden while empty     */
@property (nonatomic, copy)   NSString         *subtitle;
@property (nonatomic, copy)   NSString *(^button_handler)(NSInteger index);
@property (nonatomic, copy)   void (^dismissed_handler)(void);
@property (nonatomic, assign) BOOL              chosen;     /* a button answered */
@end

/* Panels on screen: each keeps itself alive until its window closes. */
static NSMutableSet<SharedToolPanel *> *live_panels;

/*
 * message_view — the wrapped, selectable message in a fixed-size view;
 * text taller than shared_look_tool_msg_max_h scrolls.
 *
 * Inputs:
 *   message — the text
 *
 * Output: a view shared_look_tool_msg_w wide.
 */
static NSView *
message_view(NSString *message)
{
    NSTextField *label = [NSTextField wrappingLabelWithString:message];
    label.font         = [NSFont systemFontOfSize:shared_look_ui_font];
    label.selectable   = YES;
    label.alignment    = NSTextAlignmentCenter;
    label.preferredMaxLayoutWidth = shared_look_tool_msg_w;
    CGFloat h = ceil([label.cell cellSizeForBounds:
                      NSMakeRect(0, 0, shared_look_tool_msg_w, CGFLOAT_MAX)].height);
    CGFloat shown_h = MIN(h, shared_look_tool_msg_max_h);

    NSView *box = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, shared_look_tool_msg_w, shown_h)];
    if (h <= shared_look_tool_msg_max_h) {
        label.frame = box.bounds;
        [box addSubview:label];
    } else {
        label.frame = NSMakeRect(0, 0, shared_look_tool_msg_w, h);
        NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:box.bounds];
        scroll.hasVerticalScroller = YES;
        scroll.drawsBackground     = NO;
        scroll.documentView        = label;
        [box addSubview:scroll];
    }
    [NSLayoutConstraint activateConstraints:@[
        [box.widthAnchor  constraintEqualToConstant:shared_look_tool_msg_w],
        [box.heightAnchor constraintEqualToConstant:shown_h],
    ]];
    return box;
}

/*
 * button_w — the width a tool-panel button is given: its title's, padded,
 * never narrower than shared_look_tool_btn_w.
 *
 * Inputs:
 *   button — the button
 *
 * Output: the width in points.
 */
static CGFloat
button_w(NSButton *button)
{
    return MAX(shared_look_tool_btn_w, button.fittingSize.width + shared_look_tool_btn_pad);
}

@implementation SharedToolPanel

/*
 * header_with_symbol:… — the header of a panel: the symbol centred at the
 * top, the bold headline under it and the subtitle under that, all on the
 * window's own background.  Records the two labels in panel so a button's
 * problem can replace the subtitle.
 *
 * Inputs:
 *   symbol   — SF Symbols name; nil or unknown shows none
 *   headline — the bold line
 *   subtitle — the second line; nil or empty for none
 *   panel    — the panel that owns the header
 *
 * Output: the header, a vertical stack with its own width and height.
 */
+ (NSStackView *)
header_with_symbol:(NSString *)symbol
          headline:(NSString *)headline
          subtitle:(NSString *)subtitle
             panel:(SharedToolPanel *)panel
{
    NSImage *sym = symbol ? [NSImage imageWithSystemSymbolName:symbol accessibilityDescription:nil]
                          : nil;
    sym = [sym imageWithSymbolConfiguration:
           [NSImageSymbolConfiguration configurationWithPointSize:shared_look_head_icon
                                                           weight:NSFontWeightRegular]];
    NSImageView *icon     = shared_ui_image_view(sym, shared_look_head_icon, shared_look_head_icon);
    icon.contentTintColor = NSColor.secondaryLabelColor;
    icon.hidden           = sym == nil;

    panel.title_label    = header_label([NSFont boldSystemFontOfSize:shared_look_ui_font],
                                        NSColor.labelColor);
    panel.subtitle_label = header_label([NSFont systemFontOfSize:shared_look_ui_font],
                                        NSColor.secondaryLabelColor);
    panel.title_label.stringValue = headline ?: @"";
    [panel show_subtitle:subtitle problem:NO];

    /* Hidden members leave the stack, so a missing symbol or subtitle leaves no gap. */
    NSStackView *head = [NSStackView stackViewWithViews:@[icon, panel.title_label, panel.subtitle_label]];
    head.orientation  = NSUserInterfaceLayoutOrientationVertical;
    head.alignment    = NSLayoutAttributeCenterX;
    head.spacing      = shared_look_head_gap;
    head.translatesAutoresizingMaskIntoConstraints = NO;
    [head layoutSubtreeIfNeeded];
    return head;
}

/*
 * show_subtitle:problem: — set the header's second line.
 *
 * Inputs:
 *   text    — the line; nil or empty hides it
 *   problem — YES to show it as a problem (in red), NO as the subtitle
 */
- (void)
show_subtitle:(NSString *)text problem:(BOOL)problem
{
    self.subtitle_label.stringValue = text ?: @"";
    self.subtitle_label.textColor   = problem ? NSColor.systemRedColor : NSColor.secondaryLabelColor;
    self.subtitle_label.hidden      = text.length == 0;
}

/*
 * build_with_title:… — the panel behind both public constructors: lay out
 * the header (symbol over title over subtitle, centred), the content and
 * one button per entry of buttons.
 *
 * Inputs:
 *   window_title — title bar text
 *   headline     — bold line under the symbol
 *   subtitle     — second line under the headline; empty = headline only
 *   symbol       — SF Symbols name for the header's symbol; may be nil
 *   content      — the controls, sized by their own fittingSize
 *   buttons      — button labels, at least one: [0] is the default button
 *                  at the far right, the rest follow to its left
 *   destructive  — index of the button with the destructive look; -1 none
 *   handler      — called with the index of the clicked button; returns
 *                  nil to close the panel or a one-line problem to show in
 *                  the subtitle's place (the panel stays open)
 *
 * Output: the panel, not yet shown.
 */
+ (instancetype)
build_with_title:(NSString *)window_title
      headline:(NSString *)headline
        subtitle:(NSString *)subtitle
          symbol:(NSString *)symbol
         content:(NSView *)content
         buttons:(NSArray<NSString *> *)buttons
     destructive:(NSInteger)destructive
         handler:(NSString *(^)(NSInteger index))handler
{
    SharedToolPanel *p = [[SharedToolPanel alloc] init];
    p.subtitle       = subtitle;
    p.button_handler = handler;

    NSMutableArray<NSButton *> *controls = [NSMutableArray array];
    CGFloat bar_w = 2 * shared_look_tool_btn_margin - shared_look_tool_btn_gap;
    for (NSUInteger i = 0; i < buttons.count; i++) {
        NSButton *b = [NSButton buttonWithTitle:buttons[i] target:p
                                         action:@selector(button_clicked:)];
        b.tag                  = (NSInteger)i;
        b.font                 = [NSFont systemFontOfSize:shared_look_ui_font];
        b.hasDestructiveAction = (NSInteger)i == destructive;
        b.translatesAutoresizingMaskIntoConstraints = NO;
        [controls addObject:b];
        bar_w += shared_look_tool_btn_gap + button_w(b);
    }
    /* No button takes Escape: it dismisses the panel (SharedToolWindow). */
    controls.firstObject.keyEquivalent = @"\r";

    [content layoutSubtreeIfNeeded];
    NSSize  cs = content.fittingSize;
    CGFloat w  = MAX(MAX(shared_look_tool_min_w, cs.width + 2 * shared_look_tool_pad), bar_w);
    NSStackView *head = [self header_with_symbol:symbol headline:headline subtitle:subtitle panel:p];
    CGFloat h  = shared_look_tool_pad + head.fittingSize.height + shared_look_tool_pad + cs.height +
                 shared_look_tool_pad + 1.0 + shared_look_tool_bar_h;

    SharedToolWindow *window = [[SharedToolWindow alloc]
        initWithContentRect:NSMakeRect(0, 0, w, h)
                  styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable |
                            NSWindowStyleMaskUtilityWindow
                    backing:NSBackingStoreBuffered
                      defer:NO];
    window.title                  = window_title;
    window.floatingPanel          = YES;
    window.hidesOnDeactivate      = NO;
    window.becomesKeyOnlyIfNeeded = NO;
    window.releasedWhenClosed     = NO;
    window.delegate               = p;
    p.panel                       = window;
    NSView *cv = window.contentView;

    [cv addSubview:head];

    NSBox *rule = [[NSBox alloc] init];
    rule.boxType = NSBoxSeparator;
    rule.translatesAutoresizingMaskIntoConstraints = NO;
    [cv addSubview:rule];

    content.translatesAutoresizingMaskIntoConstraints = NO;
    [cv addSubview:content];

    [NSLayoutConstraint activateConstraints:@[
        [head.topAnchor        constraintEqualToAnchor:cv.topAnchor constant:shared_look_tool_pad],
        [head.centerXAnchor    constraintEqualToAnchor:cv.centerXAnchor],
        [head.leadingAnchor    constraintGreaterThanOrEqualToAnchor:cv.leadingAnchor
                                                           constant:shared_look_tool_pad],
        [head.trailingAnchor   constraintLessThanOrEqualToAnchor:cv.trailingAnchor
                                                        constant:-shared_look_tool_pad],
        [content.topAnchor     constraintEqualToAnchor:head.bottomAnchor constant:shared_look_tool_pad],
        [content.centerXAnchor constraintEqualToAnchor:cv.centerXAnchor],
        [rule.leadingAnchor    constraintEqualToAnchor:cv.leadingAnchor],
        [rule.trailingAnchor   constraintEqualToAnchor:cv.trailingAnchor],
        [rule.bottomAnchor     constraintEqualToAnchor:cv.bottomAnchor constant:-shared_look_tool_bar_h],
        [rule.heightAnchor     constraintEqualToConstant:1.0],
    ]];

    /* The buttons, right-aligned: [0] rightmost, the rest to its left. */
    NSButton *right = nil;
    for (NSButton *b in controls) {
        [cv addSubview:b];
        [NSLayoutConstraint activateConstraints:@[
            [b.trailingAnchor constraintEqualToAnchor:right ? right.leadingAnchor : cv.trailingAnchor
                                             constant:right ? -shared_look_tool_btn_gap
                                                            : -shared_look_tool_btn_margin],
            [b.bottomAnchor   constraintEqualToAnchor:cv.bottomAnchor
                                             constant:-(shared_look_tool_bar_h - shared_look_tool_btn_h) / 2.0],
            [b.widthAnchor    constraintEqualToConstant:button_w(b)],
            [b.heightAnchor   constraintEqualToConstant:shared_look_tool_btn_h],
        ]];
        right = b;
    }
    return p;
}

/*
 * button_clicked: — run the button handler: nil closes the panel, a
 * problem is shown in the subtitle's place and the panel stays.
 *
 * Inputs:
 *   sender — the clicked button; its tag is the index in buttons
 */
- (void)
button_clicked:(NSButton *)sender
{
    [self show_subtitle:self.subtitle problem:NO];
    NSString *problem = self.button_handler ? self.button_handler(sender.tag) : nil;
    if (problem) {
        [self show_subtitle:problem problem:YES];
        NSBeep();
        return;
    }
    self.chosen = YES;
    [self.panel close];
}

/*
 * panel_with_title:…:handler: — see shared_tool_panel.h.
 */
+ (instancetype)
panel_with_title:(NSString *)window_title
      headline:(NSString *)headline
        subtitle:(NSString *)subtitle
          symbol:(NSString *)symbol
         content:(NSView *)content
         buttons:(NSArray<NSString *> *)buttons
     destructive:(NSInteger)destructive
         handler:(NSString *(^)(NSInteger index))handler
{
    return [self build_with_title:window_title headline:headline subtitle:subtitle
                           symbol:symbol content:content buttons:buttons
                      destructive:destructive handler:handler];
}

/*
 * show_message:… — see shared_tool_panel.h.
 */
+ (void)
show_message:(NSString *)title
     message:(NSString *)message
      symbol:(NSString *)symbol
     buttons:(NSArray<NSString *> *)buttons
 destructive:(NSInteger)destructive
        over:(NSWindow *)parent
     handler:(void (^)(NSInteger index))handler
{
    SharedToolPanel *p = [self build_with_title:shared_ui_app_name() headline:title subtitle:@""
                                         symbol:symbol content:message_view(message ?: @"")
                                        buttons:buttons destructive:destructive
                                        handler:^NSString *(NSInteger index) {
        if (handler) handler(index);
        return nil;
    }];
    p.dismissed_handler = ^{ if (handler) handler(-1); };
    [p show_over:parent];
}

/*
 * show_over: — see shared_tool_panel.h.
 */
- (void)
show_over:(NSWindow *)parent
{
    if (!live_panels) live_panels = [NSMutableSet set];
    [live_panels addObject:self];
    if (parent) {
        NSRect pf = parent.frame, f = self.panel.frame;
        [self.panel setFrameOrigin:NSMakePoint(NSMidX(pf) - f.size.width / 2.0,
                                               NSMidY(pf) - f.size.height / 2.0)];
    } else {
        [self.panel center];
    }
    [NSApp activate];
    [self.panel makeKeyAndOrderFront:nil];
}

/*
 * window — see shared_tool_panel.h.
 */
- (NSPanel *)
window
{
    return self.panel;
}

/*
 * windowWillClose: — drop the handlers (which may reference the caller's
 * objects) and the panel's self-retention, and report a close without a
 * button click to the dismissed handler.
 *
 * Inputs:
 *   note — close notification (unused)
 */
- (void)
windowWillClose:(NSNotification *)note
{
    (void)note;
    void (^dismissed)(void) = self.chosen ? nil : self.dismissed_handler;
    self.button_handler    = nil;
    self.dismissed_handler = nil;
    [live_panels removeObject:self];
    if (dismissed) dismissed();
}

@end
