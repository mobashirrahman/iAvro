//
//  test_language_mode.m
//  Avro Keyboard
//
//  Covers per-application English pass-through:
//    - applications known to want literal keystrokes default to English
//    - an ordinary application composes Bangla
//    - an explicit choice overrides the default in either direction
//    - clearing the choice returns the application to its default
//    - unknown or malformed identifiers are safe and compose Bangla
//

#import <Foundation/Foundation.h>

#import "LanguageMode.h"
#import "TestHarness.h"

static void resetOverrides(void) {
  [[NSUserDefaults standardUserDefaults]
      removeObjectForKey:@"EnglishModeOverrides"];
}

int main(void) {
  NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
  @autoreleasepool {
    resetOverrides();

    SECTION("defaults");
    CHECK([LanguageMode isEnglishModeForBundleIdentifier:@"com.apple.Terminal"],
          "Terminal defaults to English");
    CHECK([LanguageMode isEnglishModeForBundleIdentifier:@"com.apple.dt.Xcode"],
          "Xcode defaults to English");
    CHECK([LanguageMode isEnglishModeForBundleIdentifier:@"com.googlecode.iterm2"],
          "iTerm2 defaults to English");
    CHECK(![LanguageMode isEnglishModeForBundleIdentifier:@"com.apple.TextEdit"],
          "TextEdit composes Bangla");
    CHECK(![LanguageMode isEnglishModeForBundleIdentifier:@"com.apple.mail"],
          "Mail composes Bangla");

    SECTION("defaults are recognisable and non-empty");
    NSArray *defaults = [LanguageMode defaultEnglishBundleIdentifiers];
    CHECK([defaults count] > 0, "there is a default list");
    CHECK([defaults containsObject:@"com.apple.Terminal"],
          "the list contains Terminal");
    CHECK(![LanguageMode hasOverrideForBundleIdentifier:@"com.apple.Terminal"],
          "a default is not an override");

    SECTION("an explicit choice overrides the default in both directions");
    // Force compose in an application that defaults to English.
    [LanguageMode setEnglishMode:NO forBundleIdentifier:@"com.apple.Terminal"];
    CHECK(![LanguageMode isEnglishModeForBundleIdentifier:@"com.apple.Terminal"],
          "Terminal can be switched back to Bangla");
    CHECK([LanguageMode hasOverrideForBundleIdentifier:@"com.apple.Terminal"],
          "the choice is recorded as an override");

    // Force pass-through in an ordinary application.
    [LanguageMode setEnglishMode:YES forBundleIdentifier:@"com.apple.TextEdit"];
    CHECK([LanguageMode isEnglishModeForBundleIdentifier:@"com.apple.TextEdit"],
          "TextEdit can be switched to English");

    SECTION("choices are independent per application");
    // Terminal was just switched to composing; Xcode must still be English,
    // proving one application's override does not leak to another.
    CHECK([LanguageMode isEnglishModeForBundleIdentifier:@"com.apple.dt.Xcode"],
          "the Xcode choice is unaffected by the Terminal choice");
    CHECK([LanguageMode isEnglishModeForBundleIdentifier:@"com.apple.TextEdit"],
          "the TextEdit choice survives");

    SECTION("clearing restores the default");
    [LanguageMode clearOverrideForBundleIdentifier:@"com.apple.Terminal"];
    CHECK([LanguageMode isEnglishModeForBundleIdentifier:@"com.apple.Terminal"],
          "Terminal returns to its English default");
    CHECK(![LanguageMode hasOverrideForBundleIdentifier:@"com.apple.Terminal"],
          "the override is gone");
    [LanguageMode clearOverrideForBundleIdentifier:@"com.apple.TextEdit"];
    CHECK(![LanguageMode isEnglishModeForBundleIdentifier:@"com.apple.TextEdit"],
          "TextEdit returns to composing Bangla");

    SECTION("choices survive a fresh read from storage");
    [LanguageMode setEnglishMode:YES forBundleIdentifier:@"com.example.editor"];
    NSDictionary *stored = [[NSUserDefaults standardUserDefaults]
        dictionaryForKey:@"EnglishModeOverrides"];
    CHECK([[stored objectForKey:@"com.example.editor"] boolValue],
          "the choice is written to user defaults");
    CHECK([LanguageMode isEnglishModeForBundleIdentifier:@"com.example.editor"],
          "and read back");

    SECTION("malformed input is safe and composes Bangla");
    CHECK(![LanguageMode isEnglishModeForBundleIdentifier:nil],
          "nil identifier composes Bangla");
    CHECK(![LanguageMode isEnglishModeForBundleIdentifier:@""],
          "empty identifier composes Bangla");
    CHECK(![LanguageMode isEnglishModeForBundleIdentifier:@"com.unknown.app"],
          "an unknown application composes Bangla");
    BOOL threw = NO;
    @try {
      [LanguageMode setEnglishMode:YES forBundleIdentifier:nil];
      [LanguageMode setEnglishMode:YES forBundleIdentifier:@""];
      [LanguageMode clearOverrideForBundleIdentifier:nil];
      [LanguageMode clearOverrideForBundleIdentifier:@""];
    } @catch (NSException *e) {
      threw = YES;
    }
    CHECK(!threw, "nil and empty identifiers do not raise");
    CHECK(![LanguageMode hasOverrideForBundleIdentifier:nil],
          "hasOverride is safe with nil");

    SECTION("a stored value of the wrong type is ignored");
    [[NSUserDefaults standardUserDefaults]
        setObject:[NSArray arrayWithObject:@"not a dictionary"]
           forKey:@"EnglishModeOverrides"];
    CHECK([LanguageMode isEnglishModeForBundleIdentifier:@"com.apple.Terminal"],
          "a corrupt store falls back to the default rather than crashing");
    CHECK(![LanguageMode isEnglishModeForBundleIdentifier:@"com.apple.TextEdit"],
          "and ordinary applications still compose Bangla");

    resetOverrides();
    CHECK(![LanguageMode hasOverrideForBundleIdentifier:@"com.apple.Terminal"],
          "cleanup left no overrides behind");
  }
  int rc = test_report("test_language_mode");
  [pool release];
  return rc;
}
