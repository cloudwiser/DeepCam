//
//  iCloudDocument.m
//  DeepCam
//
//  Created by nichall on 08/08/2014.
//
//

#import <Foundation/Foundation.h>
#import "iCloudDocument.h"

@implementation iCloudDocument

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

/* also see 
    http://stackoverflow.com/questions/20592884/copy-file-to-icloud-without-having-to-remove-the-local-file?rq=1

 - (void)moveFileToiCloud:(FileRepresentation *)fileToMove {
    NSURL *sourceURL = fileToMove.url;
    NSString *destinationFileName = fileToMove.fileName;
    NSURL *destinationURL = [self.documentsDir URLByAppendingPathComponent:destinationFileName];
    
    dispatch_queue_t q_default;
    q_default = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
    dispatch_async(q_default, ^(void) {
        NSFileManager *fileManager = [[[NSFileManager alloc] init] autorelease];
        NSError *error = nil;
        BOOL success = [fileManager setUbiquitous:YES itemAtURL:sourceURL
                                   destinationURL:destinationURL error:&error];
        dispatch_queue_t q_main = dispatch_get_main_queue();
        dispatch_async(q_main, ^(void) {
            if (success) {
                FileRepresentation *fileRepresentation = [[FileRepresentation alloc]
                                                          initWithFileName:fileToMove.fileName url:destinationURL];
                [_fileList removeObject:fileToMove];
                [_fileList addObject:fileRepresentation];
                NSLog(@"moved file to cloud: %@", fileRepresentation);
            }
            if (!success) {
                NSLog(@"Couldn't move file to iCloud: %@", fileToMove);
            }
        });
    });
}

- (void)moveFileToLocal:(FileRepresentation *)fileToMove {
    NSURL *sourceURL = fileToMove.url;
    NSString *destinationFileName = fileToMove.fileName;
    NSURL *destinationURL = [self.documentsDir URLByAppendingPathComponent:destinationFileName];
    
    dispatch_queue_t q_default;
    q_default = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
    dispatch_async(q_default, ^(void) {
        NSFileManager *fileManager = [[[NSFileManager alloc] init] autorelease];
        NSError *error = nil;
        BOOL success = [fileManager setUbiquitous:NO itemAtURL:sourceURL destinationURL:destinationURL
                                            error:&error];
        dispatch_queue_t q_main = dispatch_get_main_queue();
        dispatch_async(q_main, ^(void) {
            if (success) {
                FileRepresentation *fileRepresentation = [[FileRepresentation alloc]
                                                          initWithFileName:fileToMove.fileName url:destinationURL];
                [_fileList removeObject:fileToMove];
                [_fileList addObject:fileRepresentation];
                NSLog(@"moved file to local storage: %@", fileRepresentation);
            }
            if (!success) {
                NSLog(@"Couldn't move file to local storage: %@", fileToMove);
            }
        });
    });
}
*/
@end
