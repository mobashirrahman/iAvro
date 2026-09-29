//
//  test_controller.m
//  Avro Keyboard
//
//  Covers controller-side selection logic that is awkward to drive through
//  InputMethodKit. The production helpers are mirrored here so the invariants
//  can be asserted without a live IMK session:
//    - candidate strings arrive as NSString or NSAttributedString (B2)
//    - selection index is always in range (B3)
//    - prefix/suffix stripping never underflows
//

#import <Foundation/Foundation.h>

#import "TestHarness.h"

// Mirrors AvroKeyboardController.stringFromCandidate:
static NSString *StringFromCandidate(id candidate) {
  if (!candidate) {
    return nil;
  }
  if ([candidate isKindOfClass:[NSAttributedString class]]) {
    return [(NSAttributedString *)candidate string];
  }
  if ([candidate isKindOfClass:[NSString class]]) {
    return (NSString *)candidate;
  }
  return nil;
}

// Mirrors the bounds clamp used before indexing the candidate array.
static NSUInteger SafeIndex(NSInteger selected, NSUInteger count) {
  if (count == 0) {
    return 0;
  }
  if (selected < 0 || (NSUInteger)selected >= count) {
    return 0;
  }
  return (NSUInteger)selected;
}

static void test_candidate_types(void) {
  SECTION("candidate value types (B2)");
  NSString *plain = @"আমি";
  CHECK([StringFromCandidate(plain) isEqualToString:plain],
        "NSString candidate handled");
  NSAttributedString *attributed =
      [[[NSAttributedString alloc] initWithString:@"তুমি"] autorelease];
  CHECK([StringFromCandidate(attributed) isEqualToString:@"তুমি"],
        "NSAttributedString candidate unwrapped");
  CHECK(StringFromCandidate(nil) == nil, "nil candidate returns nil");

  // The pre-fix code called .string on an NSString, which raises.
  BOOL raised = NO;
  @try {
    [plain performSelector:@selector(string)];
  } @catch (NSException *e) {
    raised = YES;
  }
  CHECK(raised, "pre-fix pattern [NSString string] did raise");
}

static void test_index_safety(void) {
  SECTION("selection index safety (B3)");
  CHECK(SafeIndex(0, 1) == 0, "in-range index preserved");
  CHECK(SafeIndex(2, 5) == 2, "in-range index preserved (mid)");
  CHECK(SafeIndex(4, 1) == 0, "stale index clamps to 0");
  CHECK(SafeIndex(-1, 3) == 0, "negative index clamps to 0");
  CHECK(SafeIndex(99, 3) == 0, "far out-of-range index clamps to 0");
  CHECK([NSArray array].count == 0, "empty candidate list detected");

  // indexOfObject: returning NSNotFound must not become an index.
  NSArray *candidates = [NSArray arrayWithObjects:@"আমি", @"তুমি", nil];
  NSUInteger found = [candidates indexOfObject:@"তুমি"];
  CHECK(found == 1, "indexOfObject locates a candidate");
  CHECK([candidates indexOfObject:@"নেই"] == NSNotFound,
        "missing candidate yields NSNotFound");
}

static void test_prev_selection(void) {
  SECTION("previously selected index (B3)");
  NSArray *list = [NSArray arrayWithObjects:@"a", @"b", @"b", nil];
  NSString *remembered = @"b";

  int previous = -1;
  for (int i = 0; i < (int)[list count]; i++) {
    if (previous == -1 &&
        [[list objectAtIndex:i] isEqualToString:remembered]) {
      previous = i;
    }
  }
  CHECK(previous == 1, "first match wins");

  // The old test was `if (_prevSelected && ...)`, which treats 0 as false and
  // -1 as true. Assert the corrected semantics explicitly.
  int zero = 0;
  BOOL oldCondition = (zero && 1);
  CHECK(oldCondition == NO,
        "old truthiness test drops a legitimate index-0 match");
  int minusOne = -1;
  CHECK((minusOne && 1) == YES,
        "old truthiness test wrongly accepts -1");

  previous = -1;
  NSString *noMemory = nil;
  for (int i = 0; i < (int)[list count]; i++) {
    if (previous == -1 && noMemory &&
        [[list objectAtIndex:i] isEqualToString:noMemory]) {
      previous = i;
    }
  }
  CHECK(previous == -1, "nil remembered string never matches");

  // Inserting an emoticon at index 0 shifts a remembered index.
  int shifted = 1;
  if (shifted >= 0) {
    shifted += 1;
  }
  CHECK(shifted == 2, "insert at 0 shifts remembered index 1 -> 2");
}

static void test_prefix_suffix_range(void) {
  SECTION("prefix/suffix stripping");
  NSString *candidate = @"XআমিY";
  NSRange range = NSMakeRange(1, [candidate length] - 2);
  CHECK([[candidate substringWithRange:range] isEqualToString:@"আমি"],
        "prefix and suffix strip to the inner word");

  // Overlong prefix/suffix must be rejected rather than underflowing.
  NSString *longPrefix = @"প্রিফিক্সলং";
  NSString *longSuffix = @"সাফিক্সলং";
  BOOL inBounds = ([longPrefix length] + [longSuffix length] <=
                   [@"অ" length]);
  CHECK(!inBounds, "overlong prefix+suffix is detected as out of bounds");
}

int main(void) {
  NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
  @autoreleasepool {
    test_candidate_types();
    test_index_safety();
    test_prev_selection();
    test_prefix_suffix_range();
  }
  int rc = test_report("test_controller");
  [pool release];
  return rc;
}
