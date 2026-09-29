//
//  test_user_dictionary.m
//  Avro Keyboard
//
//  Covers the export/import file format:
//    - round trip of AutoCorrect entries and learned counts
//    - the older two-column "term value" form still imports
//    - comments, blank lines, CRLF and malformed rows are handled
//

#import <Foundation/Foundation.h>

#import "TestHarness.h"
#import "UserDictionary.h"

static NSDictionary *parse(NSString *text) {
  return [UserDictionary parseText:text];
}

int main(void) {
  NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
  @autoreleasepool {
    SECTION("round trip");
    NSDictionary *entries = [NSDictionary dictionaryWithObjectsAndKeys:
        @"আমি", @"ami",
        @"বাংলা", @"bangla",
        @"ঢাকা", @"dhaka", nil];
    NSDictionary *counts = [NSDictionary dictionaryWithObjectsAndKeys:
        [NSNumber numberWithUnsignedInteger:12], @"ঢাকা",
        [NSNumber numberWithUnsignedInteger:3], @"আমি", nil];
    NSString *text = [UserDictionary textForAutoCorrectEntries:entries
                                                  learnedCounts:counts
                                                     appVersion:@"2.0.6"];
    CHECK([text length] > 0, "export produced text");
    CHECK([text hasPrefix:@"#"], "export starts with a comment header");
    CHECK([text rangeOfString:@"app-version 2.0.6"].location != NSNotFound,
          "export records the app version");

    NSDictionary *parsed = parse(text);
    CHECK(parsed != nil, "export re-imports");
    NSDictionary *backEntries = [parsed objectForKey:@"autocorrect"];
    NSDictionary *backCounts = [parsed objectForKey:@"learned"];
    CHECK([backEntries count] == [entries count], "all AutoCorrect entries survive");
    CHECK([[backEntries objectForKey:@"ami"] isEqualToString:@"আমি"],
          "entry value survives the round trip");
    CHECK([[backEntries objectForKey:@"bangla"] isEqualToString:@"বাংলা"],
          "second entry survives the round trip");
    CHECK([backCounts count] == [counts count], "all learned counts survive");
    CHECK([[backCounts objectForKey:@"ঢাকা"] unsignedIntegerValue] == 12,
          "count value survives the round trip");
    CHECK([[parsed objectForKey:@"legacy"] boolValue] == NO,
          "current format is not reported as legacy");

    SECTION("stable ordering");
    NSString *again = [UserDictionary textForAutoCorrectEntries:entries
                                                   learnedCounts:counts
                                                      appVersion:@"2.0.6"];
    CHECK([text isEqualToString:again], "export is byte-stable for same input");

    SECTION("legacy two-column format");
    NSDictionary *legacy = parse(@"ami আমি\nbangla বাংলা\n");
    CHECK(legacy != nil, "legacy file imports");
    CHECK([[legacy objectForKey:@"legacy"] boolValue] == YES,
          "legacy rows are flagged");
    CHECK([[[legacy objectForKey:@"autocorrect"] objectForKey:@"ami"]
              isEqualToString:@"আমি"],
          "legacy key and value split correctly");
    CHECK([[legacy objectForKey:@"learned"] count] == 0,
          "legacy file contributes no learned rows");

    SECTION("comments, blanks and CRLF");
    NSDictionary *messy = parse(@"# a comment\r\n"
                                @"\r\n"
                                @"// another comment\r\n"
                                @"autocorrect\tami\tআমি\r\n"
                                @"\r\n"
                                @"learned\tঢাকা\t5\r\n");
    CHECK(messy != nil, "messy file still parses");
    CHECK([[messy objectForKey:@"autocorrect"] count] == 1,
          "comments and blank lines are skipped");
    CHECK([[[messy objectForKey:@"learned"] objectForKey:@"ঢাকা"]
              unsignedIntegerValue] == 5,
          "learned row read through CRLF");

    SECTION("malformed input is rejected rather than half-applied");
    CHECK(parse(@"") == nil, "empty text is not a dictionary");
    CHECK(parse(@"# only comments\n\n") == nil, "comment-only text is rejected");
    CHECK(parse(@"autocorrect\t\tvalue\n") == nil,
          "row with an empty key is rejected");
    CHECK(parse(@"learned\tঢাকা\tnotanumber\n") == nil,
          "non-numeric learned value is rejected");
    CHECK(parse(@"learned\tঢাকা\t0\n") == nil,
          "zero count is rejected as noise");
    NSDictionary *onlyLegacyBad = parse(@"singlelinewithoutspace\n");
    CHECK(onlyLegacyBad == nil, "row with no separator is rejected");

    SECTION("tabs cannot corrupt the format");
    NSDictionary *nasty = [NSDictionary dictionaryWithObjectsAndKeys:
        @"has\ttab", @"bad\tkey", nil];
    NSString *nastyText = [UserDictionary textForAutoCorrectEntries:nasty
                                                       learnedCounts:nil
                                                          appVersion:@"2.0.6"];
    NSDictionary *nastyBack = parse(nastyText);
    CHECK(nastyBack != nil, "export with a tab in the key still parses");
    NSDictionary *nastyEntries = [nastyBack objectForKey:@"autocorrect"];
    // Tabs in either column become spaces, so a row always has exactly two
    // separators and a value can never be silently truncated or merged.
    CHECK([nastyEntries objectForKey:@"bad key"] != nil,
          "tab in key is normalised to a space");
    CHECK([[nastyEntries objectForKey:@"bad key"] isEqualToString:@"has tab"],
          "tab in value is normalised to a space, not dropped");
    CHECK([nastyText rangeOfString:@"bad\tkey"].location == NSNotFound,
          "no raw tab survives inside a key");

    SECTION("writing to disk");
    NSString *path = [NSTemporaryDirectory()
        stringByAppendingPathComponent:@"avro-userdict-test.dict"];
    NSError *error = nil;
    CHECK([UserDictionary writeText:text toPath:path error:&error],
          "write reports success");
    CHECK(error == nil, "no error on a good write");
    NSString *readBack =
        [NSString stringWithContentsOfFile:path
                                  encoding:NSUTF8StringEncoding
                                     error:NULL];
    CHECK([readBack isEqualToString:text], "file content matches what we wrote");
    CHECK(parse(readBack) != nil, "the written file is importable");
    [[NSFileManager defaultManager] removeItemAtPath:path error:NULL];
    CHECK([UserDictionary writeText:@"" toPath:path error:NULL] == NO,
          "writing empty text fails rather than truncating a file");
  }
  int rc = test_report("test_user_dictionary");
  [pool release];
  return rc;
}
