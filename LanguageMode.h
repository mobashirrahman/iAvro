//
//  LanguageMode.h
//  Avro Keyboard
//
//  Decides whether a given application should receive plain English instead of
//  being composed into Bangla.
//
//  Typing Bangla and English in the same session is normal — commands, code and
//  technical terms are all English — and a phonetic input method that composes
//  everything makes terminals and editors unusable. Squirrel and the Japanese
//  input method both remember a per-application state; this is that.
//
//  Defaults cover the applications where composition is almost always wrong. A
//  user override always wins, so any application can be switched either way.
//

#import <Foundation/Foundation.h>

@interface LanguageMode : NSObject

// YES when the application should receive raw keystrokes, not composed Bangla.
+ (BOOL)isEnglishModeForBundleIdentifier:(NSString *)bundleIdentifier;

// Records an explicit choice for one application, overriding the default list.
+ (void)setEnglishMode:(BOOL)english
    forBundleIdentifier:(NSString *)bundleIdentifier;

// Removes any explicit choice, returning the application to its default.
+ (void)clearOverrideForBundleIdentifier:(NSString *)bundleIdentifier;

// YES when the current state differs from the built-in default.
+ (BOOL)hasOverrideForBundleIdentifier:(NSString *)bundleIdentifier;

// Applications that default to English mode.
+ (NSArray *)defaultEnglishBundleIdentifiers;

@end
