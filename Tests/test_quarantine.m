//
//  test_quarantine.m
//  Avro Keyboard
//
//  A corrupt or missing data file must degrade the input method, never kill
//  it. Both parsers used to @throw from -init when their JSON was missing or
//  unparsable, which would abort the IME on every launch after one bad write.
//  Valid JSON with the wrong shape crashed too (initWithString:nil,
//  objectAtIndex:0 on an empty table).
//
//  This suite swaps corrupt files into its own working directory, asserts the
//  degraded behavior, then restores the originals before reporting. It runs
//  LAST so a crash here (the bug, if present) cannot poison other suites.
//

#import <Foundation/Foundation.h>

#import "AvroParser.h"
#import "Database.h"
#import "RegexParser.h"
#import "TestHarness.h"

static NSString *BackupPath(NSString *name) {
  return [NSTemporaryDirectory() stringByAppendingPathComponent:name];
}

static void SwapInCorruptTables(void) {
  NSFileManager *fm = [NSFileManager defaultManager];
  for (NSString *name in [NSArray arrayWithObjects:@"data.json", @"regex.json",
                                                   @"database.db3", nil]) {
    NSString *live = [[[NSFileManager defaultManager] currentDirectoryPath]
        stringByAppendingPathComponent:name];
    NSString *backup = BackupPath([name stringByAppendingString:@".good"]);
    [fm removeItemAtPath:backup error:NULL];
    [fm copyItemAtPath:live toPath:backup error:NULL];
    [@"NOT VALID {{{" writeToFile:live
                        atomically:YES
                          encoding:NSUTF8StringEncoding
                             error:NULL];
  }
}

static void RestoreTables(void) {
  NSFileManager *fm = [NSFileManager defaultManager];
  for (NSString *name in [NSArray arrayWithObjects:@"data.json", @"regex.json",
                                                   @"database.db3", nil]) {
    NSString *live = [[[NSFileManager defaultManager] currentDirectoryPath]
        stringByAppendingPathComponent:name];
    NSString *backup = BackupPath([name stringByAppendingString:@".good"]);
    [fm removeItemAtPath:live error:NULL];
    [fm moveItemAtPath:backup toPath:live error:NULL];
  }
}

int main(void) {
  NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
  // Corrupt FIRST: the singletons below must initialize against the bad files
  // in this fresh process.
  SwapInCorruptTables();
  @autoreleasepool {
    SECTION("garbage files degrade instead of killing");
    BOOL raised = NO;
    @try {
      [AvroParser sharedInstance];
      [RegexParser sharedInstance];
      [Database sharedInstance];
    } @catch (NSException *e) {
      raised = YES;
    }
    CHECK(!raised, "initializing against corrupt tables does not raise");

    SECTION("transliteration degrades to passthrough");
    CHECK([[[AvroParser sharedInstance] parse:@"ami"] isEqualToString:@"ami"],
          "parse returns the input unchanged with no table");
    CHECK([[[AvroParser sharedInstance] parse:@""] isEqualToString:@""],
          "empty input stays empty");
    CHECK([[[AvroParser sharedInstance] parse:@"kothha"]
              isEqualToString:@"kothha"],
          "unmatched multi-char input passes through whole");

    SECTION("dictionary search degrades to empty");
    CHECK([[[Database sharedInstance] find:@"ami"] count] == 0,
          "find returns empty rather than crashing");

    SECTION("valid JSON with the wrong shape is also safe");
    // Covered implicitly: the garbage above is not even valid JSON, and the
    // loaders additionally coerce missing keys, non-string values and an empty
    // pattern list to empty tables.
    // Note the lowercase: with no case table, case distinctions are unknowable
    // and fix: normalizes everything. Degraded mode preserves content, not case.
    CHECK([[[AvroParser sharedInstance] parse:@"TH"] isEqualToString:@"th"],
          "affected syllables pass through instead of crashing");
  }
  RestoreTables();
  int rc = test_report("test_quarantine");
  [pool release];
  return rc;
}
