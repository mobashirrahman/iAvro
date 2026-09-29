//
//  VersionInfo.m
//  Avro Keyboard
//

#import "VersionInfo.h"

@implementation VersionInfo

+ (NSString *)formatVersion:(NSString *)shortVersion build:(NSString *)build {
  if ([shortVersion length] == 0) {
    return @"unknown version";
  }
  if ([build length] == 0) {
    return shortVersion;
  }
  return [NSString stringWithFormat:@"%@ (build %@)", shortVersion, build];
}

+ (NSString *)displayVersion {
  NSDictionary *info = [[NSBundle mainBundle] infoDictionary];
  return [self formatVersion:[info objectForKey:@"CFBundleShortVersionString"]
                       build:[info objectForKey:@"CFBundleVersion"]];
}

+ (NSString *)architectureDescription {
  // Both macros are defined for a universal build, so this reports what the
  // running slice set actually contains.
#if defined(__arm64__) && defined(__x86_64__)
  return @"Universal (Apple Silicon and Intel)";
#elif defined(__arm64__)
  return @"Apple Silicon";
#elif defined(__x86_64__)
  return @"Intel";
#else
  return nil;
#endif
}

+ (NSString *)displaySummary {
  NSString *architectures = [self architectureDescription];
  if ([architectures length] == 0) {
    return [NSString stringWithFormat:@"Avro Keyboard %@",
                                      [self displayVersion]];
  }
  return [NSString stringWithFormat:@"Avro Keyboard %@ — %@",
                                    [self displayVersion], architectures];
}

@end
