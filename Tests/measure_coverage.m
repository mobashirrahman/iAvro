#import <Foundation/Foundation.h>

#import "AvroParser.h"
#import "Database.h"
#import "TestHarness.h"

// Separates two very different problems that both look like "typo not found":
//   A) the correct spelling retrieves the word fine, so the typo really is the
//      problem, and input perturbation would help.
//   B) the correct spelling also fails, so the word is unreachable for a
//      different reason (missing from a searched table, or a parse mismatch)
//      and no amount of typo tolerance would recover it.

int main(void) {
  NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
  @autoreleasepool {
    [[NSUserDefaults standardUserDefaults] setBool:YES forKey:@"IncludeDictionary"];
    AvroParser *parser = [AvroParser sharedInstance];
    Database *db = [Database sharedInstance];

    NSArray *cases = [NSArray arrayWithObjects:
        @"mii", @"ami", @"tummi", @"tumi", @"banglaa", @"bangla",
        @"kothha", @"kotha", @"bhlao", @"bhalo", @"dhakka", @"dhaka",
        @"basngladesh", @"bangladesh", @"basha", @"bhasha", @"sunno", @"shunno",
        @"prathom", @"prothom", @"kemon", @"kemono", @"ditio", @"ditiyo",
        @"sesh", @"shesh", @"jono", @"jonno", nil];

    SECTION("does the CORRECT spelling retrieve the intended word?");
    NSUInteger typoOnly = 0, alsoCorrectFails = 0;
    for (NSUInteger i = 0; i < [cases count]; i += 2) {
      NSString *typo = [cases objectAtIndex:i];
      NSString *intended = [cases objectAtIndex:i + 1];
      NSString *want = [parser parse:intended];

      BOOL typoFinds = [[db find:typo] containsObject:want];
      BOOL correctFinds = [[db find:intended] containsObject:want];
      if (correctFinds) {
        typoOnly++;
        printf("       %-13s correct spelling finds it  -> TYPO problem\n",
               [typo UTF8String]);
      } else {
        alsoCorrectFails++;
        // Diagnose across every table the database actually loaded, not a
        // hand-written list that can drift out of date.
        NSMutableArray *holders = [NSMutableArray array];
        for (NSString *t in [db tableNames]) {
          if ([[db wordsInTable:t] containsObject:want]) {
            [holders addObject:t];
          }
        }
        printf("       %-13s correct spelling ALSO fails -> %s\n",
               [typo UTF8String],
               holders.count
                   ? [[NSString stringWithFormat:@"held in table(s) %@ but never searched",
                                                 [holders componentsJoinedByString:@","]] UTF8String]
                   : "genuinely absent from the dictionary");
      }
    }
    printf("\n       %lu are genuine typo problems; %lu are retrieval-coverage "
           "problems.\n",
           (unsigned long)typoOnly, (unsigned long)alsoCorrectFails);
  }
  [pool release];
  return 0;
}
