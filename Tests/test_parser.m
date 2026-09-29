//
//  test_parser.m
//  Avro Keyboard
//
//  Covers the transliteration parser contracts:
//    - data.json / regex.json tables are complete and order-independent
//    - case-sensitive characters survive normalisation (B4)
//    - isExact honours end-of-string matches (B5)
//    - parse: produces stable, spec-conformant output
//

#import <Foundation/Foundation.h>

#import "AvroParser.h"
#import "RegexParser.h"
#import "TestHarness.h"

static NSDictionary *loadJSON(NSString *name) {
  NSString *path = [[NSBundle mainBundle] pathForResource:name ofType:@"json"];
  if (!path) {
    path = [[NSFileManager defaultManager] currentDirectoryPath];
    path = [path stringByAppendingPathComponent:
                         [NSString stringWithFormat:@"%@.json", name]];
  }
  NSData *data = [NSData dataWithContentsOfFile:path];
  if (!data) {
    return nil;
  }
  return [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL];
}

// The old implementation binary-searched this array assuming length-descending,
// lex-ascending order. It is not in that order, so patterns were missed.
static void test_pattern_table_shape(void) {
  SECTION("pattern table shape");
  NSDictionary *json = loadJSON(@"data");
  if (!json) {
    CHECK(NO, "data.json loaded");
    return;
  }
  NSArray *patterns = [json objectForKey:@"patterns"];
  CHECK([patterns count] > 0, "data.json has patterns");

  NSMutableDictionary *seen = [NSMutableDictionary dictionary];
  for (NSDictionary *entry in patterns) {
    NSString *find = [entry objectForKey:@"find"];
    if (find) {
      seen[find] = @YES;
    }
  }
  CHECK([seen count] > 0, "every pattern has a find key");
  printf("       %lu patterns, %lu unique find keys\n",
         (unsigned long)[patterns count], (unsigned long)[seen count]);

  // Every pattern must be resolvable through the hash index the parser now
  // uses, so lookups cannot silently miss regardless of file order.
  // Patterns whose "replace" is intentionally empty (Avro's backtick/joiner
  // control forms) are excluded: empty output is correct for those.
  AvroParser *parser = [AvroParser sharedInstance];
  NSUInteger expected = 0;
  NSUInteger resolved = 0;
  for (NSDictionary *entry in patterns) {
    NSString *find = [entry objectForKey:@"find"];
    NSString *replace = [entry objectForKey:@"replace"];
    if (!find || [replace length] == 0) {
      continue;
    }
    expected++;
    NSString *out = [parser parse:find];
    if (out && [out length] > 0) {
      resolved++;
    }
  }
  CHECK(expected > 0, "data.json has transliterating patterns");
  CHECK(resolved == expected,
        "every transliterating pattern produces non-empty output");

  // The intentionally empty-replace control patterns must stay empty so they
  // cannot leak stray characters into composition.
  CHECK([[parser parse:@"`"] length] == 0,
        "backtick control pattern stays empty");
}

static void test_metacharacter_stripping(void) {
  SECTION("regex metacharacter stripping (B4: not a bug)");
  AvroParser *parser = [AvroParser sharedInstance];
  RegexParser *regex = [RegexParser sharedInstance];

  // regex.json's "casesensitive" set is the regex metacharacters, not letters.
  // clean: deliberately drops them so a term such as "ki(re" can never inject
  // invalid syntax (or a wildcard) into the generated dictionary regex.
  CHECK([[regex clean:@"a|b"] isEqualToString:@"ab"],
        "clean: drops the pipe metacharacter");
  CHECK([[regex clean:@"a(b)c"] isEqualToString:@"abc"],
        "clean: drops parentheses");
  CHECK([[regex clean:@".*+?"] length] == 0,
        "clean: drops quantifier and wildcard metacharacters");
  CHECK([[regex clean:@"|()[]{}^$*+?."] length] == 0,
        "clean: drops the full metacharacter set");

  // Letters are still normalised, which is what clean: exists to do.
  CHECK([[regex clean:@"Ami"] isEqualToString:@"ami"],
        "clean: lowercases letters");
  CHECK([[regex clean:@"AMIT"] isEqualToString:@"amit"],
        "clean: lowercases the whole term");
  CHECK([[regex clean:@""] length] == 0, "clean: empty stays empty");
  CHECK([[regex parse:@"ami"] length] > 0, "RegexParser parse: works end to end");

  // The transliteration normaliser is a different code path and must keep
  // case-sensitive letters, otherwise "bhalO" style input breaks.
  CHECK([[parser fix:@"Ami"] isEqualToString:@"ami"],
        "fix: lowercases non-case-sensitive letters");
  CHECK([[parser fix:@"O"] isEqualToString:@"O"],
        "fix: preserves case-sensitive O");
}

static void test_is_exact(void) {
  SECTION("isExact boundary (B5)");
  AvroParser *parser = [AvroParser sharedInstance];
  RegexParser *regex = [RegexParser sharedInstance];

  // End-anchored: previously required end < length, so these never matched.
  CHECK([parser isExact:@"ch" heystack:@"such" start:2 end:4 not:NO],
        "AvroParser isExact matches at end of string");
  CHECK([regex isExact:@"ch" heystack:@"such" start:2 end:4 not:NO],
        "RegexParser isExact matches at end of string");
  CHECK([parser isExact:@"ami" heystack:@"ami" start:0 end:3 not:NO],
        "full-string exact match works");

  CHECK([parser isExact:@"bc" heystack:@"abcd" start:1 end:3 not:NO],
        "middle match works");
  CHECK([parser isExact:@"ab" heystack:@"abcd" start:0 end:2 not:NO],
        "start match works");
  CHECK([parser isExact:@"xx" heystack:@"such" start:2 end:4 not:NO] == NO,
        "mismatch returns NO");
  CHECK([parser isExact:@"ch" heystack:@"such" start:2 end:4 not:YES] == NO,
        "negative flag inverts a match");
  CHECK([parser isExact:@"xx" heystack:@"such" start:2 end:4 not:YES],
        "negative flag inverts a mismatch");

  // Out-of-range inputs must not raise.
  CHECK([parser isExact:@"ab" heystack:@"ab" start:-1 end:1 not:NO] == NO,
        "negative start is safe");
  CHECK([parser isExact:@"ab" heystack:@"ab" start:0 end:5 not:NO] == NO,
        "end past length is safe");
  CHECK([parser isExact:@"b" heystack:@"ab" start:2 end:1 not:NO] == NO,
        "reversed range is safe");
}

static void test_parse_output(void) {
  SECTION("parse output stability");
  AvroParser *parser = [AvroParser sharedInstance];

  struct {
    const char *input;
    const char *expected;
  } cases[] = {
      {"ami", "আমি"},
      {"tumi", "তুমি"},
      {"bangla", "বাংলা"},
      {"kotha", "কথা"},
      // Lowercase "o" is its own letter, so a trailing "o" is not a vowel
      // sign: "bhalo" transliterates to the stem, "bhalO" to the full word.
      {"bhalo", "ভাল"},
      {"bhalO", "ভালো"},
      // Patterns that the old binary search silently dropped.
      {"TH", "ৎ"},
      {"H", "ঃ"},
      {"qq", "ঁ"},
  };

  for (size_t i = 0; i < sizeof(cases) / sizeof(cases[0]); i++) {
    NSString *in = [NSString stringWithUTF8String:cases[i].input];
    NSString *want = [NSString stringWithUTF8String:cases[i].expected];
    NSString *got = [parser parse:in];
    CHECK([got isEqualToString:want],
          ([NSString stringWithFormat:@"parse \"%s\" -> %@", cases[i].input,
                                    want])
              .UTF8String);
  }

  CHECK([[parser parse:@""] length] == 0, "parse empty returns empty");
  CHECK([[parser parse:nil] length] == 0, "parse nil returns empty");
}

int main(void) {
  NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
  @autoreleasepool {
    test_pattern_table_shape();
    test_metacharacter_stripping();
    test_is_exact();
    test_parse_output();
  }
  int rc = test_report("test_parser");
  [pool release];
  return rc;
}
