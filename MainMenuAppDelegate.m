//
//  AvroKeyboard
//
//  Created by Rifat Nabi on 6/24/12.
//  Copyright (c) 2012 OmicronLab. All rights reserved.
//

#import "MainMenuAppDelegate.h"
#import <Sparkle/Sparkle.h>

#import "AutoCorrect.h"
#import "CacheManager.h"
#import "Database.h"
#import "RegexParser.h"

// Sparkle owns the update feed and the user-initiated update check. Keeping a
// strong reference is required: SPUStandardUpdaterController does not retain
// itself, and it is released on dealloc.
static SPUStandardUpdaterController *sUpdaterController = nil;

@implementation MainMenuAppDelegate

@synthesize imPref;

//this method is added so that our controllers can access the shared NSMenu.
-(NSMenu*)menu {
	return _menu;
}

//add an awakeFromNib item so that we can set the action method.  Note that any menuItems without an action will be disabled when
//displayed in the Text Input Menu.
-(void)awakeFromNib {
	NSMenuItem* preferences = [_menu itemWithTag:1];
	
	if (preferences) {
		[preferences setAction:@selector(showPreferences:)];
	}

    NSMenuItem* checkForUpdates = [_menu itemWithTag:2];
    if (checkForUpdates == nil) {
        // The nib has no item with this tag, so build one. Menu items without
        // an action are disabled when shown in the Text Input menu, so the
        // action and target are set before it is added.
        checkForUpdates = [[[NSMenuItem alloc] initWithTitle:@"Check for Updates…"
                                                      action:@selector(checkForUpdates:)
                                               keyEquivalent:@""] autorelease];
        [checkForUpdates setTag:2];
        [_menu addItem:checkForUpdates];
    }
    [checkForUpdates setAction:@selector(checkForUpdates:)];
    [checkForUpdates setTarget:self];

    [self startUpdater];

    if ([[NSUserDefaults standardUserDefaults] boolForKey:@"IncludeDictionary"]) {
        NSLog(@"Loading Dictionary...");
        [Database sharedInstance];
        [RegexParser sharedInstance];
        [CacheManager sharedInstance];
    }
    [AutoCorrect sharedInstance];
}

- (void)startUpdater {
    if (sUpdaterController != nil) {
        return;
    }
    // Updates are signed with Sparkle's EdDSA key (see SUPublicEDKey in
    // Info.plist), so no Apple Developer Program membership is required. If
    // the feed or key is missing, stay quiet rather than popping errors.
    NSString *feedURL = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"SUFeedURL"];
    NSString *publicKey = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"SUPublicEDKey"];
    if ([feedURL length] == 0 || [publicKey length] == 0) {
        NSLog(@"Auto-updates not configured (SUFeedURL/SUPublicEDKey missing).");
        return;
    }

    sUpdaterController = [[SPUStandardUpdaterController alloc] initWithStartingUpdater:YES
                                                                        updaterDelegate:nil
                                                                     userDriverDelegate:nil];
}

- (IBAction)checkForUpdates:(id)sender {
    if (sUpdaterController == nil) {
        NSBeep();
        return;
    }
    [sUpdaterController checkForUpdates:sender];
}

// Currently doesn't work
- (void)applicationWillTerminate:(NSNotification *)notification {
    if ([[NSUserDefaults standardUserDefaults] boolForKey:@"IncludeDictionary"]) {
        [[CacheManager sharedInstance] persist];
    }
}

@end
