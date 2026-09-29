//
//  TypoCorrections.m
//  Avro Keyboard
//

#import "TypoCorrections.h"

// A doubled letter is the most common single typo and one extra lookup
// rescues it. Adjacent transposition was implemented and measured: because the
// wrong position is unknown, corrections have to be tried left to right, and
// the correct one is usually not among the first few. Capping at one lookup
// found 4 of 10 typos against 5 of 10 at four lookups, for 9.5 ms versus
// 19.5 ms per lookup. It does not pay for itself, so it is not attempted.
static const NSUInteger kMaxCorrections = 1;

// Below this length there is no useful correction to make, and short terms are
// usually just partially typed words.
static const NSUInteger kMinimumLength = 4;

@implementation TypoCorrections

+ (NSUInteger)maximumCorrections {
  return kMaxCorrections;
}

+ (NSArray *)correctionsForTerm:(NSString *)term {
  NSUInteger length = [term length];
  if (length < kMinimumLength) {
    return [NSArray array];
  }

  NSMutableArray *corrections = [NSMutableArray arrayWithCapacity:kMaxCorrections];
  NSMutableSet *seen = [NSMutableSet setWithObject:term];

  // 1. Collapse a doubled letter: kothha -> kotha, jono -> jonno.
  //    Only the first run, so this never produces more than one candidate.
  for (NSUInteger i = 1; i < length; i++) {
    if ([term characterAtIndex:i] != [term characterAtIndex:i - 1]) {
      continue;
    }
    NSString *collapsed = [term stringByReplacingCharactersInRange:NSMakeRange(i, 1)
                                                       withString:@""];
    if (![seen containsObject:collapsed]) {
      [seen addObject:collapsed];
      [corrections addObject:collapsed];
    }
    break;
  }

  return corrections;
}

@end
