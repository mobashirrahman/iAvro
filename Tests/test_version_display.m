//
//  test_version_display.m
//  Avro Keyboard
//
//  Covers the version string shown in the About panel and the preferences
//  window, which is what a tester uses to confirm which build they are running.
//

#import <Foundation/Foundation.h>

#import "VersionInfo.h"
#import "TestHarness.h"

int main(void) {
  NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
  @autoreleasepool {
    SECTION("formatting");
    CHECK([[VersionInfo formatVersion:@"2.0.6" build:@"6"]
              isEqualToString:@"2.0.6 (build 6)"],
          "version and build are both shown");
    CHECK([[VersionInfo formatVersion:@"2.0.6" build:@""]
              isEqualToString:@"2.0.6"],
          "a missing build is omitted rather than shown as empty");
    CHECK([[VersionInfo formatVersion:@"2.0.6" build:nil]
              isEqualToString:@"2.0.6"],
          "a nil build is omitted");
    CHECK([[VersionInfo formatVersion:@"" build:@"6"]
              isEqualToString:@"unknown version"],
          "a missing version says so instead of showing nothing");
    CHECK([[VersionInfo formatVersion:nil build:@"6"]
              isEqualToString:@"unknown version"],
          "a nil version says so too");

    SECTION("the built app reports a real version");
    // Outside an application bundle there is no version to read; if this runs
    // inside the bundle it must not come back unknown.
    NSString *display = [VersionInfo displayVersion];
    printf("       displayVersion -> %s\n", [display UTF8String]);
    CHECK([display length] > 0, "displayVersion never returns empty");
    if ([[[NSBundle mainBundle] infoDictionary]
            objectForKey:@"CFBundleShortVersionString"]) {
      CHECK(![display isEqualToString:@"unknown version"],
            "inside the app bundle a real version is reported");
      CHECK([display rangeOfString:@"build"].location != NSNotFound,
            "the build number is included");
    } else {
      CHECK([display isEqualToString:@"unknown version"],
            "outside a bundle the fallback is used");
    }
  }
  int rc = test_report("test_version_display");
  [pool release];
  return rc;
}
