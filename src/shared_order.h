/*
 * shared_order — a hand-made order an app keeps in its config as a list of
 * ids ("30,10,40"): how the list is read back against what is on screen,
 * and how it is written.  Tasks keeps the order of its task list and board
 * this way (task_order.c), and both apps the order of their Favorites bar
 * (dragged into place), so the rule exists once, here.  Plain C, so an
 * app's C code can use it; the file is compiled with the module's .m.
 *
 * The rule, reading: ids the saved list names come first, in its
 * sequence; anything it does not mention (made since) keeps its current
 * relative order at the tail.  Forgiving by design: a saved id that is no
 * longer on screen matches nothing, and a token that is not a number is
 * skipped.  Writing: the ids comma separated, ids of 0 left out.
 */

#ifndef SHARED_ORDER_H
#define SHARED_ORDER_H

#include <stdint.h>

/*
 * shared_order_permutation — the display order a saved id list asks for,
 * as indices into `ids`.
 *
 * Inputs:
 *   ids   — the ids on screen, in their current order
 *   n     — how many
 *   saved — the config value, or NULL when none is saved
 *
 * Output:
 *   new int[n] (free it) holding every index 0..n-1 exactly once, so that
 *   position i should show ids[result[i]]; or NULL when there is nothing
 *   to do (no saved order, or fewer than two ids).
 */
int *shared_order_permutation(const int64_t *ids, int n, const char *saved);

/*
 * shared_order_text — the config value for an order.
 *
 * Inputs:
 *   ids — the ids in the order to remember; ids of 0 are skipped
 *   n   — how many
 *
 * Output:
 *   new string (free it): the ids, comma separated; or NULL when no id is
 *   worth storing (the caller then removes the key).
 */
char *shared_order_text(const int64_t *ids, int n);

#endif /* SHARED_ORDER_H */
