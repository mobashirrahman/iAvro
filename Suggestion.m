//
//  AvroKeyboard
//
//  Created by Rifat Nabi on 6/28/12.
//  Copyright (c) 2012 OmicronLab. All rights reserved.
//

#import "Suggestion.h"
#import "AutoCorrect.h"
#import "AvroParser.h"
#import "CacheManager.h"
#import "Database.h"
#import "NSString+Levenshtein.h"
#import "RegexKitLite.h"
#import "RegexParser.h"
#import "SettingsKeys.h"

static Suggestion *sharedInstance = nil;

@implementation Suggestion

+ (Suggestion *)sharedInstance {
  if (sharedInstance == nil) {
    [[self alloc] init]; // assignment not done here, see allocWithZone
  }
  return sharedInstance;
}

+ (id)allocWithZone:(NSZone *)zone {

  if (sharedInstance == nil) {
    sharedInstance = [super allocWithZone:zone];
    return sharedInstance; // assignment and return on first allocation
  }
  return nil; // on subsequent allocation attempts return nil
}

- (id)copyWithZone:(NSZone *)zone {
  return self;
}

- (id)retain {
  return self;
}

- (oneway void)release {
  // do nothing
}

- (id)autorelease {
  return self;
}

- (NSUInteger)retainCount {
  return NSUIntegerMax; // This is sooo not zero
}

- (id)init {
  self = [super init];
  if (self) {
    _suggestions = [[NSMutableArray alloc] initWithCapacity:0];
    _cachedPreferenceFlags = -1;
  }
  return self;
}

- (void)dealloc {
  [_suggestions release];
  [super dealloc];
}

// AutoCorrect + ranked dictionary words for a term, memoized in the phonetic
// cache. A cached empty array counts as a hit, so unknown words aren't
// re-scanned on every keystroke.
- (NSArray *)wordsForTerm:(NSString *)term {
  NSArray *cached = [[CacheManager sharedInstance] arrayForKey:term];
  if (cached) {
    return cached;
  }

  NSMutableArray *words = [NSMutableArray arrayWithCapacity:0];
  NSString *autoCorrect = nil;
  // Suggestions form AutoCorrect
  if ([[NSUserDefaults standardUserDefaults]
          boolForKey:kEnableAutoCorrectDefaultsKey]) {
    autoCorrect = [[AutoCorrect sharedInstance] find:term];
    if (autoCorrect) {
      [words addObject:autoCorrect];
    }
  }

  // Suggestions from Dictionary
  if ([[NSUserDefaults standardUserDefaults]
          boolForKey:kEnableSuggestionsDefaultsKey]) {
    NSArray *dicList = [[Database sharedInstance] find:term];
    if (dicList) {
      // Remove autoCorrect if it is already in the dictionary
      if (autoCorrect && [dicList containsObject:autoCorrect]) {
        [words removeObject:autoCorrect];
      }
      // Compute each edit distance once, then sort by cached value
      NSString *parsed = [[AvroParser sharedInstance] parse:term];
      NSMutableDictionary *distances =
          [NSMutableDictionary dictionaryWithCapacity:[dicList count]];
      for (NSString *word in dicList) {
        int dist = [parsed computeLevenshteinDistanceWithString:word];
        [distances setObject:[NSNumber numberWithInt:dist] forKey:word];
      }
      NSArray *sortedDicList = [dicList
          sortedArrayUsingComparator:^NSComparisonResult(id left, id right) {
            int dist1 = [[distances objectForKey:left] intValue];
            int dist2 = [[distances objectForKey:right] intValue];
            if (dist1 < dist2) {
              return NSOrderedAscending;
            } else if (dist1 > dist2) {
              return NSOrderedDescending;
            } else {
              return [(NSString *)left compare:(NSString *)right];
            }
          }];
      [words addObjectsFromArray:sortedDicList];
    }
  }

  NSArray *result = [[words copy] autorelease];
  [[CacheManager sharedInstance] setArray:result forKey:term];
  return result;
}

// Cached word lists depend on which sources are consulted, so drop them when
// either toggle changes. AutoCorrect entries also feed these lists and are
// dropped through AutoCorrect's own entriesDidChange.
- (void)invalidateCacheIfPreferencesChanged {
  NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
  NSInteger flags = ([defaults boolForKey:kEnableAutoCorrectDefaultsKey] ? 1 : 0) |
                    ([defaults boolForKey:kEnableSuggestionsDefaultsKey] ? 2 : 0);
  if (flags != _cachedPreferenceFlags) {
    [[CacheManager sharedInstance] removeAllArrays];
    _cachedPreferenceFlags = flags;
  }
}

- (NSArray *)getList:(NSString *)term {
  [_suggestions removeAllObjects];
  if (!term || [term length] == 0) {
    return [[_suggestions copy] autorelease];
  }

  // Suggestions from Default Parser
  NSString *paresedString = [[AvroParser sharedInstance] parse:term];
  if ([[NSUserDefaults standardUserDefaults] boolForKey:@"IncludeDictionary"]) {
    [self invalidateCacheIfPreferencesChanged];
    [_suggestions addObjectsFromArray:[self wordsForTerm:term]];

    // Suggestions with Suffix
    if ([[NSUserDefaults standardUserDefaults]
            boolForKey:kEnableSuggestionsDefaultsKey]) {
      NSInteger i;
      BOOL alreadySelected = FALSE;
      // NOTE: no removeAllBase here. The base cache is bounded inside
      // CacheManager; nuking it every keystroke dropped reverse-suffix
      // entries written by the previous term before the user could select.
      for (i = [term length] - 1; i > 0; --i) {
        NSString *suffix = [[Database sharedInstance]
            banglaForSuffix:[[term substringFromIndex:i] lowercaseString]];
        if (suffix && [suffix length] > 0) {
          NSString *base = [term substringToIndex:i];
          // Usually a cache hit (the base was typed on the way here), but the
          // cache evicts, so compute it on a miss rather than dropping
          // suffix suggestions.
          NSArray *cached = [self wordsForTerm:base];
          NSString *selected = nil;
          if (!alreadySelected) {
            // Base user selection
            selected = [[CacheManager sharedInstance] stringForKey:base];
          }
          if (cached) {
            for (NSString *item in cached) {
              if (!item || [item length] == 0) {
                continue;
              }
              // Skip AutoCorrect English Entry
              if ([base isEqualToString:item]) {
                continue;
              }
              NSString *word;
              // Again saving humanity cause I'm Superman, no I'm not drunk or
              // on weed :D
              NSInteger cutPos = [item length] - 1;

              NSString *itemRMC = [item
                  substringFromIndex:cutPos]; // RMC is Right Most Character
              NSString *suffixLMC =
                  [suffix substringToIndex:1]; // LMC is Left Most Character
              // BEGIN :: This part was taken from http://d.pr/zTmF
              if ([self isVowel:itemRMC] && [self isKar:suffixLMC]) {
                word = [NSString stringWithFormat:@"%@\u09df%@", item, suffix];
              } else {
                if ([itemRMC isEqualToString:@"\u09ce"]) {
                  word = [NSString
                      stringWithFormat:@"%@\u09a4%@",
                                       [item substringToIndex:cutPos], suffix];
                } else if ([itemRMC isEqualToString:@"\u0982"]) {
                  word = [NSString
                      stringWithFormat:@"%@\u0999%@",
                                       [item substringToIndex:cutPos], suffix];
                } else {
                  word = [NSString stringWithFormat:@"%@%@", item, suffix];
                }
              }
              // END

              // Reverse Suffix Caching
              [[CacheManager sharedInstance]
                  setBase:[NSArray arrayWithObjects:base, item, nil]
                   forKey:word];

              // Check that the WORD is not already in the list
              if (![_suggestions containsObject:word]) {
                // Intelligent Selection
                if (!alreadySelected && selected &&
                    [item isEqualToString:selected]) {
                  if (![[CacheManager sharedInstance] stringForKey:term]) {
                    [[CacheManager sharedInstance] setString:word forKey:term];
                  }
                  alreadySelected = TRUE;
                }
                [_suggestions addObject:word];
              }
            }
          }
        }
      }
    }
  }

  // All-caps input also offers the letters spelled out (ABC -> এবিসি)
  NSString *abbreviation = [self abbreviationForTerm:term];
  if (abbreviation && ![_suggestions containsObject:abbreviation]) {
    [_suggestions addObject:abbreviation];
  }

  if ([_suggestions containsObject:paresedString] == NO) {
    [_suggestions addObject:paresedString];
  }

  [self promoteLearnedChoicesForTerm:term];

  return [[_suggestions copy] autorelease];
}

// Reorders candidates using what this user has actually committed before, the
// same idea as the Japanese IME's conversion learning. Terms the user has never
// committed are left exactly as they were, so the common case is unchanged.
//
// Two signals, in order:
//   1. the last word committed for this term (weight.plist), then
//   2. how often each candidate word has been committed at all
//      (weight-counts.plist), which acts as a personal unigram frequency.
// Candidates with no history keep their incoming order, so the distance
// ranking computed in wordsForTerm: is still the tiebreaker.
- (void)promoteLearnedChoicesForTerm:(NSString *)term {
  if (!term || [_suggestions count] < 2) {
    return;
  }
  if (![[NSUserDefaults standardUserDefaults] boolForKey:@"IncludeDictionary"]) {
    return;
  }

  CacheManager *cache = [CacheManager sharedInstance];
  NSString *lastChosen = [cache stringForKey:term];
  if (lastChosen && [lastChosen length] == 0) {
    lastChosen = nil;
  }

  NSArray *original = [[_suggestions copy] autorelease];
  NSMutableArray *head = [NSMutableArray arrayWithCapacity:1];
  NSMutableArray *tail = [NSMutableArray arrayWithCapacity:[original count]];
  for (NSString *word in original) {
    if (lastChosen && [word isEqualToString:lastChosen]) {
      if ([head count] == 0) {
        [head addObject:word];
        continue;
      }
    }
    [tail addObject:word];
  }
  if ([head count] == 0) {
    return;  // nothing learned for this term; leave the order untouched
  }

  // Stable sort the remainder by personal frequency, so words the user never
  // picks keep the distance order they arrived in.
  [tail sortUsingComparator:^NSComparisonResult(NSString *a, NSString *b) {
    NSUInteger fa = [cache countForKey:a];
    NSUInteger fb = [cache countForKey:b];
    if (fa == fb) {
      return NSOrderedSame;
    }
    return fa < fb ? NSOrderedDescending : NSOrderedAscending;
  }];

  [_suggestions removeAllObjects];
  [_suggestions addObjectsFromArray:head];
  [_suggestions addObjectsFromArray:tail];
}

// Ported from Windows Avro (clsAbbreviation): English letter names in
// Bangla. Only for terms with no lowercase letters and at least one letter.
- (NSString *)abbreviationForTerm:(NSString *)term {
  static NSDictionary *names = nil;
  if (!names) {
    names = [[NSDictionary alloc] initWithObjectsAndKeys:
        @"এ", @"A", @"বি", @"B", @"সি", @"C", @"ডি", @"D", @"ই", @"E",
        @"এফ", @"F", @"জি", @"G", @"এইচ", @"H", @"আই", @"I", @"জে", @"J",
        @"কে", @"K", @"এল", @"L", @"এম", @"M", @"এন", @"N", @"ও", @"O",
        @"পি", @"P", @"কিউ", @"Q", @"আর", @"R", @"এস", @"S", @"টি", @"T",
        @"ইউ", @"U", @"ভি", @"V", @"ডব্লিউ", @"W", @"এক্স", @"X",
        @"ওয়াই", @"Y", @"জেড", @"Z",
        @"০", @"0", @"১", @"1", @"২", @"2", @"৩", @"3", @"৪", @"4",
        @"৫", @"5", @"৬", @"6", @"৭", @"7", @"৮", @"8", @"৯", @"9", nil];
  }
  if (![term isEqualToString:[term uppercaseString]] ||
      [term rangeOfCharacterFromSet:[NSCharacterSet uppercaseLetterCharacterSet]]
              .location == NSNotFound) {
    return nil;
  }
  NSMutableString *result = [NSMutableString stringWithCapacity:[term length] * 2];
  NSUInteger i;
  for (i = 0; i < [term length]; i++) {
    NSString *c = [term substringWithRange:NSMakeRange(i, 1)];
    NSString *name = [names objectForKey:c];
    [result appendString:name ? name : c];
  }
  return result;
}

- (BOOL)isKar:(NSString *)letter {
  return [letter isMatchedByRegex:@"^["
                                  @"\u09be\u09bf\u09c0\u09c1\u09c2\u09c3\u09c7"
                                  @"\u09c8\u09cb\u09cc\u09c4]$"];
}

- (BOOL)isVowel:(NSString *)letter {
  return [letter
      isMatchedByRegex:@"^["
                       @"\u0985\u0986\u0987\u0988\u0989\u098a\u098b\u098f\u0990"
                       @"\u0993\u0994\u098c\u09e1\u09be\u09bf\u09c0\u09c1\u09c2"
                       @"\u09c3\u09c7\u09c8\u09cb\u09cc]$"];
}

@end
