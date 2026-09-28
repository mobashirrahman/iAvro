//
//  AvroKeyboard
//
//  Created by Rifat Nabi on 6/21/12.
//  Copyright (c) 2012 OmicronLab. All rights reserved.
//

#import "AvroKeyboardController.h"
#import "MainMenuAppDelegate.h"
#import "Suggestion.h"
#import "Candidates.h"
#import "CacheManager.h"
#import "RegexKitLite.h"
#import "AvroParser.h"
#import "AutoCorrect.h"
#import "SettingsKeys.h"

@interface AvroKeyboardController ()
- (NSString *)compositionDisplayString;
- (NSString *)stringFromCandidate:(id)candidate;
- (void)addEnglishCandidateRemembering:(NSString *)prevString;
- (NSInteger)preferredTransliterationIndex;
- (BOOL)isClassicMode;
- (NSString *)classicOutput;
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

// Windows Avro offers the typed Roman text as the last choice, so English
// words can be typed without switching input sources. Choosing it is
// remembered like any other candidate: the weight cache stores the raw term.
- (void)addEnglishCandidateRemembering:(NSString *)prevString {
    if (![[NSUserDefaults standardUserDefaults] boolForKey:kOfferEnglishDefaultsKey]) {
        return;
    }
    if ([_currentCandidates containsObject:_composedBuffer]) {
        return;
    }
    [_currentCandidates addObject:[[_composedBuffer copy] autorelease]];
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
                if ([candidateText isEqualToString:_composedBuffer]) {
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
        [[CacheManager sharedInstance] schedulePersist];
    }
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
    else {
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
    [self commitText:@"\t"];
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
    if ([self respondsToSelector:aSelector]) {
		// The NSResponder methods like insertNewline: or deleteBackward: are
		// methods that return void. didCommandBySelector method requires
		// that you return YES if the command is handled and NO if you do not. 
		// This is necessary so that unhandled commands can be passed on to the
		// client application. For that reason we need to test in the case where
		// we might not handle the command.
		
		if (_composedBuffer && [_composedBuffer length] > 0) {
            if (aSelector == @selector(insertTab:) 
                || aSelector == @selector(insertNewline:)
                || aSelector == @selector(deleteBackward:)
                || aSelector == @selector(moveLeft:)
                || aSelector == @selector(moveRight:)
                || aSelector == @selector(moveUp:)
                || aSelector == @selector(moveDown:)) {
                [self performSelector:aSelector withObject:sender];
                return YES;
            }
        }
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
    return [(MainMenuAppDelegate *)[NSApp delegate] menu];
}

- (void)showPreferences:(id)sender {
    NSWindow *pw = [[[(MainMenuAppDelegate *)[NSApp delegate] imPref] windowController] window];

    [pw setHidesOnDeactivate:NO];
    [pw setLevel:NSModalPanelWindowLevel];
    [pw makeKeyAndOrderFront:self];
}

@end
