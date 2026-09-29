//
//  AvroKeyboard
//
//  Created by Rifat Nabi on 6/28/12.
//  Copyright (c) 2012 OmicronLab. All rights reserved.
//

#import "Database.h"
#import "FMDatabase.h"
#import "RegexKitLite.h"
#import "RegexParser.h"
#import "TypoCorrections.h"


static Database *sharedInstance = nil;

@implementation Database

+ (Database *)sharedInstance {
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
    _db = [[NSMutableDictionary alloc] initWithCapacity:0];
    _suffix = [[NSMutableDictionary alloc] initWithCapacity:0];

    NSAutoreleasePool *loopPool = [[NSAutoreleasePool alloc] init];

    NSString *filePath = [[NSBundle mainBundle] pathForResource:@"database"
                                                         ofType:@"db3"];
    FMDatabase *sqliteDb = [FMDatabase databaseWithPath:filePath];
    [sqliteDb open];

    [self loadTableWithName:@"A" fromDatabase:sqliteDb];
    [self loadTableWithName:@"AA" fromDatabase:sqliteDb];
    [self loadTableWithName:@"B" fromDatabase:sqliteDb];
    [self loadTableWithName:@"BH" fromDatabase:sqliteDb];
    [self loadTableWithName:@"C" fromDatabase:sqliteDb];
    [self loadTableWithName:@"CH" fromDatabase:sqliteDb];
    [self loadTableWithName:@"D" fromDatabase:sqliteDb];
    [self loadTableWithName:@"Dd" fromDatabase:sqliteDb];
    [self loadTableWithName:@"Ddh" fromDatabase:sqliteDb];
    [self loadTableWithName:@"Dh" fromDatabase:sqliteDb];
    [self loadTableWithName:@"E" fromDatabase:sqliteDb];
    [self loadTableWithName:@"G" fromDatabase:sqliteDb];
    [self loadTableWithName:@"Gh" fromDatabase:sqliteDb];
    [self loadTableWithName:@"H" fromDatabase:sqliteDb];
    [self loadTableWithName:@"I" fromDatabase:sqliteDb];
    [self loadTableWithName:@"II" fromDatabase:sqliteDb];
    [self loadTableWithName:@"J" fromDatabase:sqliteDb];
    [self loadTableWithName:@"JH" fromDatabase:sqliteDb];
    [self loadTableWithName:@"K" fromDatabase:sqliteDb];
    [self loadTableWithName:@"KH" fromDatabase:sqliteDb];
    [self loadTableWithName:@"Khandatta" fromDatabase:sqliteDb];
    [self loadTableWithName:@"L" fromDatabase:sqliteDb];
    [self loadTableWithName:@"M" fromDatabase:sqliteDb];
    [self loadTableWithName:@"N" fromDatabase:sqliteDb];
    [self loadTableWithName:@"NGA" fromDatabase:sqliteDb];
    [self loadTableWithName:@"NN" fromDatabase:sqliteDb];
    [self loadTableWithName:@"NYA" fromDatabase:sqliteDb];
    [self loadTableWithName:@"O" fromDatabase:sqliteDb];
    [self loadTableWithName:@"OI" fromDatabase:sqliteDb];
    [self loadTableWithName:@"OU" fromDatabase:sqliteDb];
    [self loadTableWithName:@"P" fromDatabase:sqliteDb];
    [self loadTableWithName:@"PH" fromDatabase:sqliteDb];
    [self loadTableWithName:@"R" fromDatabase:sqliteDb];
    [self loadTableWithName:@"RR" fromDatabase:sqliteDb];
    [self loadTableWithName:@"RRH" fromDatabase:sqliteDb];
    [self loadTableWithName:@"RRI" fromDatabase:sqliteDb];
    [self loadTableWithName:@"S" fromDatabase:sqliteDb];
    [self loadTableWithName:@"SH" fromDatabase:sqliteDb];
    [self loadTableWithName:@"SS" fromDatabase:sqliteDb];
    [self loadTableWithName:@"T" fromDatabase:sqliteDb];
    [self loadTableWithName:@"TH" fromDatabase:sqliteDb];
    [self loadTableWithName:@"TT" fromDatabase:sqliteDb];
    [self loadTableWithName:@"TTH" fromDatabase:sqliteDb];
    [self loadTableWithName:@"U" fromDatabase:sqliteDb];
    [self loadTableWithName:@"UU" fromDatabase:sqliteDb];
    [self loadTableWithName:@"Y" fromDatabase:sqliteDb];
    [self loadTableWithName:@"Z" fromDatabase:sqliteDb];

    [self loadSuffixTableFromDatabase:sqliteDb];

    [sqliteDb close];

    [self loadExtraWords];

    [loopPool release];
  }
  return self;
}

- (void)dealloc {
  [_db release];
  [_suffix release];
  [super dealloc];
}

- (void)loadTableWithName:(NSString *)name fromDatabase:(FMDatabase *)sqliteDb {
  NSMutableArray *items = [[NSMutableArray alloc] init];

  FMResultSet *results = [sqliteDb
      executeQuery:[NSString stringWithFormat:@"SELECT * FROM %@", name]];
  while ([results next]) {
    [items addObject:[results stringForColumn:@"Words"]];
  }

  /*
   NSLog(@"-----------------------------------------------------------------");
   NSLog(@"%d items added to key %@", count, name);
   NSLog(@"-----------------------------------------------------------------");
   */

  [_db setObject:items forKey:[name lowercaseString]];

  [results close];
  [items release];
}

// Words that the bundled AutoCorrect wordlist knows but database.db3 does not
// live in data/extra-words.tsv, generated by tools/build_extra_words.py. They
// are merged into the same in-memory tables so lookup needs no extra path.
- (void)loadExtraWords {
  NSString *path = [[NSBundle mainBundle] pathForResource:@"extra-words"
                                                   ofType:@"tsv"];
  NSString *contents = path ? [NSString stringWithContentsOfFile:path
                                                         encoding:NSUTF8StringEncoding
                                                            error:NULL]
                            : nil;
  if ([contents length] == 0) {
    return;
  }

  NSCharacterSet *whitespace = [NSCharacterSet whitespaceCharacterSet];
  for (NSString *rawLine in [contents componentsSeparatedByCharactersInSet:
                                             [NSCharacterSet newlineCharacterSet]]) {
    NSString *line = [rawLine stringByTrimmingCharactersInSet:whitespace];
    if ([line length] == 0 || [line hasPrefix:@"#"]) {
      continue;
    }
    NSRange tab = [line rangeOfString:@"\t"];
    if (tab.location == NSNotFound) {
      continue;
    }
    NSString *table = [[line substringToIndex:tab.location]
        stringByTrimmingCharactersInSet:whitespace];
    NSString *word = [[line substringFromIndex:NSMaxRange(tab)]
        stringByTrimmingCharactersInSet:whitespace];
    if ([table length] == 0 || [word length] == 0) {
      continue;
    }
    NSString *key = [table lowercaseString];
    NSMutableArray *bucket = [_db objectForKey:key];
    if (!bucket) {
      bucket = [NSMutableArray array];
      [_db setObject:bucket forKey:key];
    }
    if (![bucket containsObject:word]) {
      [bucket addObject:word];
    }
  }
}

- (NSArray*)wordsInTable:(NSString*)table {  if (!table) {
    return nil;
  }
  return [_db objectForKey:[table lowercaseString]];
}

- (NSArray*)tableNames {
  return [_db allKeys];
}

- (void)loadSuffixTableFromDatabase:(FMDatabase *)sqliteDb {
  FMResultSet *results = [sqliteDb
      executeQuery:[NSString stringWithFormat:@"SELECT * FROM Suffix"]];
  while ([results next]) {
    [_suffix setObject:[results stringForColumn:@"Bangla"]
                forKey:[results stringForColumn:@"English"]];
  }
  [results close];
}

// A term that already returns several candidates is trusted as typed. Below
// this many, the term is either a typo or an unusual romanisation, so a few
// cheap corrections are consulted as well. Measured: gating on "no results at
// all" almost never fires, because a mistyped term usually still matches
// *something*, just not the word that was meant.
static const NSUInteger kWeakResultCount = 3;

- (NSArray *)find:(NSString *)term {
  if (!term || [term length] == 0) {
    return [NSArray array];
  }

  NSMutableArray *matches =
      [[[self searchExactly:term] mutableCopy] autorelease];
  if ([matches count] >= kWeakResultCount) {
    return matches;
  }

  // Try a small number of cheap corrections, stopping at the first that finds
  // something, and keep those results too: a mistyped term often matches a
  // wrong word, and the right one is worth offering alongside it. Ranking in
  // Suggestion decides the order, so the corrected word can still surface.
  for (NSString *correction in [TypoCorrections correctionsForTerm:term]) {
    NSArray *corrected = [self searchExactly:correction];
    if ([corrected count] == 0) {
      continue;
    }
    for (NSString *word in corrected) {
      if (![matches containsObject:word]) {
        [matches addObject:word];
      }
    }
    break;
  }

  return matches;
}

- (NSArray *)searchExactly:(NSString *)term {
  // Left Most Character
  unichar lmc = [[term lowercaseString] characterAtIndex:0];
  NSString *regex = [NSString
      stringWithFormat:@"^%@$", [[RegexParser sharedInstance] parse:term]];
  NSMutableArray *tableList = [[NSMutableArray alloc] initWithCapacity:0];
  NSMutableSet *suggestions = [[NSMutableSet alloc] initWithCapacity:0];

  switch (lmc) {
  case 'a':
    [tableList
        addObjectsFromArray:[NSArray arrayWithObjects:@"a", @"aa", @"e", @"oi",
                                                      @"o", @"nya", @"y", nil]];
    break;
  case 'b':
    [tableList addObjectsFromArray:[NSArray arrayWithObjects:@"b", @"bh", nil]];
    break;
  case 'c':
    [tableList
        addObjectsFromArray:[NSArray arrayWithObjects:@"c", @"ch", @"k", nil]];
    break;
  case 'd':
    [tableList addObjectsFromArray:[NSArray arrayWithObjects:@"d", @"dh", @"dd",
                                                             @"ddh", nil]];
    break;
  case 'e':
    [tableList addObjectsFromArray:[NSArray arrayWithObjects:@"i", @"ii", @"e",
                                                             @"y", nil]];
    break;
  case 'f':
    [tableList addObjectsFromArray:[NSArray arrayWithObjects:@"ph", nil]];
    break;
  case 'g':
    [tableList
        addObjectsFromArray:[NSArray arrayWithObjects:@"g", @"gh", @"j", nil]];
    break;
  case 'h':
    [tableList addObjectsFromArray:[NSArray arrayWithObjects:@"h", nil]];
    break;
  case 'i':
    [tableList
        addObjectsFromArray:[NSArray arrayWithObjects:@"i", @"ii", @"y", nil]];
    break;
  case 'j':
    [tableList
        addObjectsFromArray:[NSArray arrayWithObjects:@"j", @"jh", @"z", nil]];
    break;
  case 'k':
    [tableList addObjectsFromArray:[NSArray arrayWithObjects:@"k", @"kh", nil]];
    break;
  case 'l':
    [tableList addObjectsFromArray:[NSArray arrayWithObjects:@"l", nil]];
    break;
  case 'm':
    [tableList addObjectsFromArray:[NSArray arrayWithObjects:@"h", @"m", nil]];
    break;
  case 'n':
    [tableList
        addObjectsFromArray:[NSArray arrayWithObjects:@"n", @"nya", @"nga",
                                                      @"nn", nil]];
    break;
  case 'o':
    [tableList
        addObjectsFromArray:[NSArray arrayWithObjects:@"a", @"u", @"uu", @"oi",
                                                      @"o", @"ou", @"y", nil]];
    break;
  case 'p':
    [tableList addObjectsFromArray:[NSArray arrayWithObjects:@"p", @"ph", nil]];
    break;
  case 'q':
    [tableList addObjectsFromArray:[NSArray arrayWithObjects:@"k", nil]];
    break;
  case 'r':
    [tableList
        addObjectsFromArray:[NSArray arrayWithObjects:@"rri", @"h", @"r", @"rr",
                                                      @"rrh", nil]];
    break;
  case 's':
    [tableList
        addObjectsFromArray:[NSArray arrayWithObjects:@"s", @"sh", @"ss", nil]];
    break;
  case 't':
    [tableList
        addObjectsFromArray:[NSArray arrayWithObjects:@"t", @"th", @"tt",
                                                      @"tth", @"khandatta",
                                                      nil]];
    break;
  case 'u':
    [tableList
        addObjectsFromArray:[NSArray arrayWithObjects:@"u", @"uu", @"y", nil]];
    break;
  case 'v':
    [tableList addObjectsFromArray:[NSArray arrayWithObjects:@"bh", nil]];
    break;
  case 'w':
    [tableList addObjectsFromArray:[NSArray arrayWithObjects:@"o", nil]];
    break;
  case 'x':
    [tableList addObjectsFromArray:[NSArray arrayWithObjects:@"e", @"k", nil]];
    break;
  case 'y':
    [tableList addObjectsFromArray:[NSArray arrayWithObjects:@"i", @"y", nil]];
    break;
  case 'z':
    [tableList addObjectsFromArray:[NSArray arrayWithObjects:@"h", @"j", @"jh",
                                                             @"z", nil]];
    break;
  default:
    break;
  }

  // The extra-words table is searched for every term: it holds words whose
  // onset does not match any syllable table, and they must still be found.
  [tableList addObject:@"extra"];

  for (NSString *table in tableList) {
    NSArray *tableData = [_db objectForKey:table];
    for (NSString *tmpString in tableData) {
      if ([tmpString isMatchedByRegex:regex]) {
        [suggestions addObject:tmpString];
      }
    }
  }

  [tableList release];
  [suggestions autorelease];

  return [suggestions allObjects];
}

- (NSString *)banglaForSuffix:(NSString *)suffix {
  return [_suffix objectForKey:suffix];
}

@end
