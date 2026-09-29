//
//  UserDictionary.h
//  Avro Keyboard
//
//  Serialises and parses the user's own data: AutoCorrect entries and learned
//  selection counts. Deliberately Foundation-only so it can be unit tested
//  without a window server.
//

#import <Foundation/Foundation.h>

@interface UserDictionary : NSObject

// Both stores in one file, so a single Export produces a complete backup.
// Rows are "<kind><TAB><key><TAB><value>"; kind is "autocorrect" or "learned".
+ (NSString *)textForAutoCorrectEntries:(NSDictionary *)entries
                          learnedCounts:(NSDictionary *)counts
                             appVersion:(NSString *)version;

// Accepts the current format and the older two-column "term value" form used
// by the first importer, so existing files keep working. Returns nil only when
// the text is unusable. Callers get:
//   "autocorrect" -> NSDictionary of key -> value
//   "learned"     -> NSDictionary of word -> NSNumber count
//   "legacy"      -> NSNumber BOOL, YES when rows were two-column
+ (NSDictionary *)parseText:(NSString *)text;

+ (BOOL)writeText:(NSString *)text
           toPath:(NSString *)path
            error:(NSError **)error;

@end
