//
//  TestHarness.h
//  Avro Keyboard test support
//
//  Tiny assertion harness shared by the test programs. Header-only so each
//  test file can be compiled and run standalone by Tests/run_tests.sh.
//

#ifndef AVRO_TEST_HARNESS_H
#define AVRO_TEST_HARNESS_H

#include <Foundation/Foundation.h>

static int gFailures = 0;
static int gChecks = 0;

#define CHECK(cond, msg)                                                        \
  do {                                                                          \
    gChecks++;                                                                  \
    if (cond) {                                                                 \
      printf("  PASS  %s\n", (msg));                                             \
    } else {                                                                    \
      printf("  FAIL  %s\n", (msg));                                             \
      gFailures++;                                                              \
    }                                                                           \
  } while (0)

#define SECTION(name) printf("== %s ==\n", (name))

static int test_report(const char *suite) {
  printf("\n%s: %d checks, %d failure(s)\n", suite, gChecks, gFailures);
  printf("%s\n", gFailures == 0 ? "ALL CHECKS PASSED" : "THERE WERE FAILURES");
  return gFailures == 0 ? 0 : 1;
}

#endif /* AVRO_TEST_HARNESS_H */
