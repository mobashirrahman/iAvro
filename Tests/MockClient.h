//
//  MockClient.h
//  Avro Keyboard
//
//  A test double for the application side of an input session. Implements the
//  IMKTextInput methods AvroKeyboardController actually calls, recording what
//  the controller commits as inline text and what it shows as marked
//  (composing) text.
//
//  Deliberately duck-typed rather than declaring <IMKTextInput> conformance:
//  that protocol lives in Carbon's HIToolbox headers, and the controller only
//  ever talks to `id`, so conformance would buy nothing but a heavy import.
//

#import <Foundation/Foundation.h>

@interface MockClient : NSObject {
  NSMutableString *_committed;
  NSMutableString *_marked;
  NSString *_bundleIdentifier;
}

@property (nonatomic, readonly) NSString *committed;
@property (nonatomic, readonly) NSString *marked;
@property (nonatomic, copy) NSString *bundleIdentifier;

- (void)reset;

@end
