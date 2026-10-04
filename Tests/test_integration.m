//
//  test_integration.m
//  Avro Keyboard
//
//  Drives the REAL AvroKeyboardController with a MockClient, the way Lekho's
//  integration tests drive its real controller. This is the suite that replaces
//  mirrored logic: every assertion below goes through production code paths.
//
//  Two harnesses details matter:
//  - Apple's initWithServer:delegate:client: throws for a non-genuine client,
//    so controllers are built with nil and the mock is injected into
//    _currentClient (retained, mirroring what init does).
//  - TestableController answers -client with the mock, which restores the
//    paths that consult it (English-mode gating).
//  - HOME is sandboxed to a fresh temp dir so weight.plist writes and user
//    defaults never touch the real home directory.
//

#import <Foundation/Foundation.h>
#import <objc/runtime.h>

#import "AvroKeyboardController.h"
#import "LanguageMode.h"
#import "MockClient.h"
#import "TestableController.h"
#import "TestHarness.h"

@interface AvroKeyboardController (Testing)
- (NSArray *)candidates:(id)sender;
- (void)candidateSelected:(id)candidate;
- (void)deleteBackward:(id)sender;
- (void)cancelOperation:(id)sender;
- (void)commitComposition:(id)sender;
- (void)deactivateServer:(id)sender;
- (IBAction)toggleEnglishModeForCurrentApp:(id)sender;
- (BOOL)isEnglishModeActive;
@end

static void InjectClient(AvroKeyboardController *controller, MockClient *client) {
  Ivar iv = class_getInstanceVariable([AvroKeyboardController class], "_currentClient");
  NSCAssert(iv, @"_currentClient ivar missing");
  object_setIvar(controller, iv, client);
  [client retain]; // the controller's share, mirroring init's retain
}

static AvroKeyboardController *NewPlainController(MockClient *client) {
  AvroKeyboardController *c = [[AvroKeyboardController alloc]
      initWithServer:nil delegate:nil client:nil];
  NSCAssert(c, @"controller init failed");
  InjectClient(c, client);
  return [c autorelease];
}

static TestableController *NewTestableController(MockClient *client) {
  TestableController *c = [[TestableController alloc]
      initWithServer:nil delegate:nil client:nil];
  NSCAssert(c, @"controller init failed");
  InjectClient(c, client);
  [c setTestClient:client];
  return [c autorelease];
}

static void SetDefaults(BOOL inlineBangla, BOOL dictionary) {
  NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
  [d setBool:inlineBangla forKey:@"ShowInlineBangla"];
  [d setBool:dictionary forKey:@"IncludeDictionary"];
  [d setBool:NO forKey:@"EnableAutoCorrect"];
  [d setBool:dictionary forKey:@"EnableSuggestions"];
  [d setBool:NO forKey:@"EnableJoNukta"];
}

static void TypeString(AvroKeyboardController *c, MockClient *m, NSString *s) {
  for (NSUInteger i = 0; i < [s length]; i++) {
    [c inputText:[s substringWithRange:NSMakeRange(i, 1)] client:m];
  }
}

static NSString *Composed(AvroKeyboardController *c, MockClient *m) {
  return [[c composedString:m] string];
}

static void testTypingCommitsBangla(void) {
  SECTION("typing commits Bangla through the real controller");
  MockClient *m = [[[MockClient alloc] init] autorelease];
  AvroKeyboardController *c = NewPlainController(m);
  SetDefaults(YES, NO); // dictionary off: the only candidate is the parse

  CHECK([c inputText:@"a" client:m] == YES, "letters are consumed");
  TypeString(c, m, @"mi");
  CHECK([Composed(c, m) isEqualToString:@"আমি"],
        "inline preview shows the transliteration");
  CHECK([c inputText:@" " client:m] == NO, "space passes through");
  CHECK([[m committed] isEqualToString:@"আমি"], "space commits আমি");
  CHECK([[m marked] length] == 0, "no marked text remains");
}

static void testInlineToggle(void) {
  SECTION("inline preview toggle");
  MockClient *m = [[[MockClient alloc] init] autorelease];
  AvroKeyboardController *c = NewPlainController(m);

  SetDefaults(YES, NO);
  TypeString(c, m, @"am");
  CHECK([Composed(c, m) isEqualToString:@"আম"], "inline on shows transliteration");

  SetDefaults(NO, NO);
  // A fresh controller reflects the new default.
  MockClient *m2 = [[[MockClient alloc] init] autorelease];
  AvroKeyboardController *c2 = NewPlainController(m2);
  TypeString(c2, m2, @"am");
  CHECK([Composed(c2, m2) isEqualToString:@"am"], "inline off shows raw letters");
}

static void testEscRevertsToLiteral(void) {
  SECTION("Esc reverts to the literal keystrokes");
  MockClient *m = [[[MockClient alloc] init] autorelease];
  AvroKeyboardController *c = NewPlainController(m);
  SetDefaults(YES, NO);

  TypeString(c, m, @"ami");
  CHECK([c didCommandBySelector:@selector(cancelOperation:) client:m] == YES,
        "Esc is claimed while composing");
  CHECK([[m committed] isEqualToString:@"ami"], "Esc inserts the literal text");
  CHECK([Composed(c, m) length] == 0, "composition is cleared");

  CHECK([c didCommandBySelector:@selector(cancelOperation:) client:m] == NO,
        "Esc with nothing composing passes through");
  CHECK([[m committed] isEqualToString:@"ami"], "nothing further committed");
}

static void testEmptyInputPaths(void) {
  SECTION("empty-input paths are safe");
  MockClient *m = [[[MockClient alloc] init] autorelease];
  AvroKeyboardController *c = NewPlainController(m);
  SetDefaults(YES, NO);

  CHECK([c inputText:@" " client:m] == NO, "space with no composition passes");
  CHECK([[m committed] length] == 0, "nothing committed");

  BOOL crashed = NO;
  @try {
    [c deleteBackward:m];
  } @catch (NSException *e) {
    crashed = YES;
  }
  CHECK(!crashed, "backspace on empty buffer does not raise");
  CHECK([Composed(c, m) length] == 0, "still nothing composing");
}

static void testDeleteBackwardStepsBack(void) {
  SECTION("backspace steps back through the composition");
  MockClient *m = [[[MockClient alloc] init] autorelease];
  AvroKeyboardController *c = NewPlainController(m);
  SetDefaults(YES, NO);

  TypeString(c, m, @"ami");
  [c deleteBackward:m];
  CHECK([Composed(c, m) isEqualToString:@"আম"], "one backspace leaves আম");
  [c deleteBackward:m];
  [c deleteBackward:m];
  CHECK([Composed(c, m) length] == 0, "deleting everything clears");
}

static void testCommitComposition(void) {
  SECTION("commitComposition inserts the display string");
  MockClient *m = [[[MockClient alloc] init] autorelease];
  AvroKeyboardController *c = NewPlainController(m);
  SetDefaults(YES, NO);

  TypeString(c, m, @"ami");
  [c commitComposition:m];
  CHECK([[m committed] isEqualToString:@"আমি"], "commit inserts আমি");
  CHECK([Composed(c, m) length] == 0, "buffer cleared");
}

static void testTypoCandidateOffered(void) {
  SECTION("doubled-letter typo is offered, end to end");
  MockClient *m = [[[MockClient alloc] init] autorelease];
  AvroKeyboardController *c = NewPlainController(m);
  SetDefaults(YES, YES);

  TypeString(c, m, @"kothha");
  NSArray *list = [c candidates:m];
  CHECK([list containsObject:@"কথা"], "কথা is among the candidates for kothha");
  [c inputText:@" " client:m];
  CHECK([[m committed] length] > 0, "space commits something");
}

static void testFirstSpaceAfterLaunch(void) {
  SECTION("first space after launch (B3 regression)");
  MockClient *m = [[[MockClient alloc] init] autorelease];
  AvroKeyboardController *c = NewPlainController(m);
  SetDefaults(YES, NO);

  BOOL crashed = NO;
  @try {
    [c inputText:@"a" client:m];
    [c inputText:@" " client:m];
  } @catch (NSException *e) {
    crashed = YES;
  }
  CHECK(!crashed, "no crash on the first space");
  CHECK([[m committed] length] > 0, "something committed");
}

static void testEnglishModePassThrough(void) {
  SECTION("English mode passes keys through untouched");
  MockClient *m = [[[MockClient alloc] init] autorelease];
  [m setBundleIdentifier:@"com.apple.Terminal"]; // default-on list
  TestableController *c = NewTestableController(m);
  SetDefaults(YES, YES);

  CHECK([c isEnglishModeActive], "Terminal is English by default");
  CHECK([c inputText:@"k" client:m] == NO, "keys pass through");
  CHECK([Composed(c, m) length] == 0, "nothing composes");
  CHECK([[m committed] length] == 0, "nothing committed");
}

static void testEnglishModeSwitchCommitsFirst(void) {
  SECTION("switching to English mid-word commits first");
  MockClient *m = [[[MockClient alloc] init] autorelease];
  TestableController *c = NewTestableController(m);
  SetDefaults(YES, NO);

  TypeString(c, m, @"am");
  CHECK([Composed(c, m) length] > 0, "composition in flight");
  [m setBundleIdentifier:@"com.apple.Terminal"];
  CHECK([c inputText:@"i" client:m] == NO, "returns NO after switching");
  CHECK([[m committed] isEqualToString:@"আম"],
        "pending composition committed, not lost");
  CHECK([c inputText:@"x" client:m] == NO, "further keys pass through");
  CHECK([[m committed] isEqualToString:@"আম"], "nothing further composed");
}

static void testToggleFlipsStoredMode(void) {
  SECTION("menu toggle flips the stored mode");
  MockClient *m = [[[MockClient alloc] init] autorelease];
  [m setBundleIdentifier:@"com.test.editor"];
  TestableController *c = NewTestableController(m);
  SetDefaults(YES, NO);

  CHECK(![c isEnglishModeActive], "starts in Bangla");
  [c toggleEnglishModeForCurrentApp:m];
  CHECK([c isEnglishModeActive], "toggle switches to English");
  CHECK([c inputText:@"k" client:m] == NO, "and keys pass through");
  [c toggleEnglishModeForCurrentApp:m];
  CHECK(![c isEnglishModeActive], "toggle switches back to Bangla");
  [LanguageMode clearOverrideForBundleIdentifier:@"com.test.editor"];
}

static void testDeactivateIsSafe(void) {
  SECTION("deactivate with composition in flight");
  MockClient *m = [[[MockClient alloc] init] autorelease];
  AvroKeyboardController *c = NewPlainController(m);
  SetDefaults(YES, NO);

  TypeString(c, m, @"am");
  BOOL crashed = NO;
  @try {
    [c deactivateServer:m];
  } @catch (NSException *e) {
    crashed = YES;
  }
  CHECK(!crashed, "deactivate does not raise");
}

int main(int argc, char *argv[]) {
  NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];

  // Sandbox HOME so weight.plist writes and user defaults never touch the
  // real home directory. Must run before anything touches disk.
  char sandbox[] = "/tmp/avro-integ-XXXXXX";
  NSCAssert(mkdtemp(sandbox), @"mkdtemp failed");
  setenv("HOME", sandbox, 1);

  @autoreleasepool {
    testTypingCommitsBangla();
    testInlineToggle();
    testEscRevertsToLiteral();
    testEmptyInputPaths();
    testDeleteBackwardStepsBack();
    testCommitComposition();
    testTypoCandidateOffered();
    testFirstSpaceAfterLaunch();
    testEnglishModePassThrough();
    testEnglishModeSwitchCommitsFirst();
    testToggleFlipsStoredMode();
    testDeactivateIsSafe();
  }
  int rc = test_report("test_integration");
  [pool release];
  return rc;
}
