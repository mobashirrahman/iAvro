#import <Foundation/Foundation.h>

#import "AvroParser.h"
#import "Database.h"
#import "TestHarness.h"

// Measures "input perturbation" as a way to survive roman typos without a
// roman-keyed word list. Instead of searching a word index for a near match,
// generate plausible corrections of what the user typed and run the ordinary
// exact lookup for each. Used only as a fallback when the exact lookup finds
// little, so correctly spelled input pays nothing.
//
// This measures whether that is worth building before building it.

static NSArray *Variants(NSString *term) {
  NSMutableArray *out = [NSMutableArray arrayWithCapacity:32];
  NSMutableSet *seen = [NSMutableSet setWithObject:term];
  NSUInteger len = [term length];

  // Letters that Avro users actually confuse. Kept small on purpose: a full
  // alphabet substitution set would be far too slow.
  NSArray *vowels = [NSArray arrayWithObjects:@"a", @"e", @"i", @"o", @"u", nil];
  NSArray *confs = [NSArray arrayWithObjects:@"h", @"n", @"N", @"s", @"S",
                                              @"t", @"T", @"y", @"r", @"b",
                                              @"v", @"o", nil];

  void (^add)(NSString *) = ^(NSString *s) {
    if ([s length] > 0 && ![seen containsObject:s]) {
      [seen addObject:s];
      [out addObject:s];
    }
  };

  // 1. Collapse a doubled letter: kothha -> kotha, jono -> jonno.
  for (NSUInteger i = 1; i < len; i++) {
    unichar c = [term characterAtIndex:i];
    if (c == [term characterAtIndex:i - 1]) {
      add([term stringByReplacingCharactersInRange:NSMakeRange(i, 1)
                                          withString:@""]);
      break;
    }
  }

  // 2. Swap an adjacent pair: basngladesh -> bangladesh.
  for (NSUInteger i = 0; i + 1 < len; i++) {
    unichar a = [term characterAtIndex:i];
    unichar b = [term characterAtIndex:i + 1];
    if (a == b) {
      continue;
    }
    NSString *swappedPair = [NSString stringWithFormat:@"%C%C", b, a];
    add([term stringByReplacingCharactersInRange:NSMakeRange(i, 2)
                                      withString:swappedPair]);
  }

  // 3. Substitute one letter with a phonetically confusable one.
  for (NSUInteger i = 0; i < len; i++) {
    NSString *current = [term substringWithRange:NSMakeRange(i, 1)];
    for (NSString *v in confs) {
      if ([v isEqualToString:current]) {
        continue;
      }
      add([term stringByReplacingCharactersInRange:NSMakeRange(i, 1)
                                        withString:v]);
    }
  }

  // 4. Delete a letter: mostly the hasanta marker 'h'.
  for (NSUInteger i = 0; i < len; i++) {
    NSString *current = [term substringWithRange:NSMakeRange(i, 1)];
    if (![current isEqualToString:@"h"]) {
      continue;
    }
    add([term stringByReplacingCharactersInRange:NSMakeRange(i, 1)
                                       withString:@""]);
  }

  // 5. Insert a vowel or 'h': basha -> bhasha, sesh -> shesh.
  for (NSUInteger i = 0; i <= len; i++) {
    for (NSString *v in confs) {
      if (![v isEqualToString:@"h"] && ![vowels containsObject:v]) {
        continue;
      }
      NSMutableString *inserted = [term mutableCopy];
      [inserted insertString:v atIndex:i];
      add(inserted);
      [inserted release];
    }
  }

  return out;
}

int main(void) {
  NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
  @autoreleasepool {
    [[NSUserDefaults standardUserDefaults] setBool:YES forKey:@"IncludeDictionary"];
    AvroParser *parser = [AvroParser sharedInstance];
    Database *db = [Database sharedInstance];

    SECTION("recovery rate on single-typo inputs");
    NSArray *cases = [NSArray arrayWithObjects:
        @"mii", @"ami",
        @"tummi", @"tumi",
        @"banglaa", @"bangla",
        @"kothha", @"kotha",
        @"bhlao", @"bhalo",
        @"dhakka", @"dhaka",
        @"basngladesh", @"bangladesh",
        @"basha", @"bhasha",
        @"sunno", @"shunno",
        @"prathom", @"prothom",
        @"kemon", @"kemono",
        @"ditio", @"ditiyo",
        @"sesh", @"shesh",
        @"jono", @"jonno",
        nil];

    NSUInteger recovered = 0, total = 0, worstTries = 0, totalVariants = 0;
    for (NSUInteger i = 0; i < [cases count]; i += 2) {
      NSString *typo = [cases objectAtIndex:i];
      NSString *intended = [cases objectAtIndex:i + 1];
      NSString *want = [parser parse:intended];
      total++;

      NSArray *exact = [db find:typo];
      NSUInteger tries = 0;
      BOOL found = [exact containsObject:want];
      if (found) {
        printf("       %-13s exact already works\n", [typo UTF8String]);
        continue;
      }

      for (NSString *variant in Variants(typo)) {
        tries++;
        if ([[db find:variant] containsObject:want]) {
          found = YES;
          break;
        }
      }
      totalVariants += tries;
      if (found) {
        recovered++;
      }
      if (tries > worstTries) {
        worstTries = tries;
      }
      printf("       %-13s -> %-11s after %-3lu variants\n",
             [typo UTF8String], found ? "RECOVERED" : "still missing",
             (unsigned long)tries);
    }
    printf("\n       recovered %lu/%lu typos; worst case %lu lookups; "
           "mean %.1f per rescued word\n",
           (unsigned long)recovered, (unsigned long)total,
           (unsigned long)worstTries,
           recovered ? (double)totalVariants / recovered : 0.0);
  }
  [pool release];
  return 0;
}
