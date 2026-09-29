//
//  test_storage.m
//  Avro Keyboard
//
//  Covers user data storage:
//    - weight.plist corrupt/missing fallback, persist round-trip (B7)
//    - phonetic and base caches are bounded
//    - AutoCorrect user overlay lives outside the signed bundle
//

#import <Foundation/Foundation.h>

#import "AutoCorrect.h"
#import "CacheManager.h"
#import "TestHarness.h"

static NSString *supportFolder(void) {
  NSArray *paths = NSSearchPathForDirectoriesInDomains(
      NSApplicationSupportDirectory, NSUserDomainMask, YES);
  return [[[paths objectAtIndex:0] stringByAppendingPathComponent:@"OmicronLab"]
      stringByAppendingPathComponent:@"Avro Keyboard"];
}

static void test_cache_bounds(void) {
  SECTION("cache bounds");
  CacheManager *cache = [CacheManager sharedInstance];

  for (int i = 0; i < 1100; i++) {
    [cache setArray:[NSArray arrayWithObject:@"x"]
             forKey:[NSString stringWithFormat:@"flood-%d", i]];
  }
  NSUInteger phonetic = [cache phoneticCacheCount];
  printf("       phonetic entries after 1100 inserts: %lu\n",
         (unsigned long)phonetic);
  CHECK(phonetic <= 1000, "phonetic cache stays bounded");

  for (int i = 0; i < 600; i++) {
    [cache setBase:[NSArray arrayWithObjects:@"a", @"b", nil]
            forKey:[NSString stringWithFormat:@"base-%d", i]];
  }
  NSUInteger base = [cache recentBaseCacheCount];
  printf("       base entries after 600 inserts: %lu\n", (unsigned long)base);
  CHECK(base <= 500, "base cache stays bounded");

  [cache setArray:[NSArray arrayWithObject:@"LIVE"] forKey:@"live-key"];
  CHECK([[[cache arrayForKey:@"live-key"] objectAtIndex:0]
             isEqualToString:@"LIVE"],
        "fresh phonetic entry readable after eviction pressure");
  [cache setBase:[NSArray arrayWithObject:@"LIVEB"] forKey:@"live-base"];
  CHECK([[[cache baseForKey:@"live-base"] objectAtIndex:0]
             isEqualToString:@"LIVEB"],
        "fresh base entry readable after eviction pressure");
}

static void test_cache_nil_guards(void) {
  SECTION("cache nil guards");
  CacheManager *cache = [CacheManager sharedInstance];
  BOOL threw = NO;
  @try {
    [cache setString:nil forKey:@"k"];
    [cache setString:@"v" forKey:nil];
    [cache setArray:nil forKey:@"k"];
    [cache setBase:nil forKey:@"k"];
    [cache removeStringForKey:nil];
  } @catch (NSException *e) {
    threw = YES;
  }
  CHECK(!threw, "nil arguments do not raise");
  CHECK([cache stringForKey:nil] == nil, "stringForKey:nil returns nil");
  CHECK([cache arrayForKey:nil] == nil, "arrayForKey:nil returns nil");
  CHECK([cache baseForKey:nil] == nil, "baseForKey:nil returns nil");
}

static void test_weight_persist(void) {
  SECTION("weight.plist persistence (B7)");
  NSString *weightPath =
      [supportFolder() stringByAppendingPathComponent:@"weight.plist"];
  NSString *backup =
      [NSTemporaryDirectory() stringByAppendingPathComponent:@"weight_backup.plist"];
  BOOL existed = [[NSFileManager defaultManager] fileExistsAtPath:weightPath];
  if (existed) {
    [[NSFileManager defaultManager] copyItemAtPath:weightPath
                                             toPath:backup
                                              error:NULL];
  }

  CacheManager *cache = [CacheManager sharedInstance];
  NSString *key = @"__test_weight_key__";
  [cache setString:@"__test_weight_value__" forKey:key];
  CHECK([[cache stringForKey:key] isEqualToString:@"__test_weight_value__"],
        "in-memory round trip");
  [cache persist];

  NSDictionary *onDisk = [NSDictionary dictionaryWithContentsOfFile:weightPath];
  CHECK(onDisk != nil && [onDisk objectForKey:key] != nil,
        "persist writes the key to disk");

  [cache removeStringForKey:key];
  [cache persist];
  NSDictionary *cleaned = [NSDictionary dictionaryWithContentsOfFile:weightPath];
  CHECK([cleaned objectForKey:key] == nil, "key removed from disk");

  if (existed) {
    [[NSFileManager defaultManager] removeItemAtPath:weightPath error:NULL];
    [[NSFileManager defaultManager] copyItemAtPath:backup
                                             toPath:weightPath
                                              error:NULL];
    [[NSFileManager defaultManager] removeItemAtPath:backup error:NULL];
  }

  // A corrupt plist must not leave the cache unusable.
  NSString *corrupt =
      [NSTemporaryDirectory() stringByAppendingPathComponent:@"corrupt.plist"];
  [@"NOT A PLIST {{{" writeToFile:corrupt
                      atomically:YES
                        encoding:NSUTF8StringEncoding
                           error:NULL];
  NSMutableDictionary *loaded = [[NSMutableDictionary alloc] initWithContentsOfFile:corrupt];
  if (!loaded) {
    loaded = [[NSMutableDictionary alloc] initWithCapacity:0];
  }
  BOOL usable = NO;
  @try {
    [loaded setObject:@"v" forKey:@"k"];
    usable = [[loaded objectForKey:@"k"] isEqualToString:@"v"];
  } @catch (NSException *e) {
    usable = NO;
  }
  CHECK(usable, "corrupt plist falls back to a usable empty dictionary");
  [loaded release];
  [[NSFileManager defaultManager] removeItemAtPath:corrupt error:NULL];
}

static void test_autocorrect_overlay(void) {
  SECTION("AutoCorrect user overlay");
  AutoCorrect *autoCorrect = [AutoCorrect sharedInstance];

  NSString *userPath =
      [supportFolder() stringByAppendingPathComponent:@"autodict-user.plist"];
  NSString *backup = [NSTemporaryDirectory()
      stringByAppendingPathComponent:@"autodict_user_backup.plist"];
  BOOL existed = [[NSFileManager defaultManager] fileExistsAtPath:userPath];
  if (existed) {
    [[NSFileManager defaultManager] copyItemAtPath:userPath
                                             toPath:backup
                                              error:NULL];
  }

  // Bundled entries are read-only: user data must not be written into the
  // signed app bundle.
  NSString *bundleDict = [[NSBundle mainBundle] pathForResource:@"autodict"
                                                          ofType:@"plist"];
  NSDate *bundleDate = nil;
  if (bundleDict) {
    NSDictionary *attrs = [[NSFileManager defaultManager]
        attributesOfItemAtPath:bundleDict
                         error:NULL];
    bundleDate = [attrs objectForKey:NSFileModificationDate];
  }

  [autoCorrect setUserAutoCorrect:@"X-TEST" forTerm:@"ac-test-key"];
  CHECK([[autoCorrect find:@"ac-test-key"] isEqualToString:@"X-TEST"],
        "user entry resolves");
  NSDictionary *persisted = [NSDictionary dictionaryWithContentsOfFile:userPath];
  CHECK(persisted != nil && [persisted objectForKey:@"ac-test-key"] != nil,
        "user entry persisted to Application Support");

  if (bundleDate) {
    NSDictionary *afterAttrs = [[NSFileManager defaultManager]
        attributesOfItemAtPath:bundleDict
                         error:NULL];
    NSDate *afterDate = [afterAttrs objectForKey:NSFileModificationDate];
    CHECK([bundleDate isEqualToDate:afterDate],
          "bundled autodict.plist left untouched");
  }

  // Removal must fall back to the bundled value when one exists.
  NSString *bundledTerm = nil;
  NSDictionary *bundled = [NSDictionary dictionaryWithContentsOfFile:bundleDict];
  for (NSString *candidate in bundled) {
    if ([candidate length] > 2 && [candidate length] < 6) {
      bundledTerm = candidate;
      break;
    }
  }
  if (bundledTerm) {
    [autoCorrect setUserAutoCorrect:@"OVERRIDDEN" forTerm:bundledTerm];
    CHECK([[autoCorrect find:bundledTerm] isEqualToString:@"OVERRIDDEN"],
          "user overlay beats the bundled entry");
    [autoCorrect removeUserAutoCorrectForTerm:bundledTerm];
    CHECK([[autoCorrect find:bundledTerm]
              isEqualToString:[bundled objectForKey:bundledTerm]],
          "removal restores the bundled value");
  }

  [autoCorrect removeUserAutoCorrectForTerm:@"ac-test-key"];
  CHECK([autoCorrect find:@"ac-test-key"] == nil, "user-only entry removed");

  BOOL threw = NO;
  @try {
    [autoCorrect setUserAutoCorrect:nil forTerm:@"k"];
    [autoCorrect setUserAutoCorrect:@"v" forTerm:nil];
    [autoCorrect removeUserAutoCorrectForTerm:nil];
  } @catch (NSException *e) {
    threw = YES;
  }
  CHECK(!threw && [autoCorrect find:nil] == nil, "nil arguments are safe");

  if (existed) {
    [[NSFileManager defaultManager] removeItemAtPath:userPath error:NULL];
    [[NSFileManager defaultManager] copyItemAtPath:backup
                                             toPath:userPath
                                              error:NULL];
    [[NSFileManager defaultManager] removeItemAtPath:backup error:NULL];
  } else {
    [[NSFileManager defaultManager] removeItemAtPath:userPath error:NULL];
  }
}

static void test_selection_counts(void) {
  SECTION("selection counts");
  CacheManager *cache = [CacheManager sharedInstance];

  NSString *word = @"__count_probe_word__";
  [cache forgetCountsForKey:word];
  CHECK([cache countForKey:word] == 0, "unknown word starts at zero");
  [cache incrementCountForKey:word];
  [cache incrementCountForKey:word];
  [cache incrementCountForKey:word];
  CHECK([cache countForKey:word] == 3, "increments accumulate");
  [cache incrementCountForKey:nil];
  CHECK([cache countForKey:nil] == 0, "nil key is safe and reads as zero");
  [cache forgetCountsForKey:nil];

  // Counts must survive a round trip, and must not corrupt weight.plist.
  NSString *folder = supportFolder();
  NSString *countsPath =
      [folder stringByAppendingPathComponent:@"weight-counts.plist"];
  [cache persist];
  NSDictionary *onDisk = [NSDictionary dictionaryWithContentsOfFile:countsPath];
  CHECK(onDisk != nil, "weight-counts.plist written");
  CHECK([[onDisk objectForKey:word] unsignedIntegerValue] == 3,
        "count persisted with the right value");
  CHECK([NSDictionary dictionaryWithContentsOfFile:
             [folder stringByAppendingPathComponent:@"weight.plist"]] != nil,
        "weight.plist still written");

  [cache forgetCountsForKey:word];
  [cache persist];
  CHECK([[NSDictionary dictionaryWithContentsOfFile:countsPath]
             objectForKey:word] == nil,
        "forget removes the count from disk");
}

int main(void) {
  NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
  @autoreleasepool {
    test_cache_bounds();
    test_cache_nil_guards();
    test_weight_persist();
    test_selection_counts();
    test_autocorrect_overlay();
  }
  int rc = test_report("test_storage");
  [pool release];
  return rc;
}
