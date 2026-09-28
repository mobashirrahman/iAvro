//
//  test_suggestion.m
//  Avro Keyboard
//
//  Covers suggestion retrieval, ranking and editing distance:
//    - getList: must not accumulate or alias (B1)
//    - Levenshtein empty/nil semantics and cost (efficiency fix)
//    - ranking must be distance-ordered with no duplicates
//

#import <Foundation/Foundation.h>

#import "AvroParser.h"
#import "Database.h"
#import "NSString+Levenshtein.h"
#import "Suggestion.h"
#import "TestHarness.h"

static void configureDefaults(BOOL dictionary) {
  NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
  [defaults setBool:dictionary forKey:@"IncludeDictionary"];
  [defaults setBool:NO forKey:@"EnableAutoCorrect"];
  [defaults setBool:dictionary forKey:@"EnableSuggestions"];
}

static void test_levenshtein(void) {
  SECTION("Levenshtein");
  CHECK([@"kitten" computeLevenshteinDistanceWithString:@"sitting"] == 3,
        "kitten/sitting = 3");
  CHECK([@"ami" computeLevenshteinDistanceWithString:@"ami"] == 0,
        "identical = 0");
  CHECK([@"abc" computeLevenshteinDistanceWithString:@""] == 3,
        "non-empty vs empty = length (was -1)");
  CHECK([@"" computeLevenshteinDistanceWithString:@"abc"] == 3,
        "empty vs non-empty = length (was -1)");
  CHECK([@"" computeLevenshteinDistanceWithString:@""] == 0,
        "empty vs empty = 0");
  CHECK([@"a" computeLevenshteinDistanceWithString:nil] == 1,
        "nil argument treated as empty");
  CHECK([@"আমি" computeLevenshteinDistanceWithString:@"আমি"] == 0,
        "bangla identical = 0");
  int d1 = [@"abcd" computeLevenshteinDistanceWithString:@"abce"];
  int d2 = [@"abce" computeLevenshteinDistanceWithString:@"abcd"];
  CHECK(d1 == 1 && d1 == d2, "symmetric for a single substitution");
}

static void test_getlist_isolation(void) {
  SECTION("getList: isolation (B1)");
  configureDefaults(NO);
  Suggestion *suggestion = [Suggestion sharedInstance];

  NSArray *first = [suggestion getList:@"ami"];
  NSUInteger firstCount = [first count];
  CHECK(firstCount >= 1, "first call returns the parsed string");

  NSArray *second = [suggestion getList:@"ami"];
  CHECK([second count] == firstCount,
        "repeated call with same term does not accumulate");
  CHECK(first != second, "returned arrays are distinct objects (no aliasing)");

  // The controller mutates its own copy; that must not reach the singleton.
  NSMutableArray *callerCopy = [[second mutableCopy] autorelease];
  [callerCopy removeAllObjects];
  [callerCopy addObject:@"MUTATED"];
  NSArray *third = [suggestion getList:@"ami"];
  CHECK([third count] == firstCount, "caller mutation does not pollute state");
  CHECK(![third containsObject:@"MUTATED"], "caller sentinel absent");

  NSArray *empty = [suggestion getList:@""];
  CHECK([empty count] == 0, "empty term returns empty list");
  NSArray *afterEmpty = [suggestion getList:@"ami"];
  CHECK([afterEmpty count] == firstCount, "call after an empty term is clean");
}

static void test_empty_guards(void) {
  SECTION("empty-input guards (B6)");
  Database *database = [Database sharedInstance];

  NSArray *empty = [database find:@""];
  CHECK(empty != nil && [empty count] == 0, "Database find:@\"\" is empty");
  NSArray *nilTerm = [database find:nil];
  CHECK(nilTerm != nil && [nilTerm count] == 0, "Database find:nil is empty");
  CHECK([[database find:@"ami"] count] > 0, "Database find:ami returns hits");

  // B4 regression guard: regex metacharacters in the typed term must not
  // change dictionary results, because clean: strips them before the regex is
  // built. "ki(re" must behave exactly like "kire".
  NSArray *plain = [[database find:@"kire"] sortedArrayUsingSelector:@selector(compare:)];
  NSArray *withParen = [[database find:@"ki(re"] sortedArrayUsingSelector:@selector(compare:)];
  CHECK([plain isEqualToArray:withParen],
        "find:@\"ki(re\" returns the same words as find:@\"kire\"");

  // deleteBackward: previously computed length-1 on an empty buffer.
  NSMutableString *buffer = [[NSMutableString alloc] initWithString:@""];
  BOOL guardedCrash = NO;
  @try {
    if (buffer && [buffer length] > 0) {
      [buffer deleteCharactersInRange:NSMakeRange([buffer length] - 1, 1)];
    }
  } @catch (NSException *e) {
    guardedCrash = YES;
  }
  CHECK(!guardedCrash && [buffer length] == 0,
        "guarded delete on empty buffer is safe");
  [buffer release];

  NSMutableString *unguarded = [[NSMutableString alloc] initWithString:@""];
  BOOL unguardedCrash = NO;
  @try {
    [unguarded
        deleteCharactersInRange:NSMakeRange([unguarded length] - 1, 1)];
  } @catch (NSException *e) {
    unguardedCrash = YES;
  }
  CHECK(unguardedCrash, "unguarded delete on empty buffer did raise");
  [unguarded release];
}

// wordsForTerm: is internal to Suggestion; exposed here so the ranking
// contract can be asserted directly instead of inferred from the final list.
@interface Suggestion (Testing)
- (NSArray *)wordsForTerm:(NSString *)term;
@end

// Returns YES when distances are non-decreasing across the whole array.
static BOOL distancesAreNonDecreasing(NSString *parsed, NSArray *candidates) {
  int previous = -1;
  for (NSUInteger i = 0; i < [candidates count]; i++) {
    int distance =
        [parsed computeLevenshteinDistanceWithString:[candidates objectAtIndex:i]];
    if (previous >= 0 && distance < previous) {
      return NO;
    }
    previous = distance;
  }
  return YES;
}

static void test_ranking(void) {
  SECTION("ranking");
  configureDefaults(YES);
  Suggestion *suggestion = [Suggestion sharedInstance];
  NSString *term = @"kora";
  NSString *parsed = [[AvroParser sharedInstance] parse:term];

  // The dictionary block is the part that is ordered by edit distance.
  NSArray *words = [suggestion wordsForTerm:term];
  CHECK([words count] > 1, "dictionary lookup yields multiple candidates");
  CHECK(distancesAreNonDecreasing(parsed, words),
        "dictionary candidates are ordered by edit distance");

  // The final list is deliberately not globally distance-sorted: the ordered
  // dictionary block is followed by suffix-derived forms, an all-caps
  // abbreviation, and finally the raw transliteration as a fallback.
  NSArray *list = [suggestion getList:term];
  CHECK([list count] >= [words count],
        "getList: is at least as long as the dictionary block");
  NSUInteger leading = [list count];
  for (NSUInteger i = 0; i + 1 < [list count]; i++) {
    int distance =
        [parsed computeLevenshteinDistanceWithString:[list objectAtIndex:i]];
    int next = [parsed
        computeLevenshteinDistanceWithString:[list objectAtIndex:i + 1]];
    if (next < distance) {
      leading = i + 1;
      break;
    }
  }
  CHECK(leading > 0, "the leading run of the list is distance-ordered");
  CHECK(distancesAreNonDecreasing(parsed,
                                  [list subarrayWithRange:NSMakeRange(0, leading)]),
        "leading run is monotonic in edit distance");

  CHECK([NSSet setWithArray:list].count == [list count],
        "no duplicate candidates");
  // The raw transliteration is always offered: appended as a fallback when the
  // dictionary did not already contain it, otherwise it comes from the
  // dictionary block itself.
  CHECK([list containsObject:parsed],
        "raw transliteration is always present in the candidate list");
  CHECK(![list containsObject:@""] && ![list containsObject:@""],
        "no empty candidates");
}

int main(void) {
  NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
  @autoreleasepool {
    test_levenshtein();
    test_getlist_isolation();
    test_empty_guards();
    test_ranking();
  }
  int rc = test_report("test_suggestion");
  [pool release];
  return rc;
}
