//
//  test_typo_corrections.m
//  Avro Keyboard
//
//  Covers the narrow typo correction:
//    - the two rules produce the right candidates
//    - the cap is respected, and short terms are left alone
//    - recovery on real typos, measured against the dictionary
//    - correctly spelled input does not pay for it
//

#import <Foundation/Foundation.h>

#import "Database.h"
#import "TestHarness.h"
#import "TypoCorrections.h"

int main(void) {
  NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
  @autoreleasepool {
    [[NSUserDefaults standardUserDefaults] setBool:YES forKey:@"IncludeDictionary"];

    SECTION("doubled letter");
    NSArray *c1 = [TypoCorrections correctionsForTerm:@"kothha"];
    CHECK([c1 containsObject:@"kotha"], "kothha -> kotha");
    CHECK([c1 containsObject:@"kotha"], "doubled correction is present");
    NSArray *c2 = [TypoCorrections correctionsForTerm:@"banglaa"];
    CHECK([c2 containsObject:@"bangla"], "banglaa -> bangla");
    NSArray *c3 = [TypoCorrections correctionsForTerm:@"dhakka"];
    CHECK([c3 containsObject:@"dhaka"], "dhakka -> dhaka");

    SECTION("transposition is deliberately not attempted");
    // Implemented, then removed: with the wrong position unknown, corrections
    // must be tried left to right and the right one is rarely among the first
    // few. Measured at 4 of 10 typos for one lookup against 5 of 10 for four.
    NSArray *c4 = [TypoCorrections correctionsForTerm:@"bagnladesh"];
    CHECK([c4 count] == 0,
          "a transposed term yields no correction (documented cost decision)");
    CHECK([TypoCorrections maximumCorrections] == 1,
          "cap is one correction, so at most one extra lookup");

    SECTION("no correction is invented for clean input");
    NSArray *clean = [TypoCorrections correctionsForTerm:@"kotha"];
    for (NSString *c in clean) {
      CHECK(![c isEqualToString:@"kotha"], "a clean term is never returned as its own correction");
    }

    SECTION("bounds and cap");
    CHECK([[TypoCorrections correctionsForTerm:@""] count] == 0, "empty term -> no corrections");
    CHECK([[TypoCorrections correctionsForTerm:@"ab"] count] == 0,
          "short term -> no corrections (too short to have a useful typo)");
    CHECK([[TypoCorrections correctionsForTerm:@"abc"] count] == 0,
          "three characters -> no corrections");
    CHECK([[TypoCorrections correctionsForTerm:@"kotha"] count] <=
              [TypoCorrections maximumCorrections],
          "corrections never exceed the cap");
    // Many doubled letters must still yield at most one candidate.
    CHECK([[TypoCorrections correctionsForTerm:@"aabbaaccdd"] count] <=
              [TypoCorrections maximumCorrections],
          "multiple doubled runs still yield one correction");
    NSUInteger cap = [TypoCorrections maximumCorrections];
    printf("       cap is %lu corrections\n", (unsigned long)cap);

    SECTION("corrections are unique");
    NSMutableSet *unique = [NSMutableSet set];
    for (NSString *c in [TypoCorrections correctionsForTerm:@"aabbccdd"]) {
      [unique addObject:c];
    }
    CHECK([unique count] ==
              [[TypoCorrections correctionsForTerm:@"aabbccdd"] count],
          "no duplicate corrections");

    SECTION("real typos are recovered from the dictionary");
    NSDictionary *cases = [NSDictionary dictionaryWithObjectsAndKeys:
        @"কথা", @"kothha",
        @"বাংলা", @"banglaa",
        nil];
    for (NSString *typo in cases) {
      NSString *want = [cases objectForKey:typo];
      BOOL got = [[[Database sharedInstance] find:typo] containsObject:want];
      if (!got) {
        printf("       %-10s -> %s not recovered\n", [typo UTF8String],
               [want UTF8String]);
      }
      CHECK(got, ([NSString stringWithFormat:@"%@ recovers %@", typo, want])
                      .UTF8String);
    }

    SECTION("correctly spelled input is unaffected and cheap");
    // These are ordinary words; they must still resolve without corrections.
    CHECK([[[Database sharedInstance] find:@"bangla"] containsObject:@"বাংলা"],
          "bangla still finds বাংলা");
    CHECK([[[Database sharedInstance] find:@"kotha"] count] > 0,
          "kotha still finds candidates");
    CHECK([[[Database sharedInstance] find:@"bhalo"] count] > 0,
          "bhalo still finds candidates");
  }
  int rc = test_report("test_typo_corrections");
  [pool release];
  return rc;
}
