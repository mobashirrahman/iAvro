#import <Foundation/Foundation.h>

#import "AvroParser.h"
#import "Database.h"
#import "NSString+Levenshtein.h"
#import "TestHarness.h"

// Distinguishes the two failure modes that fuzzy retrieval is supposed to fix:
//   A) the intended word is absent from the candidate list -> retrieval gap,
//      which needs a roman index.
//   B) the intended word is present but not ranked first -> ranking gap,
//      which frequency weighting can fix far more cheaply.

int main(void) {
  NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
  @autoreleasepool {
    [[NSUserDefaults standardUserDefaults] setBool:YES forKey:@"IncludeDictionary"];
    [[NSUserDefaults standardUserDefaults] setBool:YES forKey:@"EnableSuggestions"];

    AvroParser *parser = [AvroParser sharedInstance];
    Database *db = [Database sharedInstance];

    SECTION("is the intended word retrieved, and where does it rank?");

    NSArray *cases = [NSArray arrayWithObjects:
        // typo, intended roman
        @"mii",      @"ami",
        @"tummi",    @"tumi",
        @"banglaa",  @"bangla",
        @"kothha",   @"kotha",
        @"bhlao",    @"bhalo",
        @"dhakka",   @"dhaka",
        @"basngladesh", @"bangladesh",
        @"basha",    @"bhasha",
        @"sunno",    @"shunno",
        @"prathom",  @"prothom",
        @"kemon",    @"kemono",
        @"ditio",    @"ditiyo",
        @"sesh",     @"shesh",
        @"jono",     @"jonno",
        nil];

    NSUInteger retrievalGaps = 0;
    NSUInteger rankingGaps = 0;
    NSUInteger fine = 0;

    for (NSUInteger i = 0; i < [cases count]; i += 2) {
      NSString *typo = [cases objectAtIndex:i];
      NSString *intended = [cases objectAtIndex:i + 1];
      NSString *want = [parser parse:intended];

      NSArray *hits = [db find:typo];
      NSUInteger rank = [hits indexOfObject:want];

      const char *verdict;
      if (rank == NSNotFound) {
        verdict = "RETRIEVAL GAP (absent)";
        retrievalGaps++;
      } else if (rank > 0) {
        verdict = "RANKING GAP (present, not first)";
        rankingGaps++;
      } else {
        verdict = "fine (rank 0)";
        fine++;
      }
      printf("       %-12s want=%-12s hits=%-3lu rank=%-3s %s\n",
             [typo UTF8String], [want UTF8String], (unsigned long)[hits count],
             rank == NSNotFound ? "-" : [[NSString stringWithFormat:@"%lu", (unsigned long)rank] UTF8String],
             verdict);
    }

    printf("\n       fine=%lu  ranking gaps=%lu  retrieval gaps=%lu\n",
           (unsigned long)fine, (unsigned long)rankingGaps,
           (unsigned long)retrievalGaps);
    printf("       -> A roman index is only required for retrieval gaps "
           "(%lu of %lu).\n",
           (unsigned long)retrievalGaps,
           (unsigned long)(retrievalGaps + rankingGaps + fine));
  }
  [pool release];
  return 0;
}
