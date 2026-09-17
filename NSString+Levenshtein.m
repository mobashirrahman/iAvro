//
//  NSString+Levenshtein.m
//  Levenshtein
//
//  Created by Stefano Pigozzi on 8/20/09.
//  Copyright 2009 Stefano Pigozzi. All rights reserved.
//

#import "NSString+Levenshtein.h"
#include <stdlib.h>

@implementation NSString (Levenshtein)

/// minimum between three values
static int minimum(int a,int b,int c)
{
	int min=a;
	if(b<min)
		min=b;
	if(c<min)
		min=c;
	return min;
}


-(int) computeLevenshteinDistanceWithString:(NSString *) string
{
	int n = (int)[self length];
	int m = (int)(string ? [string length] : 0);

	if (n == 0) {
		return m;
	}
	if (m == 0) {
		return n;
	}

	int *prev = malloc(sizeof(int) * (m + 1));
	int *curr = malloc(sizeof(int) * (m + 1));
	if (!prev || !curr) {
		free(prev);
		free(curr);
		return (n > m) ? n : m;
	}

	int i, j, cost;
	for (j = 0; j <= m; j++) {
		prev[j] = j;
	}

	for (i = 1; i <= n; i++) {
		curr[0] = i;
		unichar selfChar = [self characterAtIndex:i - 1];
		for (j = 1; j <= m; j++) {
			if (selfChar == [string characterAtIndex:j - 1])
				cost = 0;
			else
				cost = 1;
			curr[j] = minimum(curr[j - 1] + 1, prev[j] + 1, prev[j - 1] + cost);
		}
		int *tmp = prev;
		prev = curr;
		curr = tmp;
	}

	int distance = prev[m];
	free(prev);
	free(curr);
	return distance;
}


@end
