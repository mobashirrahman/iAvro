//
//  AvroKeyboard
//
//  Created by Rifat Nabi on 7/1/12.
//  Copyright (c) 2012 OmicronLab. All rights reserved.
//

#import "CacheManager.h"

static CacheManager* sharedInstance = nil;

@implementation CacheManager

+ (CacheManager *)sharedInstance  {
    if (sharedInstance == nil) {
        [[self alloc] init]; // assignment not done here, see allocWithZone
    }
	return sharedInstance;
}

+ (id)allocWithZone:(NSZone *)zone {
    
    if (sharedInstance == nil) {
        sharedInstance = [super allocWithZone:zone];
        return sharedInstance;  // assignment and return on first allocation
    }
    return nil; //on subsequent allocation attempts return nil
}

- (id)copyWithZone:(NSZone *)zone {
    return self;
}

- (id)retain {
    return self;
}

- (oneway void)release {
    //do nothing
}

- (id)autorelease {
    return self;
}

- (NSUInteger)retainCount {
    return NSUIntegerMax;  // This is sooo not zero
}

- (id)init {
    self = [super init];
    if (self) {
        // Weight PLIST File
        NSString *path = [self getSharedFolder];
        NSFileManager *fileManager = [NSFileManager defaultManager];
        if ([fileManager fileExistsAtPath:path] == NO) {
            NSError* error = nil;
            [[NSFileManager defaultManager] createDirectoryAtPath:path withIntermediateDirectories:YES attributes:nil error:&error];
            if (error) {
                @throw error;
            }
        }
        
        path = [path stringByAppendingPathComponent:@"weight.plist"];
        
        if ([fileManager fileExistsAtPath:path]) {
            _weightCache = [[NSMutableDictionary alloc] initWithContentsOfFile:path];
            if (!_weightCache) {
                _weightCache = [[NSMutableDictionary alloc] initWithCapacity:0];
            }
        } else {
            _weightCache = [[NSMutableDictionary alloc] initWithCapacity:0];
        }
        _phoneticCache = [[NSMutableDictionary alloc] initWithCapacity:0];
        _recentBaseCache = [[NSMutableDictionary alloc] initWithCapacity:0];

        // Selection counts live in their own file so weight.plist keeps the
        // term -> last-chosen-word shape older builds expect.
        NSString *countPath =
            [path stringByDeletingLastPathComponent];
        countPath = [countPath stringByAppendingPathComponent:@"weight-counts.plist"];
        if ([fileManager fileExistsAtPath:countPath]) {
            NSDictionary *loaded =
                [NSDictionary dictionaryWithContentsOfFile:countPath];
            _countCache = loaded ? [[loaded mutableCopy] autorelease]
                                 : [[NSMutableDictionary alloc] initWithCapacity:0];
        } else {
            _countCache = [[NSMutableDictionary alloc] initWithCapacity:0];
        }
    }
    return self;
}

- (void)dealloc {
    [self persist];
    [_phoneticCache release];
    [_recentBaseCache release];
    [_weightCache release];
    [_countCache release];
    [super dealloc];
}

- (void)persist {
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(persist) object:nil];
    if (!_weightCache) {
        return;
    }
    NSString *folder = [self getSharedFolder];
    [[NSFileManager defaultManager] createDirectoryAtPath:folder withIntermediateDirectories:YES attributes:nil error:NULL];
    [_weightCache writeToFile:[folder stringByAppendingPathComponent:@"weight.plist"] atomically:YES];
    if (_countCache) {
        [_countCache writeToFile:[folder stringByAppendingPathComponent:@"weight-counts.plist"]
                      atomically:YES];
    }
}

// Coalesces writes: weight.plist is rewritten whole, so saving after every
// committed word blocked typing as the file grew.
- (void)schedulePersist {
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(persist) object:nil];
    [self performSelector:@selector(persist) withObject:nil afterDelay:2.0];
}

- (NSString*)getSharedFolder {
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES);
    return [[[paths objectAtIndex:0] 
             stringByAppendingPathComponent:@"OmicronLab"] 
            stringByAppendingPathComponent:@"Avro Keyboard"];
}

// Weight Cache
- (NSString*)stringForKey:(NSString*)aKey {
    if (!aKey) {
        return nil;
    }
    return [_weightCache objectForKey:aKey];
}

- (void)removeStringForKey:(NSString*)aKey {
    if (!aKey) {
        return;
    }
    [_weightCache removeObjectForKey:aKey];
}

- (void)setString:(NSString*)aString forKey:(NSString*)aKey {
    if (!aString || !aKey) {
        return;
    }
    [_weightCache setObject:aString forKey:aKey];
}

// Selection Counts
- (NSUInteger)countForKey:(NSString*)aKey {
    if (!aKey) {
        return 0;
    }
    return [[_countCache objectForKey:aKey] unsignedIntegerValue];
}

- (void)incrementCountForKey:(NSString*)aKey {
    if (!aKey) {
        return;
    }
    NSUInteger next = [self countForKey:aKey] + 1;
    [_countCache setObject:[NSNumber numberWithUnsignedInteger:next] forKey:aKey];
    [self schedulePersist];
}

- (void)forgetCountsForKey:(NSString*)aKey {
    if (!aKey) {
        return;
    }
    [_countCache removeObjectForKey:aKey];
    [self schedulePersist];
}

static const NSUInteger kPhoneticCacheLimit = 1000;
static const NSUInteger kRecentBaseCacheLimit = 500;

+ (void)evictHalfOfDictionary:(NSMutableDictionary *)dict {
    NSArray *keys = [dict allKeys];
    NSUInteger n = [keys count] / 2;
    for (NSUInteger i = 0; i < n; i++) {
        [dict removeObjectForKey:[keys objectAtIndex:i]];
    }
}

// Phonetic Cache
- (NSArray*)arrayForKey:(NSString*)aKey {
    if (!aKey) {
        return nil;
    }
    return [_phoneticCache objectForKey:aKey];
}

- (void)removeAllArrays {
    [_phoneticCache removeAllObjects];
}

- (NSUInteger)phoneticCacheCount {
    return [_phoneticCache count];
}

- (void)setArray:(NSArray*)anArray forKey:(NSString*)aKey {
    if (!anArray || !aKey) {
        return;
    }
    [_phoneticCache setObject:anArray forKey:aKey];
    if ([_phoneticCache count] > kPhoneticCacheLimit) {
        [[self class] evictHalfOfDictionary:_phoneticCache];
    }
}

// Base Cache
- (void)removeAllBase {
    [_recentBaseCache removeAllObjects];
}

- (NSArray*)baseForKey:(NSString*)aKey {
    if (!aKey) {
        return nil;
    }
    return [_recentBaseCache objectForKey:aKey];
}

- (NSUInteger)recentBaseCacheCount {
    return [_recentBaseCache count];
}

- (void)setBase:(NSArray*)aBase forKey:(NSString*)aKey {
    if (!aBase || !aKey) {
        return;
    }
    [_recentBaseCache setObject:aBase forKey:aKey];
    if ([_recentBaseCache count] > kRecentBaseCacheLimit) {
        [[self class] evictHalfOfDictionary:_recentBaseCache];
    }
}

@end
