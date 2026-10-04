//
//  MockClient.m
//  Avro Keyboard
//

#import "MockClient.h"

@implementation MockClient

@synthesize bundleIdentifier = _bundleIdentifier;

- (id)init {
  self = [super init];
  if (self) {
    _committed = [[NSMutableString alloc] init];
    _marked = [[NSMutableString alloc] init];
    _bundleIdentifier = [@"com.apple.TextEdit" copy];
  }
  return self;
}

- (void)dealloc {
  [_committed release];
  [_marked release];
  [_bundleIdentifier release];
  [super dealloc];
}

- (NSString *)committed {
  return [[_committed copy] autorelease];
}

- (NSString *)marked {
  return [[_marked copy] autorelease];
}

- (void)reset {
  [_committed setString:@""];
  [_marked setString:@""];
}

- (void)insertText:(id)string replacementRange:(NSRange)range {
  NSString *text = nil;
  if ([string isKindOfClass:[NSAttributedString class]]) {
    text = [(NSAttributedString *)string string];
  } else if ([string isKindOfClass:[NSString class]]) {
    text = (NSString *)string;
  }
  if (text) {
    [_committed appendString:text];
  }
  [_marked setString:@""];
}

- (void)setMarkedText:(id)string
       selectionRange:(NSRange)selectionRange
     replacementRange:(NSRange)replacementRange {
  NSString *text = nil;
  if ([string isKindOfClass:[NSAttributedString class]]) {
    text = [(NSAttributedString *)string string];
  } else if ([string isKindOfClass:[NSString class]]) {
    text = (NSString *)string;
  }
  [_marked setString:(text ? text : @"")];
}

- (NSRange)selectedRange {
  return NSMakeRange([_committed length], 0);
}

- (NSRange)markedRange {
  if ([_marked length] == 0) {
    return NSMakeRange(NSNotFound, 0);
  }
  return NSMakeRange([_committed length], [_marked length]);
}

- (BOOL)supportsUnicode {
  return YES;
}

@end
