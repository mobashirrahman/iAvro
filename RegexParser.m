//
//  AvroKeyboard
//
//  Created by Rifat Nabi on 6/22/12.
//  Copyright (c) 2012 OmicronLab. All rights reserved.
//

#import "RegexParser.h"

static RegexParser* sharedInstance = nil;

@implementation RegexParser

+ (RegexParser *)sharedInstance  {
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

static NSString *RegexNonNilString(id value) {
    return [value isKindOfClass:[NSString class]] ? value : @"";
}

- (NSDictionary *)loadTableDictionary {
    NSString *filePath = [[NSBundle mainBundle] pathForResource:@"regex" ofType:@"json"];
    if (!filePath) {
        return nil;
    }
    NSData *jsonData = [NSData dataWithContentsOfFile:filePath
                                              options:NSDataReadingUncached
                                                error:NULL];
    if (!jsonData) {
        return nil;
    }
    id table = [NSJSONSerialization JSONObjectWithData:jsonData
                                               options:0
                                                 error:NULL];
    return [table isKindOfClass:[NSDictionary class]] ? table : nil;
}

- (id)init {
    self = [super init];
    if (self) {
        NSDictionary *jsonArray = [self loadTableDictionary];
        if (!jsonArray) {
            // Same contract as AvroParser: a missing or corrupt table
            // degrades to passthrough instead of killing the input method.
            NSLog(@"RegexParser: regex.json missing or corrupt; dictionary search disabled");
            jsonArray = [NSDictionary dictionary];
        }
        _vowel = [[NSString alloc] initWithString:RegexNonNilString([jsonArray objectForKey:@"vowel"])];
        _consonant = [[NSString alloc] initWithString:RegexNonNilString([jsonArray objectForKey:@"consonant"])];
        _casesensitive = [[NSString alloc] initWithString:RegexNonNilString([jsonArray objectForKey:@"casesensitive"])];
        id rawPatterns = [jsonArray objectForKey:@"patterns"];
        _patterns = [[NSArray alloc] initWithArray:([rawPatterns isKindOfClass:[NSArray class]]
                                                    ? rawPatterns : [NSArray array])];
        id firstFind = [_patterns count] > 0 ? [[_patterns objectAtIndex:0] objectForKey:@"find"] : nil;
        _maxPatternLength = [firstFind isKindOfClass:[NSString class]] ? [firstFind length] : 0;
        // Order-independent lookup: the table is not guaranteed to be
        // in valid binary-search order, so build a hash index (last
        // duplicate wins, matching previous observable behavior).
        NSMutableDictionary *patternDict = [[NSMutableDictionary alloc] initWithCapacity:[_patterns count]];
        for (id entry in _patterns) {
            if (![entry isKindOfClass:[NSDictionary class]]) {
                continue;
            }
            NSString *key = [entry objectForKey:@"find"];
            if ([key isKindOfClass:[NSString class]]) {
                [patternDict setObject:entry forKey:key];
            }
        }
        _patternDict = patternDict;
    }
    return self;
}

- (void)dealloc {
    [_vowel release];
    [_consonant release];
    [_casesensitive release];
    [_patterns release];
    [_patternDict release];

    [super dealloc];
}

- (NSString*)parse:(NSString *)string {
    if (!string || [string length] == 0) {
        return string;
    }
    
    NSString* fixed = [self clean:string];
    NSMutableString* output = [[NSMutableString alloc] initWithCapacity:0];
    
    NSInteger len = [fixed length], cur;
    for(cur = 0; cur < len; ++cur) {
        NSInteger start = cur, end;
        BOOL matched = FALSE;
        
        NSInteger chunkLen;
        for(chunkLen = _maxPatternLength; chunkLen > 0; --chunkLen) {
            end = start + chunkLen;
            if(end <= len) {
                NSString* chunk = [fixed substringWithRange:NSMakeRange(start, chunkLen)];
                
                // Order-independent hash lookup. The table is not guaranteed
                // to be in valid binary-search order, so binary search could
                // silently miss patterns.
                NSDictionary* pattern = [_patternDict objectForKey:chunk];
                if (pattern) {
                        NSArray* rules = [pattern objectForKey:@"rules"];
                        for(NSDictionary* rule in rules) {
                            
                            BOOL replace = TRUE;
                            NSInteger chk = 0;
                            NSArray* matches = [rule objectForKey:@"matches"];
                            for(NSDictionary* match in matches) {
                                NSString* value = [match objectForKey:@"value"];
                                NSString* type = [match objectForKey:@"type"];
                                NSString* scope = [match objectForKey:@"scope"];
                                BOOL isNegative = [[match objectForKey:@"negative"] boolValue];
                                
                                if([type isEqualToString:@"suffix"]) {
                                    chk = end;
                                } 
                                // Prefix
                                else {
                                    chk = start - 1;
                                }
                                
                                // Beginning
                                if([scope isEqualToString:@"punctuation"]) {
                                    if(
                                       ! (
                                          (chk < 0 && [type isEqualToString:@"prefix"]) || 
                                          (chk >= len && [type isEqualToString:@"suffix"]) || 
                                          [self isPunctuation:[fixed characterAtIndex:chk]]
                                          ) ^ isNegative
                                       ) {
                                        replace = FALSE;
                                        break;
                                    }
                                }
                                // Vowel
                                else if([scope isEqualToString:@"vowel"]) {
                                    if(
                                       ! (
                                          (
                                           (chk >= 0 && [type isEqualToString:@"prefix"]) || 
                                           (chk < len && [type isEqualToString:@"suffix"])
                                           ) && 
                                          [self isVowel:[fixed characterAtIndex:chk]]
                                          ) ^ isNegative
                                       ) {
                                        replace = FALSE;
                                        break;
                                    }
                                }
                                // Consonant
                                else if([scope isEqualToString:@"consonant"]) {
                                    if(
                                       ! (
                                          (
                                           (chk >= 0 && [type isEqualToString:@"prefix"]) || 
                                           (chk < len && [type isEqualToString:@"suffix"])
                                           ) && 
                                          [self isConsonant:[fixed characterAtIndex:chk]]
                                          ) ^ isNegative
                                       ) {
                                        replace = FALSE;
                                        break;
                                    }
                                }
                                // Exact
                                else if([scope isEqualToString:@"exact"]) {
                                    NSInteger s, e;
                                    if([type isEqualToString:@"suffix"]) {
                                        s = end;
                                        e = end + [value length];
                                    } 
                                    // Prefix
                                    else {
                                        s = start - [value length];
                                        e = start;
                                    }
                                    if(![self isExact:value heystack:fixed start:(int)s end:(int)e not:isNegative]) {
                                        replace = FALSE;
                                        break;
                                    }
                                }
                            }
                            
                            if(replace) {
                                [output appendString:[rule objectForKey:@"replace"]];
                                [output appendString:@"(্[যবম])?(্?)([ঃঁ]?)"];
                                cur = end - 1;
                                matched = TRUE;
                                break;
                            }
                            
                        }
                        
                        if(matched == TRUE) break;
                        
                        // Default
                        [output appendString:[pattern objectForKey:@"replace"]];
                        [output appendString:@"(্[যবম])?(্?)([ঃঁ]?)"];
                        cur = end - 1;
                        matched = TRUE;
                }
                if(matched == TRUE) break;                
            }
        }
        
        if(!matched) {
            unichar oldChar = [fixed characterAtIndex:cur];
            [output appendString:[NSString stringWithCharacters:&oldChar length:1]];
        }
        // NSLog(@"cur: %s, start: %s, end: %s, prev: %s\n", cur, start, end, prev);
    }
    
    [output autorelease];
    
    return output;
}

- (BOOL)isVowel:(unichar)c {
    // Making it lowercase for checking
    c = [self smallCap:c];
    NSInteger i, len = [_vowel length];
    for (i = 0; i < len; ++i) {
        if ([_vowel characterAtIndex:i] == c) {
            return TRUE;
        }
    }
    return FALSE;
}

- (BOOL)isConsonant:(unichar)c {
    // Making it lowercase for checking
    c = [self smallCap:c];
    NSInteger i, len = [_consonant length];
    for (i = 0; i < len; ++i) {
        if ([_consonant characterAtIndex:i] == c) {
            return TRUE;
        }
    }
    return FALSE;
}

- (BOOL)isPunctuation:(unichar)c {
    return !([self isVowel:c] || [self isConsonant:c]);
}

- (BOOL)isCaseSensitive:(unichar)c {
    // Making it lowercase for checking
    c = [self smallCap:c];
    NSInteger i, len = [_casesensitive length];
    for (i = 0; i < len; ++i) {
        if ([_casesensitive characterAtIndex:i] == c) {
            return TRUE;
        }
    }
    return FALSE;
}

- (BOOL)isExact:(NSString*) needle heystack:(NSString*)heystack start:(int)start end:(int)end not:(BOOL)not {
    int len = end - start;
    if (len < 0) {
        return (NO ^ not);
    }
    return ((start >= 0 && end <= (int)[heystack length]
             && [[heystack substringWithRange:NSMakeRange(start, len)] isEqualToString:needle]) ^ not);
}

- (unichar)smallCap:(unichar) letter {
    if(letter >= 'A' && letter <= 'Z') {
        letter = letter - 'A' + 'a';
    }
    return letter;
}

- (NSString*)clean:(NSString *)string {
    NSMutableString* fixed = [[NSMutableString alloc] initWithCapacity:0];
    NSInteger i, len = [string length];
    for (i = 0; i < len; ++i) {
        unichar c = [string characterAtIndex:i];
        // regex.json's "casesensitive" set is the regex metacharacters
        // (|()[]{}^$*+?. etc.), not case-sensitive letters. They are dropped
        // on purpose so they can't be injected into the dictionary regex
        // (e.g. "ki(re" would otherwise compile to an invalid pattern).
        if (![self isCaseSensitive:c]) {
            [fixed appendFormat:@"%C", [self smallCap:c]];
        }
    }
    [fixed autorelease];
    return fixed;
}

@end
