//
//  AvroKeyboard
//
//  Created by Rifat Nabi on 6/25/12.
//  Copyright (c) 2012 OmicronLab. All rights reserved.
//

#import "PreferencesController.h"
#import "AutoCorrect.h"
#import "AutoCorrectItem.h"

static NSString * const kShowInlineBanglaDefaultsKey = @"ShowInlineBangla";

@implementation PreferencesController

@synthesize autoCorrectItemsArray = _autoCorrectItemsArray;

- (id)init
{
    self = [super init];
    if (self) {
        NSMutableDictionary *autoCorrectEntries = [[AutoCorrect sharedInstance] autoCorrectEntries];
        _autoCorrectItemsArray = [[NSMutableArray alloc] init];
        for (id key in autoCorrectEntries) {
            AutoCorrectItem* item = [[AutoCorrectItem alloc] init];
            item.replace = key;
            item.with = [autoCorrectEntries objectForKey:key];
            [_autoCorrectItemsArray addObject:item];
            [item release];
        }
    }
    return self;
}

- (void)dealloc
{
    [_autoCorrectItemsArray release];
    [super dealloc];
}

- (void)awakeFromNib {
	[[self window] setContentSize:[_generalView frame].size];
    [[[self window] contentView] addSubview:_generalView];
    [[[self window] contentView] setWantsLayer:YES];

    [self addInlineBanglaPreferenceToggle];
    
    // Load Credits
    [_aboutContent readRTFDFromFile:[[NSBundle mainBundle] pathForResource:@"Credits" ofType:@"rtfd"]];
    [_aboutContent scrollToBeginningOfDocument:_aboutContent];
}

- (NSRect)newFrameForNewContentView:(NSView*)view {
    NSWindow* window = [self window];
    NSRect newFrameRect = [window frameRectForContentRect:[view frame]];
    NSRect oldFrameRect = [window frame];
    NSSize newSize = newFrameRect.size;
    NSSize oldSize = oldFrameRect.size;
    
    NSRect frame = [window frame];
    frame.size = newSize;
    frame.origin.y -= (newSize.height - oldSize.height);
    
    return frame;
}

- (NSView*)viewForTag:(NSInteger)tag {
    NSView* view = nil;
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
    NSView* view = [self viewForTag:tag];
    NSView* previousView = [self viewForTag:_currentViewTag];
    _currentViewTag = tag;
    NSRect newFrame = [self newFrameForNewContentView:view];
    
    [NSAnimationContext beginGrouping];
    
    if ([[NSApp currentEvent] modifierFlags] & NSEventModifierFlagShift) {
        [[NSAnimationContext currentContext] setDuration:1.0];
    }
    
    [[[[self window] contentView] animator] replaceSubview:previousView with:view];
    [[[self window] animator] setFrame:newFrame display:YES];
    
    [NSAnimationContext endGrouping];
}

- (IBAction)changePredicate:(id)sender {
    NSString *searchTerm = [[sender stringValue] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSPredicate *predicate = nil;
    if ([searchTerm length]) {
        predicate = [NSPredicate predicateWithFormat:@"(replace CONTAINS[c] %@) OR (with CONTAINS %@)", searchTerm, searchTerm];
    }
    [_autoCorrectController setFilterPredicate:predicate];
}

- (void)addInlineBanglaPreferenceToggle {
    if (!_generalView) {
        return;
    }

    NSRect frame = NSMakeRect(198.0, 0.0, 250.0, 18.0);
    NSButton *inlineToggle = [[NSButton alloc] initWithFrame:frame];
    [inlineToggle setButtonType:NSSwitchButton];
    [inlineToggle setTitle:@"Show Bengali inline while typing"];
    [inlineToggle setBezelStyle:NSBezelStyleRegularSquare];
    [inlineToggle setAutoresizingMask:(NSViewMaxXMargin | NSViewMinYMargin)];
    [inlineToggle bind:@"value"
              toObject:[NSUserDefaultsController sharedUserDefaultsController]
           withKeyPath:[NSString stringWithFormat:@"values.%@", kShowInlineBanglaDefaultsKey]
               options:nil];

    [_generalView addSubview:inlineToggle];
    [inlineToggle release];
}

@end
