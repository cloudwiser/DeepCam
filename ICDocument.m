//
//  ICDocument.m
//  DeepCam
//
//  Created by nichall on 08/08/2014.
//
//

#import <Foundation/Foundation.h>
#import "ICDocument.h"

@implementation ICDocument

@synthesize fileContent;

// Called whenever the application reads data from the file system
- (BOOL)loadFromContents:(id)contents ofType:(NSString *)typeName
                   error:(NSError **)outError
{
    
    if ([contents length] > 0) {
        self.fileContent = [[NSString alloc]
                            initWithBytes:[contents bytes]
                            length:[contents length]
                            encoding:NSUTF8StringEncoding];
    } else {
        // When the file is first created, assign some default content
        self.fileContent = @"Empty";
    }
    
    return YES;
}

// Called whenever the application (auto)saves the content of a file
- (id)contentsForType:(NSString *)typeName error:(NSError **)outError
{
    
    if ([self.fileContent length] == 0) {
        self.fileContent = @"Empty";
    }
    
    return [NSData dataWithBytes:[self.fileContent UTF8String]
                          length:[self.fileContent length]];
    
}

@end
