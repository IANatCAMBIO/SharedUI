/*
 * check.h — the test harness: a failure counter and a way to let the main
 * queue run.  Each test is a main() that returns check_result().
 */

#ifndef TESTS_CHECK_H
#define TESTS_CHECK_H

#include <CoreFoundation/CoreFoundation.h>
#include <stdio.h>

static int check_failures;

/*
 * check — record one assertion.
 *
 * Inputs:
 *   ok   — the condition that should hold
 *   what — what was being checked, printed either way
 */
static inline void
check(int ok, const char *what)
{
    printf("%s %s\n", ok ? "ok  " : "FAIL", what);
    if (!ok) check_failures++;
}

/*
 * check_result — the test program's exit status.
 *
 * Output: 0 when every check passed, 1 otherwise.
 */
static inline int
check_result(void)
{
    if (check_failures > 0) printf("%d check(s) failed\n", check_failures);
    return check_failures > 0 ? 1 : 0;
}

/*
 * check_spin — run the main run loop (and so the main dispatch queue) for a
 * while, letting timers and queued callbacks fire.
 *
 * Inputs:
 *   seconds — how long to run
 */
static inline void
check_spin(double seconds)
{
    CFRunLoopRunInMode(kCFRunLoopDefaultMode, seconds, false);
}

#endif /* TESTS_CHECK_H */
