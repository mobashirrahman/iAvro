//
//  AvroKeyboard
//
//  Created by Rifat Nabi on 6/24/12.
//  Copyright (c) 2012 OmicronLab. All rights reserved.
//

#import "MainMenuAppDelegate.h"
#import <Sparkle/Sparkle.h>

#import "AutoCorrect.h"
#import "AvroParser.h"
#import "CacheManager.h"
#import "Database.h"
#import "RegexParser.h"
#import "UserDictionary.h"
#import "VersionInfo.h"

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

    [self addDictionaryMenuItems];

    [self addAboutMenuItem];

    [self startUpdater];

    if ([[NSUserDefaults standardUserDefaults] boolForKey:@"IncludeDictionary"]) {
        NSLog(@"Loading Dictionary...");
        [Database sharedInstance];
        [RegexParser sharedInstance];
        [CacheManager sharedInstance];
    }
    [AutoCorrect sharedInstance];
}

// Import/Export live in the input menu rather than the AutoCorrect pane: the
// pane's button row has no free space, and these act on the whole dictionary
// rather than one entry.
- (void)addDictionaryMenuItems {
    NSMenuItem *exportItem = [_menu itemWithTag:3];
    if (exportItem == nil) {
        exportItem = [[[NSMenuItem alloc] initWithTitle:@"Export User Dictionary…"
                                                 action:@selector(exportUserDictionary:)
                                          keyEquivalent:@""] autorelease];
        [exportItem setTag:3];
        [_menu addItem:exportItem];
    }
    [exportItem setAction:@selector(exportUserDictionary:)];
    [exportItem setTarget:self];

    NSMenuItem *importItem = [_menu itemWithTag:4];
    if (importItem == nil) {
        importItem = [[[NSMenuItem alloc] initWithTitle:@"Import User Dictionary…"
                                                 action:@selector(importUserDictionary:)
                                          keyEquivalent:@""] autorelease];
        [importItem setTag:4];
        [_menu addItem:importItem];
    }
    [importItem setAction:@selector(importUserDictionary:)];
    [importItem setTarget:self];
}

- (IBAction)exportUserDictionary:(id)sender {
    NSSavePanel *panel = [NSSavePanel savePanel];
    [panel setNameFieldStringValue:@"AvroKeyboard-user-dictionary.txt"];
    [panel setMessage:@"Export your AutoCorrect entries and learned words."];
    if ([panel runModal] != NSModalResponseOK) {
        return;
    }
    NSString *version = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"];
    NSString *text = [UserDictionary
        textForAutoCorrectEntries:[[AutoCorrect sharedInstance] userAutoCorrectEntries]
                     learnedCounts:[[CacheManager sharedInstance] countSnapshot]
                        appVersion:version];
    NSError *error = nil;
    if (![UserDictionary writeText:text toPath:[[panel URL] path] error:&error]) {
        [self alertWithMessage:@"Cannot export the user dictionary"
                  informative:error ? [error localizedDescription]
                                    : @"The file could not be written."];
    }
}

- (IBAction)importUserDictionary:(id)sender {
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    [panel setMessage:@"Import AutoCorrect entries and learned words."];
    if ([panel runModal] != NSModalResponseOK) {
        return;
    }
    NSError *error = nil;
    NSString *text = [NSString stringWithContentsOfFile:[[panel URL] path]
                                                encoding:NSUTF8StringEncoding
                                                   error:&error];
    NSDictionary *parsed = text ? [UserDictionary parseText:text] : nil;
    if (!parsed) {
        [self alertWithMessage:@"Cannot import the user dictionary"
                  informative:error ? [error localizedDescription]
                                    : @"The file must be UTF-8 text, either the format this app exports "
                                      @"or one \"term value\" pair per line."];
        return;
    }

    NSDictionary *entries = [parsed objectForKey:@"autocorrect"];
    NSDictionary *counts = [parsed objectForKey:@"learned"];
    // Terms are normalised the same way the editor does, so an entry typed in
    // any case still matches what the parser produces.
    NSMutableDictionary *normalized = [NSMutableDictionary dictionaryWithCapacity:[entries count]];
    for (NSString *term in entries) {
        NSString *key = [[AvroParser sharedInstance] fix:term];
        if ([key length]) {
            [normalized setObject:[entries objectForKey:term] forKey:key];
        }
    }
    if ([normalized count] > 0) {
        [[AutoCorrect sharedInstance] setUserAutoCorrectEntries:normalized];
    }
    [[CacheManager sharedInstance] addCounts:counts];

    [self alertWithMessage:@"User dictionary imported"
              informative:[NSString stringWithFormat:
                              @"%lu AutoCorrect entries and %lu learned words were added.",
                              (unsigned long)[normalized count],
                              (unsigned long)[counts count]]];
}

- (void)alertWithMessage:(NSString *)message informative:(NSString *)informative {
    NSAlert *alert = [[[NSAlert alloc] init] autorelease];
    [alert setMessageText:message];
    [alert setInformativeText:informative];
    [alert addButtonWithTitle:@"OK"];
    [alert runModal];
}

- (void)addAboutMenuItem {
    // The standard panel reads CFBundleName, the version and the bundled
    // Credits.rtfd, so the version can never drift from the bundle.
    NSMenuItem *about = [_menu itemWithTag:5];
    if (about == nil) {
        about = [[[NSMenuItem alloc] initWithTitle:@"About Avro Keyboard"
                                            action:@selector(showAbout:)
                                     keyEquivalent:@""] autorelease];
        [about setTag:5];
        [_menu addItem:about];
    }
    [about setAction:@selector(showAbout:)];
    [about setTarget:self];
}

- (IBAction)showAbout:(id)sender {
    [NSApp activateIgnoringOtherApps:YES];
    [NSApp orderFrontStandardAboutPanel:sender];
}

- (void)startUpdater {    if (sUpdaterController != nil) {
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
