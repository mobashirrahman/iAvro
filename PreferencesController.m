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
#import "AvroParser.h"

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
  if (_addButton) {
    [_autoCorrectController removeObserver:self forKeyPath:@"selectionIndexes"];
  }
  [_replaceField release];
  [_withField release];
  [_previewLabel release];
  [_addButton release];
  [_deleteButton release];
  [_autoCorrectItemsArray release];
  [super dealloc];
}

- (void)awakeFromNib {
  // Before sizing the window: these grow their views.
  [self addGeneralToggles];
  [self addAutoCorrectEditor];

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
      [NSArray arrayWithObjects:@"Offer typed English as the last suggestion", kOfferEnglishDefaultsKey, nil],
      [NSArray arrayWithObjects:@"Preselect exact transliteration, not dictionary word", kPreferTransliterationDefaultsKey, nil],
      [NSArray arrayWithObjects:@"Classic phonetic: no suggestion window", kClassicPhoneticDefaultsKey, nil],
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

#pragma mark - AutoCorrect editor

static const CGFloat kEditorHeight = 64.0;

- (NSTextField *)editorFieldWithFrame:(NSRect)frame placeholder:(NSString *)placeholder {
  NSTextField *field = [[NSTextField alloc] initWithFrame:frame];
  [[field cell] setPlaceholderString:placeholder];
  [[field cell] setScrollable:YES];
  [field setDelegate:self];
  [field setAutoresizingMask:(NSViewMaxXMargin | NSViewMaxYMargin)];
  [_autoCorrectView addSubview:field];
  return field;
}

- (NSButton *)editorButtonWithFrame:(NSRect)frame title:(NSString *)title action:(SEL)action {
  NSButton *button = [[NSButton alloc] initWithFrame:frame];
  [button setBezelStyle:NSBezelStyleRounded];
  [button setTitle:title];
  [button setTarget:self];
  [button setAction:action];
  [button setAutoresizingMask:(NSViewMinXMargin | NSViewMaxYMargin)];
  [_autoCorrectView addSubview:button];
  return button;
}

// Ported from Windows Avro's AutoCorrect editor: add, update, delete and
// import entries. The nib only has a read-only list, so the controls are
// added here under the table.
- (void)addAutoCorrectEditor {
  if (!_autoCorrectView || _addButton) {
    return;
  }
  BOOL autoresizes = [_autoCorrectView autoresizesSubviews];
  [_autoCorrectView setAutoresizesSubviews:NO];
  NSRect viewFrame = [_autoCorrectView frame];
  viewFrame.size.height += kEditorHeight;
  [_autoCorrectView setFrame:viewFrame];
  for (NSView *subview in [_autoCorrectView subviews]) {
    NSPoint origin = [subview frame].origin;
    origin.y += kEditorHeight;
    [subview setFrameOrigin:origin];
  }
  [_autoCorrectView setAutoresizesSubviews:autoresizes];

  _replaceField = [self editorFieldWithFrame:NSMakeRect(20, 50, 120, 22)
                                 placeholder:@"Replace"];
  _withField = [self editorFieldWithFrame:NSMakeRect(146, 50, 150, 22)
                              placeholder:@"With (Roman or Bangla)"];
  _addButton = [self editorButtonWithFrame:NSMakeRect(298, 44, 138, 32)
                                     title:@"Add/Update"
                                    action:@selector(addOrUpdateAutoCorrect:)];
  _deleteButton = [self editorButtonWithFrame:NSMakeRect(298, 12, 69, 32)
                                        title:@"Delete"
                                       action:@selector(deleteAutoCorrect:)];
  [[self editorButtonWithFrame:NSMakeRect(367, 12, 69, 32)
                         title:@"Import…"
                        action:@selector(importAutoCorrect:)] release];

  _previewLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(20, 20, 276, 17)];
  [_previewLabel setEditable:NO];
  [_previewLabel setBordered:NO];
  [_previewLabel setDrawsBackground:NO];
  [_previewLabel setTextColor:[NSColor secondaryLabelColor]];
  [_previewLabel setAutoresizingMask:(NSViewMaxXMargin | NSViewMaxYMargin)];
  [_autoCorrectView addSubview:_previewLabel];

  [_autoCorrectController addObserver:self
                           forKeyPath:@"selectionIndexes"
                              options:0
                              context:NULL];
  [self updateAutoCorrectEditor];
}

- (void)observeValueForKeyPath:(NSString *)keyPath
                      ofObject:(id)object
                        change:(NSDictionary *)change
                       context:(void *)context {
  if (object == _autoCorrectController) {
    NSArray *selected = [_autoCorrectController selectedObjects];
    if ([selected count] == 1) {
      AutoCorrectItem *item = [selected objectAtIndex:0];
      [_replaceField setStringValue:item.replace];
      [_withField setStringValue:item.with];
    }
    [self updateAutoCorrectEditor];
  }
}

- (void)controlTextDidChange:(NSNotification *)notification {
  [self updateAutoCorrectEditor];
}

- (NSString *)editorCorrection {
  return [[AutoCorrect sharedInstance] correctionForValue:[self trimmed:_withField]
                                                     term:[self trimmed:_replaceField]];
}

- (NSString *)trimmed:(NSTextField *)field {
  return [[field stringValue]
      stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
}

- (void)updateAutoCorrectEditor {
  BOOL complete = [[self trimmed:_replaceField] length] > 0 &&
                  [[self trimmed:_withField] length] > 0;
  [_addButton setEnabled:complete];
  [_deleteButton setEnabled:[[_autoCorrectController selectedObjects] count] > 0];
  [_previewLabel setStringValue:complete
                     ? [NSString stringWithFormat:@"Preview: %@", [self editorCorrection]]
                     : @""];
}

- (AutoCorrectItem *)itemForKey:(NSString *)key {
  for (AutoCorrectItem *item in _autoCorrectItemsArray) {
    if ([item.replace isEqualToString:key]) {
      return item;
    }
  }
  return nil;
}

// Shows `correction` for `key` in the list, adding a row if needed.
- (AutoCorrectItem *)showEntry:(NSString *)key correction:(NSString *)correction {
  AutoCorrectItem *item = [self itemForKey:key];
  if (item) {
    item.with = correction;
  } else {
    item = [[[AutoCorrectItem alloc] init] autorelease];
    item.replace = key;
    item.with = correction;
    [_autoCorrectController addObject:item];
  }
  return item;
}

- (IBAction)addOrUpdateAutoCorrect:(id)sender {
  NSString *term = [self trimmed:_replaceField];
  NSString *correction = [self editorCorrection];
  if ([term length] == 0 || [correction length] == 0) {
    return;
  }
  [[AutoCorrect sharedInstance] setUserAutoCorrect:correction forTerm:term];
  NSString *key = [[AvroParser sharedInstance] fix:term];
  AutoCorrectItem *item = [self showEntry:key correction:correction];
  [_autoCorrectController setSelectedObjects:[NSArray arrayWithObject:item]];
  [_replaceField setStringValue:@""];
  [_withField setStringValue:@""];
  [self updateAutoCorrectEditor];
  [[self window] makeFirstResponder:_replaceField];
}

- (IBAction)deleteAutoCorrect:(id)sender {
  NSArray *selected = [[[_autoCorrectController selectedObjects] copy] autorelease];
  for (AutoCorrectItem *item in selected) {
    [[AutoCorrect sharedInstance] deleteAutoCorrectForTerm:item.replace];
  }
  [_autoCorrectController removeObjects:selected];
  [_replaceField setStringValue:@""];
  [_withField setStringValue:@""];
  [self updateAutoCorrectEditor];
}

- (IBAction)importAutoCorrect:(id)sender {
  NSOpenPanel *panel = [NSOpenPanel openPanel];
  [panel setMessage:@"Choose an Avro AutoCorrect dictionary (.dct): one \"term value\" pair per line."];
  if ([panel runModal] != NSModalResponseOK) {
    return;
  }
  NSError *error = nil;
  NSDictionary *raw = [AutoCorrect entriesFromDictionaryFile:[[panel URL] path] error:&error];
  if (!raw) {
    NSAlert *alert = [[[NSAlert alloc] init] autorelease];
    [alert setMessageText:@"Cannot import the AutoCorrect dictionary"];
    [alert setInformativeText:@"The file must be UTF-8 text with one \"term value\" pair per line."];
    [alert runModal];
    return;
  }

  AutoCorrect *autoCorrect = [AutoCorrect sharedInstance];
  NSMutableDictionary *added = [NSMutableDictionary dictionary];
  NSMutableDictionary *conflicts = [NSMutableDictionary dictionary];
  for (NSString *term in raw) {
    NSString *key = [[AvroParser sharedInstance] fix:term];
    NSString *correction = [autoCorrect correctionForValue:[raw objectForKey:term] term:term];
    NSString *current = [[autoCorrect autoCorrectEntries] objectForKey:key];
    if (!current) {
      [added setObject:correction forKey:key];
    } else if (![current isEqualToString:correction]) {
      [conflicts setObject:correction forKey:key];
    }
  }

  // Windows asks per entry; one question for all conflicts is enough here.
  if ([conflicts count] > 0) {
    NSAlert *alert = [[[NSAlert alloc] init] autorelease];
    [alert setMessageText:[NSString stringWithFormat:
        @"%lu imported entries differ from existing ones",
        (unsigned long)[conflicts count]]];
    [alert setInformativeText:@"Replace the existing entries with the imported ones?"];
    [alert addButtonWithTitle:@"Keep Existing"];
    [alert addButtonWithTitle:@"Replace"];
    if ([alert runModal] == NSAlertSecondButtonReturn) {
      [added addEntriesFromDictionary:conflicts];
    }
  }

  [autoCorrect setUserAutoCorrectEntries:added];
  for (NSString *key in added) {
    [self showEntry:key correction:[added objectForKey:key]];
  }
}

@end
