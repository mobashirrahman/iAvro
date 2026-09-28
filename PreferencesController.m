//
//  AvroKeyboard
//
//  Created by Rifat Nabi on 6/25/12.
//  Copyright (c) 2012 OmicronLab. All rights reserved.
//

#import "PreferencesController.h"
#import "AutoCorrect.h"
#import "AutoCorrectItem.h"
#import "SettingsKeys.h"

@implementation PreferencesController

@synthesize autoCorrectItemsArray = _autoCorrectItemsArray;

- (id)init {
  self = [super init];
  if (self) {
    // Snapshot: never enumerate the singleton's live mutable dictionary.
    NSDictionary *autoCorrectEntries =
        [[[[AutoCorrect sharedInstance] autoCorrectEntries] copy] autorelease];
    _autoCorrectItemsArray = [[NSMutableArray alloc] init];
    for (id key in autoCorrectEntries) {
      AutoCorrectItem *item = [[AutoCorrectItem alloc] init];
      item.replace = key;
      item.with = [autoCorrectEntries objectForKey:key];
      [_autoCorrectItemsArray addObject:item];
      [item release];
    }
  }
  return self;
}

- (void)dealloc {
  [_autoCorrectItemsArray release];
  [super dealloc];
}

- (void)awakeFromNib {
  // Before sizing the window: this grows the General view.
  [self addGeneralToggles];

  [[self window] setContentSize:[_generalView frame].size];
  [[[self window] contentView] addSubview:_generalView];
  [[[self window] contentView] setWantsLayer:YES];

  // Load Credits
  [_aboutContent
      readRTFDFromFile:[[NSBundle mainBundle] pathForResource:@"Credits"
                                                       ofType:@"rtfd"]];
  [_aboutContent scrollToBeginningOfDocument:_aboutContent];
}

- (NSRect)newFrameForNewContentView:(NSView *)view {
  NSWindow *window = [self window];
  NSRect newFrameRect = [window frameRectForContentRect:[view frame]];
  NSRect oldFrameRect = [window frame];
  NSSize newSize = newFrameRect.size;
  NSSize oldSize = oldFrameRect.size;

  NSRect frame = [window frame];
  frame.size = newSize;
  frame.origin.y -= (newSize.height - oldSize.height);

  return frame;
}

- (NSView *)viewForTag:(NSInteger)tag {
  NSView *view = nil;
  switch (tag) {
  case 0:
    view = _generalView;
    break;
  case 1:
    view = _autoCorrectView;
    break;
  default:
    view = _aboutView;
    break;
  }
  return view;
}

- (BOOL)validateToolbarItem:(NSToolbarItem *)item {
  if ([item tag] == _currentViewTag) {
    return NO;
  }
  return YES;
}

- (IBAction)switchView:(id)sender {
  NSInteger tag = [sender tag];
  NSView *view = [self viewForTag:tag];
  NSView *previousView = [self viewForTag:_currentViewTag];
  _currentViewTag = tag;
  NSRect newFrame = [self newFrameForNewContentView:view];

  [NSAnimationContext beginGrouping];

  if ([[NSApp currentEvent] modifierFlags] & NSEventModifierFlagShift) {
    [[NSAnimationContext currentContext] setDuration:1.0];
  }

  [[[[self window] contentView] animator] replaceSubview:previousView
                                                    with:view];
  [[[self window] animator] setFrame:newFrame display:YES];

  [NSAnimationContext endGrouping];
}

- (IBAction)changePredicate:(id)sender {
  NSString *searchTerm = [[sender stringValue]
      stringByTrimmingCharactersInSet:[NSCharacterSet
                                          whitespaceAndNewlineCharacterSet]];
  NSPredicate *predicate = nil;
  if ([searchTerm length]) {
    predicate = [NSPredicate
        predicateWithFormat:@"(replace CONTAINS[c] %@) OR (with CONTAINS %@)",
                            searchTerm, searchTerm];
  }
  [_autoCorrectController setFilterPredicate:predicate];
}

static const NSInteger kFirstGeneralToggleTag = 1001;
static const CGFloat kToggleRowHeight = 22.0;

// Checkboxes added in code, in display order: { title, defaults key }.
// New phonetic options go here rather than in the nib.
- (NSArray *)generalToggles {
  return [NSArray arrayWithObjects:
      [NSArray arrayWithObjects:@"Enable Suggestions", kEnableSuggestionsDefaultsKey, nil],
      [NSArray arrayWithObjects:@"Enable AutoCorrect", kEnableAutoCorrectDefaultsKey, nil],
      [NSArray arrayWithObjects:@"Show Bengali inline while typing", kShowInlineBanglaDefaultsKey, nil],
      nil];
}

// Grows the General view and stacks the toggles under the nib's own
// controls. They used to sit at fixed offsets that overlapped the nib's
// checkboxes.
- (void)addGeneralToggles {
  if (!_generalView) {
    return;
  }
  // awakeFromNib can run more than once; don't stack duplicates.
  if ([_generalView viewWithTag:kFirstGeneralToggleTag]) {
    return;
  }

  NSArray *toggles = [self generalToggles];
  CGFloat added = kToggleRowHeight * [toggles count];

  // Make room at the bottom by shifting the nib's controls up. Autoresizing
  // is off meanwhile, or their flexible margins would move them twice.
  BOOL autoresizes = [_generalView autoresizesSubviews];
  [_generalView setAutoresizesSubviews:NO];
  NSRect viewFrame = [_generalView frame];
  viewFrame.size.height += added;
  [_generalView setFrame:viewFrame];
  for (NSView *subview in [_generalView subviews]) {
    NSPoint origin = [subview frame].origin;
    origin.y += added;
    [subview setFrameOrigin:origin];
  }
  [_generalView setAutoresizesSubviews:autoresizes];

  NSUInteger i;
  for (i = 0; i < [toggles count]; i++) {
    NSArray *spec = [toggles objectAtIndex:i];
    // 18pt matches the nib's bottom margin
    CGFloat y = 18.0 + added - kToggleRowHeight * (i + 1);
    NSButton *toggle =
        [[NSButton alloc] initWithFrame:NSMakeRect(198.0, y, 250.0, 18.0)];
    [toggle setTag:kFirstGeneralToggleTag + i];
    [toggle setButtonType:NSSwitchButton];
    [toggle setTitle:[spec objectAtIndex:0]];
    [toggle setBezelStyle:NSBezelStyleRegularSquare];
    [toggle setAutoresizingMask:(NSViewMaxXMargin | NSViewMinYMargin)];
    [toggle bind:@"value"
           toObject:[NSUserDefaultsController sharedUserDefaultsController]
        withKeyPath:[NSString stringWithFormat:@"values.%@",
                                               [spec objectAtIndex:1]]
            options:nil];
    [_generalView addSubview:toggle];
    [toggle release];
  }
}

@end
