#import <Cocoa/Cocoa.h>

/*
 * shared_tag_popup — the list of known tags offered while one is being
 * typed (Notes: under the caret; Tasks: under the Tags field).  A
 * borderless child panel with rounded corners (shared_look_popup_radius)
 * that never takes the keyboard focus: the owner keeps the keys and moves
 * the selection (Up/Down) or chooses (Return/Tab) itself; a click on a row
 * chooses it.  Main thread only.
 */
@interface SharedTagPopup : NSObject

/* Called with the chosen tag's name (no '#') when a row is clicked. */
@property (nonatomic, copy) void (^chosen_handler)(NSString *name);

/* YES: no row is selected until Up/Down moves into the list, so Return
 * still means the text as typed.  NO (default): the first row is selected. */
@property (nonatomic, assign) BOOL starts_unselected;

/*
 * show_names:under:of: — list the names (the first selected unless starts_unselected) under a
 * rectangle of a view, or hide the list when there are none.
 *
 * Inputs:
 *   names — tag names without '#', in display order
 *   rect  — where the tag starts, in the view's coordinates
 *   view  — the view (its window becomes the list's parent)
 */
- (void)show_names:(NSArray<NSString *> *)names under:(NSRect)rect of:(NSView *)view;

/*
 * move_selection: — select the row `delta` away, kept within the list.
 *
 * Inputs:
 *   delta — +1 for the next row, -1 for the previous (from no selection,
 *           either selects the first)
 */
- (void)move_selection:(NSInteger)delta;

/*
 * selected_name — the selected row's name.
 *
 * Output: the name, or nil when the list is not on screen or no row is selected.
 */
- (NSString *)selected_name;

/*
 * names — what the list shows.
 *
 * Output: the names, or an empty array when hidden.
 */
- (NSArray<NSString *> *)names;

/*
 * is_visible — is the list on screen?
 *
 * Output: YES while it is.
 */
- (BOOL)is_visible;

/*
 * hide — take the list off screen.
 */
- (void)hide;

@end
