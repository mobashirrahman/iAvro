//
//  AvroKeyboard
//
//  Created by Rifat Nabi on 6/24/12.
//  Copyright (c) 2012 OmicronLab. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface AutoCorrect : NSObject {
  NSMutableDictionary *_autoCorrectEntries;
  NSMutableDictionary *_userAutoCorrectEntries;
}

@property(retain) NSMutableDictionary *autoCorrectEntries;
@property(retain) NSMutableDictionary *userAutoCorrectEntries;

+ (AutoCorrect *)sharedInstance;

- (NSString *)find:(NSString *)term;
- (NSMutableDictionary *)autoCorrectEntries;
- (void)setAutoCorrectEntries:(NSMutableDictionary *)autoCorrectEntries;
- (void)addUserEntry:(NSString *)replace with:(NSString *)with;
- (void)removeUserEntry:(NSString *)replace;
- (void)saveUserEntries;
- (BOOL)isUserEntry:(NSString *)key;

@end
