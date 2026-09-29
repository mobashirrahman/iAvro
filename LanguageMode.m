//
//  LanguageMode.m
//  Avro Keyboard
//

#import "LanguageMode.h"

// User overrides live under one key as a bundle identifier -> NSNumber(BOOL)
// map, so switching an application either way needs no schema change and an
// application can be returned to its default by removing its entry.
static NSString *const kOverridesKey = @"EnglishModeOverrides";

@implementation LanguageMode

+ (NSArray *)defaultEnglishBundleIdentifiers {
  // Terminals, shells and editors: composition here produces Bangla where the
  // user almost always meant the literal keystrokes.
  return [NSArray arrayWithObjects:
      // Terminals
      @"com.apple.Terminal",
      @"com.googlecode.iterm2",
      @"dev.warp.Warp-Stable",
      @"io.alacritty",
      @"net.kovidgoyal.kitty",
      @"com.github.wez.wezterm",
      @"co.zeit.hyper",
      @"org.alacritty",
      @"com.mitchellh.ghostty",
      // Remote and multiplexers
      @"com.termius.mac",
      @"com.lembchard.PuTTY",
      // Editors and IDEs
      @"com.apple.dt.Xcode",
      @"com.microsoft.VSCode",
      @"com.microsoft.VSCodeInsiders",
      @"com.sublimetext.4",
      @"com.sublimetext.3",
      @"com.jetbrains.intellij",
      @"com.jetbrains.pycharm",
      @"com.jetbrains.CLion",
      @"com.jetbrains.WebStorm",
      @"com.jetbrains.AppCode",
      @"abnerworks.Typora",
      @"com.uranusjr.macdown",
      nil];
}

+ (NSDictionary *)overrides {
  NSDictionary *stored =
      [[NSUserDefaults standardUserDefaults] dictionaryForKey:kOverridesKey];
  return [stored isKindOfClass:[NSDictionary class]] ? stored : nil;
}

+ (BOOL)isEnglishModeForBundleIdentifier:(NSString *)bundleIdentifier {
  if (![bundleIdentifier isKindOfClass:[NSString class]] ||
      [bundleIdentifier length] == 0) {
    // Unknown client: compose Bangla, which is what this input method is for.
    return NO;
  }

  id override = [[self overrides] objectForKey:bundleIdentifier];
  if ([override isKindOfClass:[NSNumber class]]) {
    return [override boolValue];
  }
  return [[self defaultEnglishBundleIdentifiers] containsObject:bundleIdentifier];
}

+ (void)setEnglishMode:(BOOL)english
    forBundleIdentifier:(NSString *)bundleIdentifier {
  if (![bundleIdentifier isKindOfClass:[NSString class]] ||
      [bundleIdentifier length] == 0) {
    return;
  }
  NSMutableDictionary *updated =
      [NSMutableDictionary dictionaryWithDictionary:[self overrides] ?: @{}];
  [updated setObject:[NSNumber numberWithBool:english]
              forKey:bundleIdentifier];
  [[NSUserDefaults standardUserDefaults] setObject:updated
                                            forKey:kOverridesKey];
}

+ (void)clearOverrideForBundleIdentifier:(NSString *)bundleIdentifier {
  if (![bundleIdentifier isKindOfClass:[NSString class]] ||
      [bundleIdentifier length] == 0) {
    return;
  }
  NSMutableDictionary *updated =
      [NSMutableDictionary dictionaryWithDictionary:[self overrides] ?: @{}];
  [updated removeObjectForKey:bundleIdentifier];
  [[NSUserDefaults standardUserDefaults] setObject:updated
                                            forKey:kOverridesKey];
}

+ (BOOL)hasOverrideForBundleIdentifier:(NSString *)bundleIdentifier {
  if (![bundleIdentifier isKindOfClass:[NSString class]] ||
      [bundleIdentifier length] == 0) {
    return NO;
  }
  return [[self overrides] objectForKey:bundleIdentifier] != nil;
}

@end
