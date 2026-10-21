/*
 * shared_tool_panel — the apps' own dialog: a small floating utility
 * window, in the style of the Files app, which Notes and Tasks both show
 * wherever a system alert, an alert sheet or a custom sheet would appear.
 * shared_ui_notice and shared_ui_confirm (shared_ui.h) are built on it;
 * Edit Tag and the date pickers build their own with their controls.
 *
 * A tool panel is a utility-titlebar panel with a centred header (symbol,
 * bold headline and subtitle below it, on the window's own background) at
 * the top, the caller's controls or a message below it, and a button bar
 * at the bottom.  A panel whose title bar already says what it is passes
 * an EMPTY headline and has no header: its controls are flush left at the
 * top, and a problem shows in red at the left of the button bar.  A
 * panel is not modal: it floats above ordinary windows until the user
 * clicks a button, presses Return (the default button), or presses Escape
 * or the close box, which dismiss it without an answer — so Escape never
 * answers a destructive question.  Return never destroys either: a
 * destructive button is never the default (shared_ui_confirm puts Cancel
 * there).  The apps' text size (shared_look_ui_font) throughout.
 *
 * Also here: the blue hero strip, which only Tasks' reminders window uses;
 * no tool panel shows it.
 *
 * Main thread only.
 */

#import <Cocoa/Cocoa.h>

/*
 * SharedHero — the solid blue strip at the top of the reminders window: a white
 * symbol, a bold title and a dimmer subtitle under it.  It is
 * shared_look_hero_h tall (it carries that constraint); the caller pins
 * its top and sides.
 */
@interface SharedHero : NSView

@property (nonatomic, strong, readonly) NSTextField *title_label;
@property (nonatomic, strong, readonly) NSTextField *subtitle_label;  /* hidden while empty */

/*
 * init_with_symbol: — build the strip with empty labels.
 *
 * Inputs:
 *   symbol — SF Symbols name for the icon; nil or unknown shows none
 *
 * Output: the strip.
 */
- (instancetype)init_with_symbol:(NSString *)symbol;

/*
 * set_title:subtitle: — what the strip says.  The title sits on the
 * strip's centre line when there is no subtitle, above it when there is.
 *
 * Inputs:
 *   title    — the bold line
 *   subtitle — the second line, in the subtitle colour; nil or empty for
 *              none
 */
- (void)set_title:(NSString *)title subtitle:(NSString *)subtitle;

/*
 * show_problem: — a one-line problem in the subtitle's place, highlighted
 * (a tool panel's handler refusing an answer).  set_title:subtitle: puts
 * the subtitle back.
 *
 * Inputs:
 *   problem — the line
 */
- (void)show_problem:(NSString *)problem;

@end

/*
 * SharedToolPanel — one panel on screen.  It keeps itself alive while it
 * is showing and lets go of its handlers when it closes.  Its window is a
 * SharedToolWindow (an NSPanel), which a test can find by class.
 */
@interface SharedToolPanel : NSObject

/*
 * panel_with_title:headline:subtitle:symbol:content:buttons:destructive:handler:
 * — build a panel that asks for something: the caller's controls above
 * its buttons (Edit Tag's OK / Cancel, a date's Set / Clear / Cancel).
 * show_over: displays it.
 *
 * Inputs:
 *   window_title — title bar text
 *   headline     — bold line under the symbol; empty selects the
 *                  headerless style (see above)
 *   subtitle     — second line under the headline; problems show in its
 *                  place (headerless: at the left of the button bar);
 *                  unused when headerless
 *   symbol       — SF Symbols name for the symbol centred at the top; may
 *                  be nil; unused when headerless
 *   content      — the controls, sized by their own fittingSize (fixed
 *                  widths and heights); not retained after close
 *   buttons      — button labels, at least one: [0] is the default (Return)
 *                  and sits rightmost, the rest follow to its left
 *   destructive  — index of the button that takes the destructive look,
 *                  never 0; -1 for none
 *   handler      — called with the index of the clicked button (not when
 *                  the panel is dismissed); returns nil to close the panel
 *                  or a one-line problem to show in the subtitle's place
 *                  (the panel stays open)
 *
 * Output: the panel, not yet shown.
 */
+ (instancetype)panel_with_title:(NSString *)window_title
                        headline:(NSString *)headline
                        subtitle:(NSString *)subtitle
                          symbol:(NSString *)symbol
                         content:(NSView *)content
                         buttons:(NSArray<NSString *> *)buttons
                     destructive:(NSInteger)destructive
                         handler:(NSString *(^)(NSInteger index))handler;

/*
 * show_message:message:symbol:buttons:destructive:over:handler: — show a
 * message in a tool panel and return at once: the replacement for a
 * system alert.  The title bar names the app (shared_ui_app_name).
 *
 * Inputs:
 *   title       — headline, under the symbol
 *   message     — wrapped, selectable body text (long text scrolls); may
 *                 be nil
 *   symbol      — SF Symbols name for the symbol centred at the top; may be nil
 *   buttons     — button labels, at least one: [0] is the default (Return)
 *                 and sits rightmost, the rest follow to its left
 *   destructive — index of the button that takes the destructive look,
 *                 never 0; -1 for none
 *   parent      — window to centre over; nil = the screen
 *   handler     — called once on the main thread with the index of the
 *                 clicked button, or -1 when the panel was dismissed
 *                 (Escape or the close box) without one; may be nil
 */
+ (void)show_message:(NSString *)title
             message:(NSString *)message
              symbol:(NSString *)symbol
             buttons:(NSArray<NSString *> *)buttons
         destructive:(NSInteger)destructive
                over:(NSWindow *)parent
             handler:(void (^)(NSInteger index))handler;

/*
 * show_over: — centre the panel over a window (the screen if nil), bring it
 * forward and make it key.
 *
 * Inputs:
 *   parent — window to centre over; may be nil
 */
- (void)show_over:(NSWindow *)parent;

/*
 * window — the underlying panel, e.g. to set the first responder.
 *
 * Output: the NSPanel.
 */
- (NSPanel *)window;

@end
