//
//  AvroKeyboard
//
//  Created by Rifat Nabi on 6/24/12.
//  Copyright (c) 2012 OmicronLab. All rights reserved.
//

#import "AutoCorrect.h"
#import "AvroParser.h"
#import "CacheManager.h"

static AutoCorrect* sharedInstance = nil;

@implementation AutoCorrect

@synthesize autoCorrectEntries = _autoCorrectEntries;

+ (AutoCorrect *)sharedInstance  {
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
    return sharedInstance; //on subsequent allocation attempts return nil
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

+ (NSString *)userEntriesPath {
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES);
    NSString *folder = [[[paths objectAtIndex:0]
        stringByAppendingPathComponent:@"OmicronLab"]
        stringByAppendingPathComponent:@"Avro Keyboard"];
    return [folder stringByAppendingPathComponent:@"autodict-user.plist"];
}

- (void)persistUserEntries {
    NSString *path = [[self class] userEntriesPath];
    [[NSFileManager defaultManager] createDirectoryAtPath:[path stringByDeletingLastPathComponent]
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:NULL];
    [_userEntries writeToFile:path atomically:YES];
}

- (id)init {
    self = [super init];
    if (self) {
        // Bundled entries (read-only baseline; bundle must stay pristine
        // for code signature validity).
        NSString *fileName = [[NSBundle mainBundle] pathForResource:@"autodict" ofType:@"plist"];
        NSDictionary *bundled = nil;
        if (fileName && [[NSFileManager defaultManager] fileExistsAtPath:fileName]) {
            bundled = [NSDictionary dictionaryWithContentsOfFile:fileName];
        }
        _bundledEntries = [(bundled ? bundled : [NSDictionary dictionary]) retain];

        // User overlay from Application Support (nil-safe on corrupt file).
        NSString *userPath = [[self class] userEntriesPath];
        NSMutableDictionary *user = nil;
        if ([[NSFileManager defaultManager] fileExistsAtPath:userPath]) {
            user = [[NSMutableDictionary alloc] initWithContentsOfFile:userPath];
        }
        _userEntries = user ? user : [[NSMutableDictionary alloc] initWithCapacity:0];

        // Combined live dictionary (backward compatible with existing readers).
        _autoCorrectEntries = [[NSMutableDictionary alloc] initWithCapacity:[_bundledEntries count] + [_userEntries count]];
        [_autoCorrectEntries addEntriesFromDictionary:_bundledEntries];
        [_autoCorrectEntries addEntriesFromDictionary:_userEntries];
        // An empty user value hides a bundled entry the user deleted
        for (NSString *key in _userEntries) {
            if ([[_userEntries objectForKey:key] length] == 0) {
                [_autoCorrectEntries removeObjectForKey:key];
            }
        }
    }
    return self;
}

- (void)dealloc {
    [_autoCorrectEntries release];
    [_bundledEntries release];
    [_userEntries release];
    [super dealloc];
}

// Instance Methods
- (NSString*)find:(NSString*)term {
    term = [[AvroParser sharedInstance] fix:term];
    if (!term) {
        return nil;
    }
    return [_autoCorrectEntries objectForKey:term];
}

- (void)setUserAutoCorrect:(NSString *)correction forTerm:(NSString *)term {
    if (!correction || !term || [term length] == 0) {
        return;
    }
    NSString *key = [[AvroParser sharedInstance] fix:term];
    if (!key || [key length] == 0) {
        return;
    }
    [_userEntries setObject:correction forKey:key];
    [_autoCorrectEntries setObject:correction forKey:key];
    [self persistUserEntries];
    [self entriesDidChange];
}

- (void)removeUserAutoCorrectForTerm:(NSString *)term {
    if (!term) {
        return;
    }
    NSString *key = [[AvroParser sharedInstance] fix:term];
    if (!key) {
        return;
    }
    [_userEntries removeObjectForKey:key];
    [_autoCorrectEntries removeObjectForKey:key];
    id bundledValue = [_bundledEntries objectForKey:key];
    if (bundledValue) {
        [_autoCorrectEntries setObject:bundledValue forKey:key];
    }
    [self persistUserEntries];
    [self entriesDidChange];
}

- (NSDictionary *)userAutoCorrectEntries {
    return [[_userEntries copy] autorelease];
}

- (void)deleteAutoCorrectForTerm:(NSString *)term {
    NSString *key = [[AvroParser sharedInstance] fix:term];
    if (!key || [key length] == 0) {
        return;
    }
    if ([_bundledEntries objectForKey:key]) {
        // Bundled entries can't be removed from the bundle; mask them.
        [_userEntries setObject:@"" forKey:key];
    } else {
        [_userEntries removeObjectForKey:key];
    }
    [_autoCorrectEntries removeObjectForKey:key];
    [self persistUserEntries];
    [self entriesDidChange];
}

- (void)setUserAutoCorrectEntries:(NSDictionary *)entries {
    for (NSString *term in entries) {
        NSString *key = [[AvroParser sharedInstance] fix:term];
        NSString *correction = [entries objectForKey:term];
        if ([key length] == 0 || [correction length] == 0) {
            continue;
        }
        [_userEntries setObject:correction forKey:key];
        [_autoCorrectEntries setObject:correction forKey:key];
    }
    [self persistUserEntries];
    [self entriesDidChange];
}

// Suggestion lists are memoized per term and include AutoCorrect results.
- (void)entriesDidChange {
    [[CacheManager sharedInstance] removeAllArrays];
}

// Values are stored as the Bangla they produce. Like Windows Avro, a value
// typed in Roman phonetic is transliterated; Bangla, symbols and emoticons
// (value same as the term, e.g. ":-P") are kept as typed.
- (NSString *)correctionForValue:(NSString *)value term:(NSString *)term {
    if (!value) {
        return nil;
    }
    NSCharacterSet *latin = [NSCharacterSet characterSetWithCharactersInString:
        @"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ"];
    BOOL hasBangla = [value rangeOfString:@"[\u0980-\u09FF]"
                                  options:NSRegularExpressionSearch].location != NSNotFound;
    if (hasBangla || [value rangeOfCharacterFromSet:latin].location == NSNotFound) {
        return value;
    }
    BOOL phoneticWord = [term rangeOfString:@"^"].location != NSNotFound ||
        [term rangeOfString:@"^[A-Za-z]{2,}:$" options:NSRegularExpressionSearch].location != NSNotFound;
    if (term && !phoneticWord && [value caseInsensitiveCompare:term] == NSOrderedSame &&
        [term rangeOfString:@"[A-Za-z]{3,}" options:NSRegularExpressionSearch].location == NSNotFound &&
        [term rangeOfString:@"[^A-Za-z]" options:NSRegularExpressionSearch].location != NSNotFound) {
        return value;
    }
    return [[AvroParser sharedInstance] parse:value];
}

// Windows Avro .dct format: "term value" per line, "//" lines are comments.
+ (NSDictionary *)entriesFromDictionaryFile:(NSString *)path error:(NSError **)error {
    NSString *contents = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:error];
    if (!contents) {
        return nil;
    }
    NSMutableDictionary *entries = [NSMutableDictionary dictionary];
    for (NSString *rawLine in [contents componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]]) {
        NSString *line = [rawLine stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        if ([line length] == 0 || [line hasPrefix:@"/"]) {
            continue;
        }
        NSRange space = [line rangeOfCharacterFromSet:[NSCharacterSet whitespaceCharacterSet]];
        if (space.location == NSNotFound) {
            continue;
        }
        NSString *value = [[line substringFromIndex:NSMaxRange(space)]
            stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        if ([value length] > 0) {
            [entries setObject:value forKey:[line substringToIndex:space.location]];
        }
    }
    return entries;
}

@end
