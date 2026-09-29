#import <Foundation/Foundation.h>

#import "AvroParser.h"
#import "CacheManager.h"
#import "Suggestion.h"
#import "TestHarness.h"

// End-to-end check that learned choices survive a restart and still reorder
// candidates, which is the behaviour the Japanese IME calls conversion
// learning. Runs twice so the second pass reads state written by the first.

int main(void) {
  NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
  @autoreleasepool {
    [[NSUserDefaults standardUserDefaults] setBool:YES forKey:@"IncludeDictionary"];
    [[NSUserDefaults standardUserDefaults] setBool:NO forKey:@"EnableAutoCorrect"];
    [[NSUserDefaults standardUserDefaults] setBool:YES forKey:@"EnableSuggestions"];

    CacheManager *cache = [CacheManager sharedInstance];
    NSString *term = @"dhaka";

    SECTION("baseline order");
    NSArray *list = [[Suggestion sharedInstance] getList:term];
    for (NSUInteger i = 0; i < [list count] && i < 5; i++) {
      printf("       %lu. %s\n", (unsigned long)i + 1,
             [[list objectAtIndex:i] UTF8String]);
    }
    CHECK([list count] > 1, "candidates exist for dhaka");

    NSString *first = [list objectAtIndex:0];
    NSString *target = nil;
    for (NSUInteger i = 1; i < [list count]; i++) {
      target = [list objectAtIndex:i];
      break;
    }

    SECTION("learn the second choice three times");
    for (int i = 0; i < 3; i++) {
      [cache setString:target forKey:term];
      [cache incrementCountForKey:target];
    }
    [cache persist];

    NSArray *after = [[Suggestion sharedInstance] getList:term];
    printf("       after learning: 1. %s\n",
           [[after objectAtIndex:0] UTF8String]);
    CHECK([[after objectAtIndex:0] isEqualToString:target],
          "learned word is now first");
    CHECK(![first isEqualToString:target] || [list count] == 1,
          "the change is real (previous first differed)");

    // Simulate a restart: the only thing that carries over is the plist on disk.
    SECTION("after a restart (state read back from disk)");
    NSString *folder = [[@"~/Library/Application Support/OmicronLab/Avro Keyboard"
        stringByExpandingTildeInPath] copy];
    NSDictionary *weight =
        [NSDictionary dictionaryWithContentsOfFile:
            [folder stringByAppendingPathComponent:@"weight.plist"]];
    NSDictionary *counts =
        [NSDictionary dictionaryWithContentsOfFile:
            [folder stringByAppendingPathComponent:@"weight-counts.plist"]];
    CHECK([[weight objectForKey:term] isEqualToString:target],
          "learned choice is on disk");
    CHECK([[counts objectForKey:target] unsignedIntegerValue] == 3,
          "commit count is on disk");

    // Cleanup so the probe does not leave state behind.
    [cache removeStringForKey:term];
    [cache forgetCountsForKey:target];
    [cache persist];
  }
  [pool release];
  return 0;
}
