//
//  avro_transliterate.m
//  Build-time helper for tools/update_autodict.py.
//
//  Reads a JSON array of Roman phonetic strings on stdin and writes the
//  array transliterated by the real AvroParser (data.json must sit next to
//  the binary, since AvroParser loads it from the main bundle).
//

#import <Foundation/Foundation.h>
#import "AvroParser.h"

int main(int argc, char *argv[]) {
    @autoreleasepool {
        NSData *input = [[NSFileHandle fileHandleWithStandardInput] readDataToEndOfFile];
        NSArray *terms = [NSJSONSerialization JSONObjectWithData:input options:0 error:NULL];
        if (![terms isKindOfClass:[NSArray class]]) {
            fprintf(stderr, "expected a JSON array of strings on stdin\n");
            return 1;
        }
        NSMutableArray *output = [NSMutableArray arrayWithCapacity:[terms count]];
        for (NSString *term in terms) {
            [output addObject:[[AvroParser sharedInstance] parse:term]];
        }
        NSData *json = [NSJSONSerialization dataWithJSONObject:output options:0 error:NULL];
        [[NSFileHandle fileHandleWithStandardOutput] writeData:json];
    }
    return 0;
}
