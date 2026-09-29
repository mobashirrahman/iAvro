#import <Foundation/Foundation.h>

#import "AvroParser.h"
#import "Database.h"
#import "TestHarness.h"

// The user-visible coverage metric: of the words the bundled AutoCorrect
// wordlist knows, how many can you actually get by typing the roman spelling
// that produced them? Run it with and without data/extra-words.tsv present to
// see the improvement.

int main(void) {
  NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
  @autoreleasepool {
    [[NSUserDefaults standardUserDefaults] setBool:YES forKey:@"IncludeDictionary"];
    NSDictionary *autodict =
        [NSDictionary dictionaryWithContentsOfFile:@"autodict.plist"];

    // Bangla values only, with a roman spelling that round-trips to them.
    NSMutableArray *romans = [NSMutableArray array];
    NSMutableArray *words = [NSMutableArray array];
    for (NSString *roman in autodict) {
      NSString *value = [autodict objectForKey:roman];
      if ([value length] == 0 || [value hasPrefix:@"."]) {
        continue;
      }
      BOOL bangla = NO;
      for (NSUInteger i = 0; i < [value length]; i++) {
        if ([value characterAtIndex:i] >= 0x980 &&
            [value characterAtIndex:i] <= 0x9FF) {
          bangla = YES;
          break;
        }
      }
      if (bangla) {
        [romans addObject:roman];
        [words addObject:value];
      }
    }

    NSUInteger found = 0, total = [romans count];
    NSMutableArray *misses = [NSMutableArray array];
    for (NSUInteger i = 0; i < total; i++) {
      NSString *term = [romans objectAtIndex:i];
      NSString *want = [words objectAtIndex:i];
      if ([[[Database sharedInstance] find:term] containsObject:want]) {
        found++;
      } else if (misses.count < 12) {
        [misses addObject:[NSString stringWithFormat:@"%@ -> %@",
                                                     term, want]];
      }
    }
    printf("       extra-words present: %s\n",
           [[[NSBundle mainBundle] pathForResource:@"extra-words" ofType:@"tsv"]
               length] ? "yes" : "no");
    printf("       retrievable: %lu / %lu  (%.1f%%)\n", (unsigned long)found,
           (unsigned long)total, total ? 100.0 * found / total : 0.0);
    for (NSString *miss in misses) {
      printf("         miss %s\n", [miss UTF8String]);
    }
  }
  [pool release];
  return 0;
}
