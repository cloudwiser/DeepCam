//
//  iCloudDocument.h
//  DeepCam
//
//  Created by nichall on 08/08/2014.
//
//

#import <UIKit/UIKit.h>

#ifndef DeepCam_iCloudDocument_h
#define DeepCam_iCloudDocument_h

#define kcloudFilename @"predictor.txt"

@interface iCloudDocument : UIDocument

@property (strong) NSString * fileContent;

@end

#endif
