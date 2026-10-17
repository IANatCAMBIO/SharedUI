/*
 * shared_order.m — saved id lists (shared_order.h).  Plain C: nothing here
 * touches Objective-C, so Tasks' C tests link it as they link its core.
 */

#include "shared_order.h"

#include <inttypes.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* One on-screen id for the lookup: the id and where it sits now. */
typedef struct {
    int64_t id;
    int     index;
} order_slot_t;

/*
 * slot_compare — qsort order for the lookup: by id, then by position, so
 * that rows sharing an id are claimed first to last.
 *
 * Inputs:
 *   a, b — order_slot_t pointers
 *
 * Output:
 *   negative, zero or positive, as qsort expects.
 */
static int
slot_compare(const void *a, const void *b)
{
    const order_slot_t *sa = a;
    const order_slot_t *sb = b;

    if (sa->id != sb->id) return sa->id < sb->id ? -1 : 1;
    return sa->index - sb->index;
}

/*
 * slot_claim — the position of the first row with this id that the saved
 * order has not yet placed.
 *
 * Inputs:
 *   slots  — the lookup, sorted by slot_compare
 *   n      — its length
 *   id     — the id to find
 *   placed — which positions are already claimed
 *
 * Output:
 *   the row's current index, or -1 when no unplaced row has that id.
 */
static int
slot_claim(const order_slot_t *slots, int n, int64_t id, const bool *placed)
{
    int lo = 0;
    int hi = n;

    while (lo < hi) {               /* first slot whose id is >= id       */
        int mid = lo + (hi - lo) / 2;
        if (slots[mid].id < id) lo = mid + 1; else hi = mid;
    }
    for (; lo < n && slots[lo].id == id; lo++) {
        if (!placed[slots[lo].index]) return slots[lo].index;
    }
    return -1;
}

/*
 * shared_order_permutation — the permutation a saved id list asks for.  A
 * sorted lookup, not a nested scan: the scan was a quarter of a million
 * comparisons on a 500-row list, repeated on every refresh.
 * Inputs/output are documented in shared_order.h.
 */
int *
shared_order_permutation(const int64_t *ids, int n, const char *saved)
{
    if (ids == NULL || n <= 1 || saved == NULL || *saved == '\0') return NULL;

    order_slot_t *slots  = malloc((size_t)n * sizeof *slots);
    int          *order  = malloc((size_t)n * sizeof *order);
    bool         *placed = calloc((size_t)n, sizeof *placed);
    if (slots == NULL || order == NULL || placed == NULL) abort();

    for (int i = 0; i < n; i++) {
        slots[i].id    = ids[i];
        slots[i].index = i;
    }
    qsort(slots, (size_t)n, sizeof *slots, slot_compare);

    int fill = 0;
    for (const char *p = saved; p != NULL && *p != '\0'; ) {
        int64_t id = strtoll(p, NULL, 10);
        int     j  = id != 0 ? slot_claim(slots, n, id, placed) : -1;
        if (j >= 0) {
            order[fill++] = j;
            placed[j]     = true;
        }
        p = strchr(p, ',');
        if (p != NULL) p++;
    }

    /* Everything the saved list did not claim, in the order it had. */
    for (int i = 0; i < n; i++) {
        if (!placed[i]) order[fill++] = i;
    }
    free(placed);
    free(slots);
    return order;
}

/*
 * shared_order_text — the ids, comma separated.
 * Inputs/output are documented in shared_order.h.
 */
char *
shared_order_text(const int64_t *ids, int n)
{
    /* An int64 is at most 20 characters, plus its comma. */
    size_t  room = (size_t)(n > 0 ? n : 0) * 21 + 1;
    char   *text = malloc(room);
    size_t  used = 0;
    if (text == NULL) abort();

    text[0] = '\0';
    for (int i = 0; i < n; i++) {
        if (ids == NULL || ids[i] == 0) continue;
        used += (size_t)snprintf(text + used, room - used, "%s%" PRId64,
                                 used > 0 ? "," : "", ids[i]);
    }
    if (used == 0) {
        free(text);
        return NULL;
    }
    return text;
}
