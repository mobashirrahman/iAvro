//
//  AvroKeyboard
//
//  Created by Rifat Nabi on 6/24/12.
//  Copyright (c) 2012 OmicronLab. All rights reserved.
//

#import "AutoCorrect.h"
#import "AvroParser.h"

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
}

@end
