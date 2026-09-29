//
//  UserDictionary.m
//  Avro Keyboard
//

#import "UserDictionary.h"

static NSString *const kRowAutoCorrect = @"autocorrect";
static NSString *const kRowLearned = @"learned";

@implementation UserDictionary

+ (NSString *)textForAutoCorrectEntries:(NSDictionary *)entries
                          learnedCounts:(NSDictionary *)counts
                             appVersion:(NSString *)version {
  NSMutableString *out = [NSMutableString string];
  [out appendFormat:@"# Avro Keyboard user dictionary\n"];
  [out appendFormat:@"# app-version %@\n", version ? version : @"unknown"];
  [out appendString:@"# Format: kind<TAB>key<TAB>value\n"];
  [out appendString:@"#   autocorrect<TAB>roman-term<TAB>replacement\n"];
  [out appendString:@"#   learned<TAB>word<TAB>times-committed\n"];
  [out appendString:@"# Lines starting with # are comments.\n"];

  // Sorted so the file is stable and diffs cleanly.
  NSArray *autoCorrectTerms =
      [entries.allKeys sortedArrayUsingSelector:@selector(compare:)];
  for (NSString *term in autoCorrectTerms) {
    NSString *value = [entries objectForKey:term];
    if (![term length] || ![value length]) {
      continue;
    }
    // Tabs or newlines would break the row format.
    NSString *safeTerm = [term stringByReplacingOccurrencesOfString:@"\t"
                                                        withString:@" "];
    NSString *safeValue = [value stringByReplacingOccurrencesOfString:@"\t"
                                                          withString:@" "];
    [out appendFormat:@"%@\t%@\t%@\n", kRowAutoCorrect, safeTerm, safeValue];
  }

  NSArray *words = [counts.allKeys sortedArrayUsingSelector:@selector(compare:)];
  for (NSString *word in words) {
    NSNumber *count = [counts objectForKey:word];
    if (![word length] || ![count unsignedIntegerValue]) {
      continue;
    }
    NSString *safeWord = [word stringByReplacingOccurrencesOfString:@"\t"
                                                         withString:@" "];
    [out appendFormat:@"%@\t%@\t%@\n", kRowLearned, safeWord, count];
  }
  return out;
}

+ (NSDictionary *)parseText:(NSString *)text {
  if ([text length] == 0) {
    return nil;
  }
  NSMutableDictionary *autoCorrect = [NSMutableDictionary dictionary];
  NSMutableDictionary *learned = [NSMutableDictionary dictionary];
  BOOL legacy = NO;
  BOOL sawAnyRow = NO;

  NSCharacterSet *whitespace = [NSCharacterSet whitespaceCharacterSet];
  NSArray *lines = [text componentsSeparatedByCharactersInSet:
                                    [NSCharacterSet newlineCharacterSet]];
  for (NSString *rawLine in lines) {
    NSString *line =
        [rawLine stringByTrimmingCharactersInSet:whitespace];
    if ([line length] == 0 || [line hasPrefix:@"#"] || [line hasPrefix:@"//"]) {
      continue;
    }

    NSArray *fields = [line componentsSeparatedByString:@"\t"];
    if ([fields count] >= 3) {
      NSString *kind = [[fields objectAtIndex:0] stringByTrimmingCharactersInSet:whitespace];
      NSString *key = [[fields objectAtIndex:1] stringByTrimmingCharactersInSet:whitespace];
      // The value may itself have contained tabs, so rejoin the remainder.
      NSString *value = [[fields subarrayWithRange:
                                    NSMakeRange(2, [fields count] - 2)]
          componentsJoinedByString:@"\t"];
      if ([kind isEqualToString:kRowAutoCorrect] && [key length] &&
          [value length]) {
        [autoCorrect setObject:value forKey:key];
        sawAnyRow = YES;
      } else if ([kind isEqualToString:kRowLearned] && [key length]) {
        unsigned long long parsed = strtoull([value UTF8String], NULL, 10);
        if (parsed > 0) {
          [learned setObject:[NSNumber numberWithUnsignedLongLong:parsed]
                      forKey:key];
          sawAnyRow = YES;
        }
      }
      continue;
    }

    // Legacy two-column "term value" form: split on the first run of
    // whitespace, which is what the original importer did.
    NSRange split = [line rangeOfCharacterFromSet:whitespace];
    if (split.location == NSNotFound) {
      continue;
    }
    NSString *key = [line substringToIndex:split.location];
    NSString *value = [[line substringFromIndex:NSMaxRange(split)]
        stringByTrimmingCharactersInSet:whitespace];
    if ([key length] && [value length]) {
      [autoCorrect setObject:value forKey:key];
      sawAnyRow = YES;
      legacy = YES;
    }
  }

  if (!sawAnyRow) {
    return nil;
  }
  return [NSDictionary dictionaryWithObjectsAndKeys:
                      autoCorrect, @"autocorrect",
                      learned, @"learned",
                      [NSNumber numberWithBool:legacy], @"legacy", nil];
}

+ (BOOL)writeText:(NSString *)text
           toPath:(NSString *)path
            error:(NSError **)error {
  if ([text length] == 0 || [path length] == 0) {
    return NO;
  }
  return [text writeToFile:path
                atomically:YES
                  encoding:NSUTF8StringEncoding
                     error:error];
}

@end
