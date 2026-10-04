//
//  TestableController.h
//  Avro Keyboard
//
//  Test-only subclass that answers -client with an injected mock. Apple's
//  IMKInputController refuses a non-genuine client object, so the real
//  initializer can only be driven with nil; overriding -client restores the
//  paths that consult it (English-mode gating, per-app menu state) without
//  touching production code.
//

#import "AvroKeyboardController.h"

@interface TestableController : AvroKeyboardController {
  id _testClient;
}

- (void)setTestClient:(id)client;

@end
