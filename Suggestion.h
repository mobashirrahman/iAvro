//
//  AvroKeyboard
//
//  Created by Rifat Nabi on 6/28/12.
//  Copyright (c) 2012 OmicronLab. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface Suggestion : NSObject {
    NSMutableArray* _suggestions;
    NSInteger _cachedPreferenceFlags;
}

+ (Suggestion *)sharedInstance;

- (NSArray*)getList:(NSString*)term;
- (NSString*)abbreviationForTerm:(NSString*)term;
- (BOOL)isKar:(NSString*)letter;
- (BOOL)isVowel:(NSString*)letter;

@end
