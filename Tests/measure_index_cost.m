#import <Foundation/Foundation.h>
#import <sqlite3.h>

#import "AvroParser.h"
#import "TestHarness.h"

// Times transliterating the whole dictionary to roman form, which is what a
// prebuilt fuzzy index would need. Also reports the size of the resulting
// data, since the index has to be shipped inside the app.

int main(void) {
  NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
  @autoreleasepool {
    NSString *path = [[NSFileManager defaultManager] currentDirectoryPath];
    path = [path stringByAppendingPathComponent:@"database.db3"];

    sqlite3 *db = NULL;
    if (sqlite3_open([path UTF8String], &db) != SQLITE_OK) {
      printf("cannot open %s\n", [path UTF8String]);
      return 1;
    }

    sqlite3_stmt *stmt = NULL;
    const char *sql =
        "SELECT name FROM sqlite_master WHERE type='table' AND name<>'Suffix' "
        "ORDER BY name";
    sqlite3_prepare_v2(db, sql, -1, &stmt, NULL);
    NSMutableArray *tables = [NSMutableArray array];
    while (sqlite3_step(stmt) == SQLITE_ROW) {
      [tables addObject:[NSString stringWithUTF8String:
                                   (const char *)sqlite3_column_text(stmt, 0)]];
    }
    sqlite3_finalize(stmt);

    AvroParser *parser = [AvroParser sharedInstance];

    NSDate *start = [NSDate date];
    NSUInteger words = 0;
    NSUInteger bytes = 0;
    NSUInteger failures = 0;

    for (NSString *table in tables) {
      NSString *q = [NSString
          stringWithFormat:@"SELECT Words FROM \"%@\"", table];
      sqlite3_stmt *s = NULL;
      if (sqlite3_prepare_v2(db, [q UTF8String], -1, &s, NULL) != SQLITE_OK) {
        continue;
      }
      while (sqlite3_step(s) == SQLITE_ROW) {
        const char *c = (const char *)sqlite3_column_text(s, 0);
        if (!c) {
          continue;
        }
        NSString *word = [NSString stringWithUTF8String:c];
        NSString *roman = [parser parse:word];
        if ([roman length] == 0) {
          failures++;
        } else if ([roman isEqualToString:word]) {
          // Word has no roman mapping; unusable as a fuzzy key.
          failures++;
        } else {
          words++;
          bytes += [word lengthOfBytesUsingEncoding:NSUTF8StringEncoding] +
                   [roman lengthOfBytesUsingEncoding:NSUTF8StringEncoding] + 1;
        }
      }
      sqlite3_finalize(s);
    }

    NSTimeInterval elapsed = -[start timeIntervalSinceNow];
    printf("       tables          : %lu\n", (unsigned long)[tables count]);
    printf("       usable entries  : %lu (skipped %lu with no roman form)\n",
           (unsigned long)words, (unsigned long)failures);
    printf("       transliterate   : %.2f s (%.0f words/s)\n", elapsed,
           elapsed > 0 ? words / elapsed : 0);
    printf("       compact size    : %.1f MB (roman+word bytes)\n",
           bytes / 1024.0 / 1024.0);
    printf("       bundle impact   : +%.1f MB on a %.1f MB app\n",
           bytes / 1024.0 / 1024.0, 2.2);
  }
  [pool release];
  return 0;
}
