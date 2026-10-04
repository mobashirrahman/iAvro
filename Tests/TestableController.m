//
//  TestableController.m
//  Avro Keyboard
//

#import "TestableController.h"

@implementation TestableController

- (void)setTestClient:(id)client {
  [client retain];
  [_testClient release];
  _testClient = client;
}

- (void)dealloc {
  [_testClient release];
  [super dealloc];
}

- (id)client {
  return _testClient;
}

@end
