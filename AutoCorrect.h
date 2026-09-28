//
//  AvroKeyboard
//
//  Created by Rifat Nabi on 6/24/12.
//  Copyright (c) 2012 OmicronLab. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface AutoCorrect : NSObject {
    NSMutableDictionary* _autoCorrectEntries;
    NSDictionary* _bundledEntries;
    NSMutableDictionary* _userEntries;
}

@property (retain) NSMutableDictionary* autoCorrectEntries;

+ (AutoCorrect *)sharedInstance;

- (NSString*)find:(NSString*)term;
- (NSMutableDictionary*)autoCorrectEntries;
- (void)setAutoCorrectEntries:(NSMutableDictionary *)autoCorrectEntries;

// User entries overlay Application Support storage (bundle stays pristine).
- (void)setUserAutoCorrect:(NSString *)correction forTerm:(NSString *)term;
- (void)removeUserAutoCorrectForTerm:(NSString *)term;
- (void)deleteAutoCorrectForTerm:(NSString *)term;
- (void)setUserAutoCorrectEntries:(NSDictionary *)entries;
- (NSString *)correctionForValue:(NSString *)value term:(NSString *)term;
+ (NSDictionary *)entriesFromDictionaryFile:(NSString *)path error:(NSError **)error;

@end
