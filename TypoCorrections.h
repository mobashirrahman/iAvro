//
//  TypoCorrections.h
//  Avro Keyboard
//
//  Generates plausible corrections of a mistyped roman term.
//
//  Deliberately narrow. A general approach that also tried single-character
//  substitutions and insertions was measured at recovering only 4 of 14 typos
//  while costing up to 90 lookups and 3.4 seconds per keystroke. Of the two
//  narrower rules, only collapsing a doubled letter survived measurement; see
//  the comment in the implementation for why transposition was dropped.
//

#import <Foundation/Foundation.h>

@interface TypoCorrections : NSObject

// Corrections for a term, most likely first and capped so the caller cannot be
// surprised by the cost. Empty for terms too short to have a useful typo.
+ (NSArray *)correctionsForTerm:(NSString *)term;

// Hard ceiling on how many corrections are offered.
+ (NSUInteger)maximumCorrections;

@end
