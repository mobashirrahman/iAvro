//
//  VersionInfo.h
//  Avro Keyboard
//
//  The version string shown in the About panel and the preferences window,
//  which is how a tester confirms which build they are running.
//
//  Foundation-only and separate from the application delegate so it can be
//  tested without linking the delegate's dependencies.
//

#import <Foundation/Foundation.h>

@interface VersionInfo : NSObject

// e.g. "2.0.6 (build 6)", read from the running bundle.
+ (NSString *)displayVersion;

// Which architectures are compiled into this binary.
+ (NSString *)architectureDescription;

// One line for display: version, then architecture when known.
+ (NSString *)displaySummary;

// Formats a version and build without a bundle, for testing.
+ (NSString *)formatVersion:(NSString *)shortVersion build:(NSString *)build;

@end
