//
//  AvroKeyboard
//
//  Created by Rifat Nabi on 6/24/12.
//  Copyright (c) 2012 OmicronLab. All rights reserved.
//

#import "AutoCorrect.h"
#import "AvroParser.h"

static AutoCorrect *sharedInstance = nil;

@implementation AutoCorrect

@synthesize autoCorrectEntries = _autoCorrectEntries;
@synthesize userAutoCorrectEntries = _userAutoCorrectEntries;

+ (AutoCorrect *)sharedInstance {
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
  return sharedInstance; // on subsequent allocation attempts return nil
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
    // Load bundled AutoCorrect dictionary
    NSString *fileName = [[NSBundle mainBundle] pathForResource:@"autodict"
                                                         ofType:@"plist"];
    if ([[NSFileManager defaultManager] fileExistsAtPath:fileName]) {
      _autoCorrectEntries =
          [[NSMutableDictionary alloc] initWithContentsOfFile:fileName];
    } else {
      _autoCorrectEntries = [[NSMutableDictionary alloc] init];
    }

    // Load user-defined AutoCorrect dictionary
    NSString *userPath = [[self getUserAutoCorrectPath] retain];
    if ([[NSFileManager defaultManager] fileExistsAtPath:userPath]) {
      _userAutoCorrectEntries =
          [[NSMutableDictionary alloc] initWithContentsOfFile:userPath];
    } else {
      _userAutoCorrectEntries = [[NSMutableDictionary alloc] init];
    }
    [userPath release];
  }
  return self;
}

- (void)dealloc {
  [_autoCorrectEntries release];
  [_userAutoCorrectEntries release];
  [super dealloc];
}

// Instance Methods
- (NSString *)find:(NSString *)term {
  term = [[AvroParser sharedInstance] fix:term];
  // User entries take priority
  NSString *userResult = _userAutoCorrectEntries[term];
  if (userResult) {
    return userResult;
  }
  return _autoCorrectEntries[term];
}

- (NSString *)getUserAutoCorrectPath {
  NSArray *paths = NSSearchPathForDirectoriesInDomains(
      NSApplicationSupportDirectory, NSUserDomainMask, YES);
  NSString *appSupportDir =
      [[[paths objectAtIndex:0] stringByAppendingPathComponent:@"OmicronLab"]
          stringByAppendingPathComponent:@"Avro Keyboard"];
  // Create directory if it doesn't exist
  NSFileManager *fileManager = [NSFileManager defaultManager];
  if (![fileManager fileExistsAtPath:appSupportDir]) {
    NSError *error = nil;
    [fileManager createDirectoryAtPath:appSupportDir
           withIntermediateDirectories:YES
                            attributes:nil
                                 error:&error];
  }
  return [appSupportDir stringByAppendingPathComponent:@"user_autodict.plist"];
}

- (void)addUserEntry:(NSString *)replace with:(NSString *)with {
  [_userAutoCorrectEntries setObject:with forKey:replace];
  [self saveUserEntries];
}

- (void)removeUserEntry:(NSString *)replace {
  [_userAutoCorrectEntries removeObjectForKey:replace];
  [self saveUserEntries];
}

- (void)saveUserEntries {
  [_userAutoCorrectEntries writeToFile:[self getUserAutoCorrectPath]
                            atomically:YES];
}

- (BOOL)isUserEntry:(NSString *)key {
  return [_userAutoCorrectEntries objectForKey:key] != nil;
}

@end
