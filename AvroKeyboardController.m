//
//  AvroKeyboard
//
//  Created by Rifat Nabi on 6/21/12.
//  Copyright (c) 2012 OmicronLab. All rights reserved.
//

#import "AvroKeyboardController.h"
#import <AppKit/AppKit.h>
#import "MainMenuAppDelegate.h"
#import "Suggestion.h"
#import "Candidates.h"
#import "CacheManager.h"
#import "RegexKitLite.h"
#import "AvroParser.h"
#import "AutoCorrect.h"
#import "LanguageMode.h"
#import "SettingsKeys.h"

// Input-menu item that toggles English pass-through for the current
// application. The tag is well clear of the 1-4 used by the shared menu.
static const NSInteger kEnglishModeMenuItemTag = 100;

@interface AvroKeyboardController ()
- (NSString *)compositionDisplayString;
- (NSString *)stringFromCandidate:(id)candidate;
- (void)recordCommitOfCandidate:(NSString *)candidateText;
- (void)addEnglishCandidateRemembering:(NSString *)prevString;
- (NSInteger)preferredTransliterationIndex;
- (BOOL)isClassicMode;
- (NSString *)classicOutput;
- (BOOL)browseCandidatesBy:(NSInteger)step;
- (NSString *)englishCandidate;
- (BOOL)isEnglishModeActive;
- (NSString *)currentBundleIdentifier;
- (void)removeEnglishModeMenuItemFromMenu:(NSMenu *)menu;
- (BOOL)shouldSelectCandidateWithDigit;
@end
@implementation AvroKeyboardController

@synthesize prefix = _prefix, term = _term, suffix = _suffix;

- (id)initWithServer:(IMKServer*)server delegate:(id)delegate client:(id)inputClient {
    
    self = [super initWithServer:server delegate:delegate client:inputClient];
    
	if (self) {
        _currentClient = [inputClient retain];
        _composedBuffer = [[NSMutableString alloc] initWithString:@""];
        _currentCandidates = [[NSMutableArray alloc] initWithCapacity:0];
        _prevSelected = -1;
        _selectedCandidateIndex = 0;
        _usedArrowKeys = false;
    }

	return self;
}

- (void)dealloc {
    [_prefix release];
    [_term release];
    [_suffix release];
    [_currentCandidates release];
    [_composedBuffer release];
    [_currentClient release];
	[super dealloc];
}

- (void)findCurrentCandidates {
    [_currentCandidates release];
    _currentCandidates = [[NSMutableArray alloc] initWithCapacity:0];
    _prevSelected = -1;
    _selectedCandidateIndex = 0;
    if (_composedBuffer && [_composedBuffer length] > 0) {
        NSString* regex = @"(^(?::`|\\.`|[-\\]\\\\~!@#&*()_=+\\[{}'\";<>/?|.,])*?(?=(?:,{2,}))|^(?::`|\\.`|[-\\]\\\\~!@#&*()_=+\\[{}'\";<>/?|.,])*)(.*?(?:,,)*)((?::`|\\.`|[-\\]\\\\~!@#&*()_=+\\[{}'\";<>/?|.,])*$)";
        NSArray* items = [_composedBuffer captureComponentsMatchedByRegex:regex];
        if (items && [items count] > 0) {
            // Split Prefix, Term & Suffix
            [self setPrefix:[[AvroParser sharedInstance] parse:[items objectAtIndex:1]]];
            [self setTerm:[items objectAtIndex:2]];
            [self setSuffix:[[AvroParser sharedInstance] parse:[items objectAtIndex:3]]];

            if ([self isClassicMode]) {
                [_currentCandidates addObject:[self classicOutput]];
                return;
            }

            NSArray *freshList = [[Suggestion sharedInstance] getList:[self term]];
            [_currentCandidates release];
            _currentCandidates = [freshList mutableCopy];
            if (_currentCandidates && [_currentCandidates count] > 0) {
                NSString* prevString = nil;
                if ([[NSUserDefaults standardUserDefaults] boolForKey:@"IncludeDictionary"]) {
                    _prevSelected = -1;
                    prevString = [[CacheManager sharedInstance] stringForKey:[self term]];
                }
                int i;
                for (i = 0; i < [_currentCandidates count]; ++i) {
                    NSString* item = [_currentCandidates objectAtIndex:i];
                    if ([[NSUserDefaults standardUserDefaults] boolForKey:@"IncludeDictionary"] &&
                        _prevSelected == -1 && prevString && [item isEqualToString:prevString] ) {
                        _prevSelected = i;
                    }
                    [_currentCandidates replaceObjectAtIndex:i withObject:
                     [NSString stringWithFormat:@"%@%@%@", [self prefix], item, [self suffix]]];
                }
                // Emoticons
                if ([_composedBuffer isEqualToString:[self term]] == NO &&
                    [[NSUserDefaults standardUserDefaults] boolForKey:@"IncludeDictionary"]) {
                    NSString* smily = [[AutoCorrect sharedInstance] find:_composedBuffer];
                    if (smily) {
                        // The term's own AutoCorrect entry can already yield it
                        // (":" + ")"), so move it to the front instead of adding twice.
                        NSUInteger existing = [_currentCandidates indexOfObject:smily];
                        BOOL wasSelected = (existing != NSNotFound && _prevSelected == (int)existing);
                        if (existing != NSNotFound) {
                            [_currentCandidates removeObjectAtIndex:existing];
                            if (_prevSelected > (int)existing) {
                                _prevSelected -= 1;
                            }
                        }
                        [_currentCandidates insertObject:smily atIndex:0];
                        if (wasSelected) {
                            _prevSelected = 0;
                        } else if (_prevSelected >= 0) {
                            _prevSelected += 1;
                        }
                    }
                }
                [self addEnglishCandidateRemembering:prevString];
                if (_prevSelected == -1) {
                    _prevSelected = (int)[self preferredTransliterationIndex];
                }
                if (_prevSelected >= 0 && _prevSelected < [_currentCandidates count]) {
                    _selectedCandidateIndex = _prevSelected;
                } else {
                    _selectedCandidateIndex = 0;
                }
            }
            else {
                [_currentCandidates addObject:[self prefix]];
                [self addEnglishCandidateRemembering:nil];
            }
        }
    }
}

// The buffer as English text: Avro's literal-dot syntax (".`", also what
// Shift-\\ types) reads as a plain dot.
- (NSString *)englishCandidate {
    // Copy: with nothing to replace this can return the mutable buffer itself
    return [[[_composedBuffer stringByReplacingOccurrencesOfString:@".`" withString:@"."] copy] autorelease];
}

// Windows Avro offers the typed Roman text as the last choice, so English
// words can be typed without switching input sources. Choosing it is
// remembered like any other candidate: the weight cache stores the raw term.
- (void)addEnglishCandidateRemembering:(NSString *)prevString {
    if (![[NSUserDefaults standardUserDefaults] boolForKey:kOfferEnglishDefaultsKey]) {
        return;
    }
    NSString *english = [self englishCandidate];
    if ([_currentCandidates containsObject:english]) {
        return;
    }
    [_currentCandidates addObject:english];
    if (_prevSelected == -1 && prevString && [prevString isEqualToString:[self term]]) {
        _prevSelected = (int)[_currentCandidates count] - 1;
    }
}

// Windows Avro's "character mode": with no remembered choice and no
// AutoCorrect hit, preselect the exact transliteration instead of the
// top dictionary word. Returns -1 to keep the default (first) candidate.
- (NSInteger)preferredTransliterationIndex {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    if (![defaults boolForKey:kPreferTransliterationDefaultsKey] ||
        ![defaults boolForKey:@"IncludeDictionary"] || [[self term] length] < 2) {
        return -1;
    }
    if ([defaults boolForKey:kEnableAutoCorrectDefaultsKey] &&
        [[AutoCorrect sharedInstance] find:[self term]]) {
        return -1;
    }
    NSString *exact = [NSString stringWithFormat:@"%@%@%@", [self prefix],
                       [[AvroParser sharedInstance] parse:[self term]], [self suffix]];
    NSUInteger index = [_currentCandidates indexOfObject:exact];
    return index == NSNotFound ? -1 : (NSInteger)index;
}

- (BOOL)isClassicMode {
    return [[NSUserDefaults standardUserDefaults] boolForKey:kClassicPhoneticDefaultsKey];
}

// Windows Avro's classic phonetic: no window, no dictionary. The output is
// the AutoCorrect entry when there is one, else the plain transliteration.
- (NSString *)classicOutput {
    if ([[NSUserDefaults standardUserDefaults] boolForKey:kEnableAutoCorrectDefaultsKey]) {
        // Whole-buffer entries first, like the emoticon lookup (":-)")
        if (![_composedBuffer isEqualToString:[self term]]) {
            NSString *whole = [[AutoCorrect sharedInstance] find:_composedBuffer];
            if (whole) {
                return whole;
            }
        }
        NSString *corrected = [[AutoCorrect sharedInstance] find:[self term]];
        if (corrected) {
            return [NSString stringWithFormat:@"%@%@%@", [self prefix], corrected, [self suffix]];
        }
    }
    return [NSString stringWithFormat:@"%@%@%@", [self prefix],
            [[AvroParser sharedInstance] parse:[self term]], [self suffix]];
}

- (void)updateCandidatesPanel {
    if ([self isClassicMode]) {
        [[Candidates sharedInstance] hide];
        return;
    }
    if (_currentCandidates && [_currentCandidates count] > 0) {
        NSUserDefaults *defaultsDictionary = [NSUserDefaults standardUserDefaults];
        
        // delete and init IMKCandidates instance because setPanelType doesn't work. panelType during init is permament in macos mojave.
        if ([[Candidates sharedInstance] panelType] != [defaultsDictionary integerForKey:@"CandidatePanelType"]) {
            [Candidates reallocate];
        }
        [[Candidates sharedInstance] updateCandidates];
        [[Candidates sharedInstance] show:kIMKLocateCandidatesBelowHint];
        if (_prevSelected > -1) {
            // IMKCandidates:selectCandidate not working here in sierra
            // Temporary workaounrd
            for (int i = 0 ; i < _prevSelected; ++i) {
                if ([[Candidates sharedInstance] panelType] == kIMKSingleColumnScrollingCandidatePanel) {
                    [[Candidates sharedInstance] moveDown:self];
                } else if ([[Candidates sharedInstance] panelType] == kIMKSingleRowSteppingCandidatePanel) {
                    [[Candidates sharedInstance] moveRight:self];
                }
            }
            // [[Candidates sharedInstance] selectCandidate:_prevSelected];
        }
    }
    else {
        [[Candidates sharedInstance] hide];
    }
}

- (NSString *)stringFromCandidate:(id)candidate {
    if (!candidate) {
        return nil;
    }
    if ([candidate isKindOfClass:[NSAttributedString class]]) {
        return [(NSAttributedString *)candidate string];
    }
    if ([candidate isKindOfClass:[NSString class]]) {
        return (NSString *)candidate;
    }
    return nil;
}

- (NSArray*)candidates:(id)sender {
	return [[_currentCandidates copy] autorelease];
}

- (void)candidateSelectionChanged:(id)candidate {
    NSString *candidateText = [self stringFromCandidate:candidate];
    if (!candidateText) {
        return;
    }
    if ([[NSUserDefaults standardUserDefaults] boolForKey:@"IncludeDictionary"]) {
        if ([self term] && [[self term] length] > 0 && [_currentCandidates count] > 0) {
            NSString *firstCandidate = [_currentCandidates objectAtIndex:0];
            if (![firstCandidate isKindOfClass:[NSString class]]) {
                firstCandidate = [self stringFromCandidate:firstCandidate];
            }
            BOOL comp = [candidateText isEqualToString:firstCandidate];
            if ((comp && _prevSelected == -1) == NO) {
                NSUInteger prefixLen = [[self prefix] length];
                NSUInteger suffixLen = [[self suffix] length];
                if ([candidateText isEqualToString:[self englishCandidate]]) {
                    // English candidate: its prefix/suffix are Roman, not the
                    // parsed lengths above, so remember the raw term itself.
                    [[CacheManager sharedInstance] setString:[self term] forKey:[self term]];
                }
                else if (prefixLen + suffixLen <= [candidateText length]) {
                    NSRange range = NSMakeRange(prefixLen,
                                                [candidateText length] - (prefixLen + suffixLen));
                    [[CacheManager sharedInstance] setString:[candidateText substringWithRange:range] forKey:[self term]];
                }

                // Reverse Suffix Caching
                NSArray* tmpArray = [[CacheManager sharedInstance] baseForKey:candidateText];
                if (tmpArray && [tmpArray count] > 0) {
                    [[CacheManager sharedInstance] setString:[tmpArray objectAtIndex:1] forKey:[tmpArray objectAtIndex:0]];
                }
            }
        }
    }
    NSUInteger found = [_currentCandidates indexOfObject:candidateText];
    if (found != NSNotFound) {
        _selectedCandidateIndex = found;
    }
}

- (void)candidateSelected:(id)candidate {
    NSString *candidateText = [self stringFromCandidate:candidate];
    if (!candidateText) {
        return;
    }
    [_currentClient insertText:candidateText replacementRange:NSMakeRange(NSNotFound, 0)];

	[self clearCompositionBuffer];
	[_currentCandidates removeAllObjects];
    [self updateCandidatesPanel];

    _usedArrowKeys = false;
    if ([[NSUserDefaults standardUserDefaults] boolForKey:@"IncludeDictionary"]) {
        [self recordCommitOfCandidate:candidateText];
        [[CacheManager sharedInstance] schedulePersist];
    }
}

// Counts a word only once it has actually been committed. Doing this in
// candidateSelectionChanged: instead would count every candidate the user
// merely arrowed past, which would flood the personal frequency with words
// they never chose.
- (void)recordCommitOfCandidate:(NSString *)candidateText {
    if (![candidateText isEqualToString:[self englishCandidate]]) {
        NSUInteger prefixLen = [[self prefix] length];
        NSUInteger suffixLen = [[self suffix] length];
        if (prefixLen + suffixLen > [candidateText length]) {
            return;
        }
        NSRange range = NSMakeRange(prefixLen,
                                    [candidateText length] - (prefixLen + suffixLen));
        [[CacheManager sharedInstance] incrementCountForKey:
            [candidateText substringWithRange:range]];
    }
}

- (void)activateServer:(id)sender {
    [super activateServer:sender];
    // Nothing can legitimately be in flight for a client that is only now
    // becoming active: a previous session may have been interrupted without a
    // matching deactivate (client crash, force-quit, fast app switch). Without
    // this, the next keystroke appends to a stale composition.
    [self clearCompositionBuffer];
    [_currentCandidates removeAllObjects];
    [self setPrefix:nil];
    [self setTerm:nil];
    [self setSuffix:nil];
    _prevSelected = -1;
    _selectedCandidateIndex = 0;
    [self updateCandidatesPanel];
}

- (void)deactivateServer:(id)sender {
    // Flush any pending debounced save when the user switches away
    if ([[NSUserDefaults standardUserDefaults] boolForKey:@"IncludeDictionary"]) {
        [[CacheManager sharedInstance] persist];
    }
    [super deactivateServer:sender];
}

- (void)commitComposition:(id)sender {
	NSString *commitString = [self compositionDisplayString];
	[sender insertText:commitString replacementRange:NSMakeRange(NSNotFound, 0)];
	
	[self clearCompositionBuffer];
	[_currentCandidates removeAllObjects];
    [self updateCandidatesPanel];
}

- (id)composedString:(id)sender {
	NSString *displayString = [self compositionDisplayString];
	return [[[NSAttributedString alloc] initWithString:displayString] autorelease];
}

- (void)clearCompositionBuffer {
	[_composedBuffer deleteCharactersInRange:NSMakeRange(0, [_composedBuffer length])];	
}

- (NSString *)compositionDisplayString {
    // Classic mode has no window, so the Bangla must show inline
    if ([self isClassicMode] && [_currentCandidates count] > 0) {
        return [_currentCandidates objectAtIndex:0];
    }
    if (![[NSUserDefaults standardUserDefaults] boolForKey:kShowInlineBanglaDefaultsKey]) {
        return _composedBuffer ? _composedBuffer : @"";
    }

    if (!_composedBuffer || [_composedBuffer length] == 0) {
        return @"";
    }

    if (![self term]) {
        return [[AvroParser sharedInstance] parse:_composedBuffer];
    }

    NSString *prefix = [self prefix] ? [self prefix] : @"";
    NSString *suffix = [self suffix] ? [self suffix] : @"";
    NSString *parsedTerm = [[AvroParser sharedInstance] parse:[self term]];
    return [NSString stringWithFormat:@"%@%@%@", prefix, parsedTerm, suffix];
}

/*
 Implement one of the three ways to receive input from the client. 
 Here are the three approaches:
 
 1.  Support keybinding.  
 In this approach the system takes each keydown and trys to map the keydown to an action method that the input method has implemented.  If an action is found the system calls didCommandBySelector:client:.  If no action method is found inputText:client: is called.  An input method choosing this approach should implement
 -(BOOL)inputText:(NSString*)string client:(id)sender;
 -(BOOL)didCommandBySelector:(SEL)aSelector client:(id)sender;
 
 2. Receive all key events without the keybinding, but do "unpack" the relevant text data.
 Key events are broken down into the Unicodes, the key code that generated them, and modifier flags.  This data is then sent to the input method's inputText:key:modifiers:client: method.  For this approach implement:
 -(BOOL)inputText:(NSString*)string key:(NSInteger)keyCode modifiers:(NSUInteger)flags client:(id)sender;
 
 3. Receive events directly from the Text Services Manager as NSEvent objects.  For this approach implement:
 -(BOOL)handleEvent:(NSEvent*)event client:(id)sender;
 */

/*!
 @method     
 @abstract   Receive incoming text.
 @discussion This method receives key board input from the client application.  The method receives the key input as an NSString. The string will have been created from the keydown event by the InputMethodKit.
 */
- (BOOL)inputText:(NSString*)string client:(id)sender {
    // Return YES to indicate the the key input was received and dealt with.  Key processing will not continue in that case.  In
    // other words the system will not deliver a key down event to the application.
    // Returning NO means the original key down will be passed on to the client.
    if ([self isEnglishModeActive]) {
        // Terminals and editors get the literal keystrokes. If a composition
        // was already in progress when the mode was switched, commit it rather
        // than discarding what the user typed.
        if (_composedBuffer && [_composedBuffer length] > 0) {
            [self commitComposition:sender];
        }
        return NO;
    }
    if ([string isEqualToString:@" "]) {
        if (_currentCandidates && [_currentCandidates count] > 0) {
            // IMKCandidates:selectedCandidateString returns null for some reason, so null is commited when user presses enter.
            // Temporary fix for macOS sierra, use our own _selectedCandidateIndex instead.
            // TODO: Figure out why IMKCandidates:selectedCandidateString isn't working.
            NSUInteger safeIndex = _selectedCandidateIndex;
            if (safeIndex >= [_currentCandidates count]) {
                safeIndex = 0;
            }
            [self candidateSelected:[_currentCandidates objectAtIndex:safeIndex]];
        }
        return NO;
    }
    if ([string length] == 1) {
        unichar ch = [string characterAtIndex:0];
        if (ch >= '1' && ch <= '9' && [self shouldSelectCandidateWithDigit]) {
            NSUInteger idx = (NSUInteger)(ch - '1');
            if (idx < [_currentCandidates count]) {
                [self candidateSelected:[_currentCandidates objectAtIndex:idx]];
            } else {
                NSBeep();
            }
            return YES;
        }
        // Anything else falls through to normal input below.
    }
    {
        if ([string isEqualToString:@"|"] &&
            [[NSUserDefaults standardUserDefaults] boolForKey:kPipeToDotDefaultsKey]) {
            // Windows Avro option: Avro's literal-dot syntax, since "." alone is দাঁড়ি
            string = @".`";
        }
        [_composedBuffer appendString:string];
        [self findCurrentCandidates];
        [self updateComposition];
        [self updateCandidatesPanel];
        return YES;
    }
}

- (void)deleteBackward:(id)sender {
    // We're called only when [compositionBuffer length] > 0, but guard anyway
    if (!_composedBuffer || [_composedBuffer length] == 0) {
        return;
    }
    [_composedBuffer deleteCharactersInRange:NSMakeRange([_composedBuffer length] - 1, 1)];
    [self findCurrentCandidates];
    [self updateComposition];
    [self updateCandidatesPanel];
}

- (void)insertTab:(id)sender {
    if (![self browseCandidatesBy:1]) {
        [self commitText:@"\t"];
    }
}

- (void)insertBacktab:(id)sender {
    [self browseCandidatesBy:-1];
}

// Windows Avro's Tab browsing: step through the candidates instead of
// committing. Returns NO when off or there is nothing to browse.
- (BOOL)browseCandidatesBy:(NSInteger)step {
    if (![[NSUserDefaults standardUserDefaults] boolForKey:kTabBrowsingDefaultsKey] ||
        [_currentCandidates count] < 2) {
        return NO;
    }
    NSInteger target = _selectedCandidateIndex + step;
    if (target < 0 || target >= (NSInteger)[_currentCandidates count]) {
        return YES; // at the end: stay put, like the arrow keys
    }
    BOOL vertical = [[Candidates sharedInstance] panelType] == kIMKSingleColumnScrollingCandidatePanel;
    if (step > 0) {
        vertical ? [[Candidates sharedInstance] moveDown:self] : [[Candidates sharedInstance] moveRight:self];
    } else {
        vertical ? [[Candidates sharedInstance] moveUp:self] : [[Candidates sharedInstance] moveLeft:self];
    }
    // Also record it directly (index + learning) rather than relying only
    // on the panel's callback.
    [self candidateSelectionChanged:[_currentCandidates objectAtIndex:target]];
    return YES;
}

- (void)insertNewline:(id)sender {
    if ([[NSUserDefaults standardUserDefaults] boolForKey:@"CommitNewLineOnEnter"]) {
        [self commitText:@"\n"];
    }
    else {
        [self commitText:@""];
    }
}

- (void)moveUp:(id)sender {
    if ([[Candidates sharedInstance] isVisible]) {
        _usedArrowKeys = true;
        [[Candidates sharedInstance] moveUp:self];
    }
}

- (void)moveDown:(id)sender {
    if ([[Candidates sharedInstance] isVisible]) {
        _usedArrowKeys = true;
        [[Candidates sharedInstance] moveDown:self];
    }
}

- (void)moveLeft:(id)sender {
    if ([[Candidates sharedInstance] isVisible]) {
        _usedArrowKeys = true;
        [[Candidates sharedInstance] moveLeft:self];
    }
}

- (void)moveRight:(id)sender {
    if ([[Candidates sharedInstance] isVisible]) {
        _usedArrowKeys = true;
        [[Candidates sharedInstance] moveRight:self];
    }
}

- (BOOL)didCommandBySelector:(SEL)aSelector client:(id)sender {
    // The NSResponder methods like insertNewline: or deleteBackward: are
    // methods that return void. didCommandBySelector method requires
    // that you return YES if the command is handled and NO if you do not.
    // This is necessary so that unhandled commands can be passed on to the
    // client application. For that reason we need to test in the case where
    // we might not handle the command.

    if (_composedBuffer && [_composedBuffer length] > 0) {
        if ([self respondsToSelector:aSelector] &&
            (aSelector == @selector(insertTab:)
             || (aSelector == @selector(insertBacktab:) &&
                 [[NSUserDefaults standardUserDefaults] boolForKey:kTabBrowsingDefaultsKey])
             || aSelector == @selector(insertNewline:)
             || aSelector == @selector(cancelOperation:)
             || aSelector == @selector(deleteBackward:)
             || aSelector == @selector(moveLeft:)
             || aSelector == @selector(moveRight:)
             || aSelector == @selector(moveUp:)
             || aSelector == @selector(moveDown:))) {
            [self performSelector:aSelector withObject:sender];
            return YES;
        }
        // Anything else (Cmd/Ctrl shortcuts, function keys, noop:) used to
        // pass through with the composition still on screen, orphaning it:
        // the next keystroke would append to text the user thought was gone.
        // Commit what was typed first, then let the key through.
        [self commitComposition:sender];
    }
	return NO;
}

- (void)commitText:(NSString*)string {
    if (_currentCandidates && [_currentCandidates count] > 0) {
        NSUInteger safeIndex = _selectedCandidateIndex;
        if (safeIndex >= [_currentCandidates count]) {
            safeIndex = 0;
        }
        [self candidateSelected:[_currentCandidates objectAtIndex:safeIndex]];
        [_currentClient insertText:string replacementRange:NSMakeRange(NSNotFound, 0)];
    }
    else {
        NSBeep();
    }
}

- (NSMenu*)menu {
    NSMenu *menu = [(MainMenuAppDelegate *)[NSApp delegate] menu];
    NSString *bundleIdentifier = [[self client] bundleIdentifier];
    NSString *name = nil;
    if ([bundleIdentifier length] > 0) {
        NSArray *running = [NSRunningApplication
            runningApplicationsWithBundleIdentifier:bundleIdentifier];
        name = [[running firstObject] localizedName];
    }
    if ([name length] == 0) {
        [self removeEnglishModeMenuItemFromMenu:menu];
        return menu;
    }

    NSMenuItem *item = [menu itemWithTag:kEnglishModeMenuItemTag];
    if (item == nil) {
        item = [[[NSMenuItem alloc]
            initWithTitle:@"" action:@selector(toggleEnglishModeForCurrentApp:)
           keyEquivalent:@""] autorelease];
        [item setTag:kEnglishModeMenuItemTag];
        [item setTarget:self];
        [menu addItem:item];
    }
    [item setTitle:[NSString stringWithFormat:@"Use English in %@", name]];
    [item setState:[self isEnglishModeActive] ? NSControlStateValueOn
                                              : NSControlStateValueOff];
    return menu;
}

- (void)removeEnglishModeMenuItemFromMenu:(NSMenu *)menu {
    NSMenuItem *item = [menu itemWithTag:kEnglishModeMenuItemTag];
    if (item) {
        [menu removeItem:item];
    }
}

// Digits double as candidate shortcuts while a list is showing, the way mature
// IMEs work. The escape hatch: once the composition itself contains a digit
// (ordinals like "11th" start with one), digits go back to being input, because
// there is no way to tell "select #1" from "type the second 1". Zero never
// selects; there is no candidate 0.
- (BOOL)shouldSelectCandidateWithDigit {
    if (!_currentCandidates || [_currentCandidates count] == 0) {
        return NO;
    }
    for (NSUInteger i = 0; i < [_composedBuffer length]; i++) {
        unichar c = [_composedBuffer characterAtIndex:i];
        if (c >= '0' && c <= '9') {
            return NO;
        }
    }
    return YES;
}

// The client tells us which application is hosting this session, so the choice
// is made per application rather than globally.
- (NSString *)currentBundleIdentifier {
    id client = [self client];
    if (![client respondsToSelector:@selector(bundleIdentifier)]) {
        return nil;
    }
    return [client bundleIdentifier];
}

- (BOOL)isEnglishModeActive {
    return [LanguageMode isEnglishModeForBundleIdentifier:[self currentBundleIdentifier]];
}

- (IBAction)toggleEnglishModeForCurrentApp:(id)sender {
    NSString *bundleIdentifier = [self currentBundleIdentifier];
    if ([bundleIdentifier length] == 0) {
        NSBeep();
        return;
    }
    // An explicit choice is recorded either way, so a default-on application
    // can be switched back to Bangla and the choice sticks.
    [LanguageMode setEnglishMode:![self isEnglishModeActive]
             forBundleIdentifier:bundleIdentifier];
}

// Esc returns the raw keystrokes, which is what you want when a word came out
// as Bangla but was meant as English.
- (void)cancelOperation:(id)sender {
    if (!_composedBuffer || [_composedBuffer length] == 0) {
        return;
    }
    NSString *literal = [[_composedBuffer copy] autorelease];
    [self clearCompositionBuffer];
    [_currentCandidates removeAllObjects];
    [self updateComposition];
    [self updateCandidatesPanel];
    [_currentClient insertText:literal replacementRange:NSMakeRange(NSNotFound, 0)];
}

- (void)showPreferences:(id)sender {
    NSWindow *pw = [[[(MainMenuAppDelegate *)[NSApp delegate] imPref] windowController] window];

    [pw setHidesOnDeactivate:NO];
    [pw setLevel:NSModalPanelWindowLevel];
    [pw makeKeyAndOrderFront:self];
}

@end
