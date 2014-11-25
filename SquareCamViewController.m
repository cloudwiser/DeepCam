/*
     File: SquareCamViewController.m
 Abstract: Dmonstrates iOS 5 features of the AVCaptureStillImageOutput class
  Version: 1.0
 
 Disclaimer: IMPORTANT:  This Apple software is supplied to you by Apple
 Inc. ("Apple") in consideration of your agreement to the following
 terms, and your use, installation, modification or redistribution of
 this Apple software constitutes acceptance of these terms.  If you do
 not agree with these terms, please do not use, install, modify or
 redistribute this Apple software.
 
 In consideration of your agreement to abide by the following terms, and
 subject to these terms, Apple grants you a personal, non-exclusive
 license, under Apple's copyrights in this original Apple software (the
 "Apple Software"), to use, reproduce, modify and redistribute the Apple
 Software, with or without modifications, in source and/or binary forms;
 provided that if you redistribute the Apple Software in its entirety and
 without modifications, you must retain this notice and the following
 text and disclaimers in all such redistributions of the Apple Software.
 Neither the name, trademarks, service marks or logos of Apple Inc. may
 be used to endorse or promote products derived from the Apple Software
 without specific prior written permission from Apple.  Except as
 expressly stated in this notice, no other rights or licenses, express or
 implied, are granted by Apple herein, including but not limited to any
 patent rights that may be infringed by your derivative works or by other
 works in which the Apple Software may be incorporated.
 
 The Apple Software is provided by Apple on an "AS IS" basis.  APPLE
 MAKES NO WARRANTIES, EXPRESS OR IMPLIED, INCLUDING WITHOUT LIMITATION
 THE IMPLIED WARRANTIES OF NON-INFRINGEMENT, MERCHANTABILITY AND FITNESS
 FOR A PARTICULAR PURPOSE, REGARDING THE APPLE SOFTWARE OR ITS USE AND
 OPERATION ALONE OR IN COMBINATION WITH YOUR PRODUCTS.
 
 IN NO EVENT SHALL APPLE BE LIABLE FOR ANY SPECIAL, INDIRECT, INCIDENTAL
 OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
 SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
 INTERRUPTION) ARISING IN ANY WAY OUT OF THE USE, REPRODUCTION,
 MODIFICATION AND/OR DISTRIBUTION OF THE APPLE SOFTWARE, HOWEVER CAUSED
 AND WHETHER UNDER THEORY OF CONTRACT, TORT (INCLUDING NEGLIGENCE),
 STRICT LIABILITY OR OTHERWISE, EVEN IF APPLE HAS BEEN ADVISED OF THE
 POSSIBILITY OF SUCH DAMAGE.
 
 Copyright (C) 2013 Apple Inc. All Rights Reserved.
 
 */

#import "SquareCamViewController.h"
#import <CoreImage/CoreImage.h>
#import <ImageIO/ImageIO.h>
#import <AssertMacros.h>
#import <AssetsLibrary/AssetsLibrary.h>
#include <sys/time.h>

#import "DeepBelief/DeepBelief.h"

#pragma mark-

const int kPositivePredictionTotal = 100;
const int kNegativePredictionTotal = 100;
const int kElementsPerPrediction = 4096;

const float kMinSecondsBetweenPings = 0.5f;

enum EPredictionState {
    eWaiting,
    ePositiveLearning,
    eNegativeWaiting,
    eNegativeLearning,
    ePredicting,
};

enum ECloudDocumentState {
    eCloudDocumentUnknown,
    eCloudDocumentOpened,
    eCloudDocumentCreated,
    eCloudDocumentOpenFailed,
    eCloudDocumentCreateFailed,
};

// used for KVO observation of the @"capturingStillImage" property to perform flash bulb animation
static const NSString *AVCaptureStillImageIsCapturingStillImageContext = @"AVCaptureStillImageIsCapturingStillImageContext";

static CGFloat DegreesToRadians(CGFloat degrees) {return degrees * M_PI / 180;};

// utility used by newSquareOverlayedImageForFeatures for
static CGContextRef CreateCGBitmapContextForSize(CGSize size);
static CGContextRef CreateCGBitmapContextForSize(CGSize size)
{
    CGContextRef    context = NULL;
    CGColorSpaceRef colorSpace;
    int             bitmapBytesPerRow;
	
    bitmapBytesPerRow = (size.width * 4);
	
    colorSpace = CGColorSpaceCreateDeviceRGB();
    context = CGBitmapContextCreate (NULL,
									 size.width,
									 size.height,
									 8,      // bits per component
									 bitmapBytesPerRow,
									 colorSpace,
									 (CGBitmapInfo)kCGImageAlphaPremultipliedLast);
	CGContextSetAllowsAntialiasing(context, NO);
    CGColorSpaceRelease( colorSpace );
    return context;
}

#pragma mark-

@interface UIImage (RotationMethods)
- (UIImage *)imageRotatedByDegrees:(CGFloat)degrees;
@end

@implementation UIImage (RotationMethods)

- (UIImage *)imageRotatedByDegrees:(CGFloat)degrees 
{   
	// calculate the size of the rotated view's containing box for our drawing space
	UIView *rotatedViewBox = [[UIView alloc] initWithFrame:CGRectMake(0,0,self.size.width, self.size.height)];
	CGAffineTransform t = CGAffineTransformMakeRotation(DegreesToRadians(degrees));
	rotatedViewBox.transform = t;
	CGSize rotatedSize = rotatedViewBox.frame.size;
	[rotatedViewBox release];
	
	// Create the bitmap context
	UIGraphicsBeginImageContext(rotatedSize);
	CGContextRef bitmap = UIGraphicsGetCurrentContext();
	
	// Move the origin to the middle of the image so we will rotate and scale around the center.
	CGContextTranslateCTM(bitmap, rotatedSize.width/2, rotatedSize.height/2);
	
	//   // Rotate the image context
	CGContextRotateCTM(bitmap, DegreesToRadians(degrees));
	
	// Now, draw the rotated/scaled image into the context
	CGContextScaleCTM(bitmap, 1.0, -1.0);
	CGContextDrawImage(bitmap, CGRectMake(-self.size.width / 2, -self.size.height / 2, self.size.width, self.size.height), [self CGImage]);
	
	UIImage *newImage = UIGraphicsGetImageFromCurrentImageContext();
	UIGraphicsEndImageContext();
	return newImage;
	
}

@end

#pragma mark-

@interface SquareCamViewController (InternalMethods)
- (void)setupAVCapture;
- (void)teardownAVCapture;
- (void)drawFaceBoxesForFeatures:(NSArray *)features forVideoBox:(CGRect)clap orientation:(UIDeviceOrientation)orientation;
@end

@implementation SquareCamViewController

@synthesize fileDownloadMonitorQuery = _fileDownloadMonitorQuery;
@synthesize currentLocation = _currentLocation;

- (void)setupAVCapture
{
	NSError *error = nil;
	
	session = [AVCaptureSession new];
	if ([[UIDevice currentDevice] userInterfaceIdiom] == UIUserInterfaceIdiomPhone)
	    [session setSessionPreset:AVCaptureSessionPreset640x480];
	else
	    [session setSessionPreset:AVCaptureSessionPresetPhoto];
	
    // Select a video device, make an input
	AVCaptureDevice *device = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
	AVCaptureDeviceInput *deviceInput = [AVCaptureDeviceInput deviceInputWithDevice:device error:&error];
	require( error == nil, bail );
	
    isUsingFrontFacingCamera = NO;
	if ( [session canAddInput:deviceInput] )
		[session addInput:deviceInput];
	
    // Make a still image output
	stillImageOutput = [AVCaptureStillImageOutput new];
	[stillImageOutput addObserver:self forKeyPath:@"capturingStillImage" options:NSKeyValueObservingOptionNew context:AVCaptureStillImageIsCapturingStillImageContext];
	if ( [session canAddOutput:stillImageOutput] )
		[session addOutput:stillImageOutput];
	
    // Make a video data output
	videoDataOutput = [AVCaptureVideoDataOutput new];
	
    // we want BGRA, both CoreGraphics and OpenGL work well with 'BGRA'
	NSDictionary *rgbOutputSettings = [NSDictionary dictionaryWithObject:
									   [NSNumber numberWithInt:kCMPixelFormat_32BGRA] forKey:(id)kCVPixelBufferPixelFormatTypeKey];
	[videoDataOutput setVideoSettings:rgbOutputSettings];
	[videoDataOutput setAlwaysDiscardsLateVideoFrames:YES]; // discard if the data output queue is blocked (as we process the still image)
    
    // create a serial dispatch queue used for the sample buffer delegate as well as when a still image is captured
    // a serial dispatch queue must be used to guarantee that video frames will be delivered in order
    // see the header doc for setSampleBufferDelegate:queue: for more information
	videoDataOutputQueue = dispatch_queue_create("VideoDataOutputQueue", DISPATCH_QUEUE_SERIAL);
	[videoDataOutput setSampleBufferDelegate:self queue:videoDataOutputQueue];
	
    if ( [session canAddOutput:videoDataOutput] )
		[session addOutput:videoDataOutput];
	[[videoDataOutput connectionWithMediaType:AVMediaTypeVideo] setEnabled:YES];
	detectFaces = YES;
  
	effectiveScale = 1.0;
	previewLayer = [[AVCaptureVideoPreviewLayer alloc] initWithSession:session];
	[previewLayer setBackgroundColor:[[UIColor blackColor] CGColor]];
	[previewLayer setVideoGravity:AVLayerVideoGravityResizeAspect];
	CALayer *rootLayer = [previewView layer];
	[rootLayer setMasksToBounds:YES];
	[previewLayer setFrame:[rootLayer bounds]];
	[rootLayer addSublayer:previewLayer];
	[session startRunning];

bail:
	[session release];
	if (error) {
		UIAlertView *alertView = [[UIAlertView alloc] initWithTitle:[NSString stringWithFormat:@"Failed with error %d", (int)[error code]]
															message:[error localizedDescription]
														   delegate:nil 
												  cancelButtonTitle:@"Dismiss" 
												  otherButtonTitles:nil];
		[alertView show];
		[alertView release];
		[self teardownAVCapture];
	}
}

// clean up capture setup
- (void)teardownAVCapture
{
	[videoDataOutput release];
	if (videoDataOutputQueue)
		dispatch_release(videoDataOutputQueue);
	[stillImageOutput removeObserver:self forKeyPath:@"isCapturingStillImage"];
	[stillImageOutput release];
	[previewLayer removeFromSuperlayer];
	[previewLayer release];
}

// perform a flash bulb animation using KVO to monitor the value of the capturingStillImage property of the AVCaptureStillImageOutput class
- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
	if ( context == AVCaptureStillImageIsCapturingStillImageContext ) {
		BOOL isCapturingStillImage = [[change objectForKey:NSKeyValueChangeNewKey] boolValue];
		
		if ( isCapturingStillImage ) {
			// do flash bulb like animation
			flashView = [[UIView alloc] initWithFrame:[previewView frame]];
			[flashView setBackgroundColor:[UIColor whiteColor]];
			[flashView setAlpha:0.f];
			[[[self view] window] addSubview:flashView];
			
			[UIView animateWithDuration:.4f
							 animations:^{
								 [flashView setAlpha:1.f];
							 }
			 ];
		}
		else {
			[UIView animateWithDuration:.4f
							 animations:^{
								 [flashView setAlpha:0.f];
							 }
							 completion:^(BOOL finished){
								 [flashView removeFromSuperview];
								 [flashView release];
								 flashView = nil;
							 }
			 ];
		}
	}
}

// utility routing used during image capture to set up capture orientation
- (AVCaptureVideoOrientation)avOrientationForDeviceOrientation:(UIDeviceOrientation)deviceOrientation
{
	AVCaptureVideoOrientation result = (AVCaptureVideoOrientation)deviceOrientation;
	if ( deviceOrientation == UIDeviceOrientationLandscapeLeft )
		result = AVCaptureVideoOrientationLandscapeRight;
	else if ( deviceOrientation == UIDeviceOrientationLandscapeRight )
		result = AVCaptureVideoOrientationLandscapeLeft;
	return result;
}

// utility routine to create a new image with the red square overlay with appropriate orientation
// and return the new composited image which can be saved to the camera roll
- (CGImageRef)newSquareOverlayedImageForFeatures:(NSArray *)features 
											inCGImage:(CGImageRef)backgroundImage 
									  withOrientation:(UIDeviceOrientation)orientation 
										  frontFacing:(BOOL)isFrontFacing
{
	CGImageRef returnImage = NULL;
	CGRect backgroundImageRect = CGRectMake(0., 0., CGImageGetWidth(backgroundImage), CGImageGetHeight(backgroundImage));
	CGContextRef bitmapContext = CreateCGBitmapContextForSize(backgroundImageRect.size);
	CGContextClearRect(bitmapContext, backgroundImageRect);
	CGContextDrawImage(bitmapContext, backgroundImageRect, backgroundImage);
	CGFloat rotationDegrees = 0.;
	
	switch (orientation) {
		case UIDeviceOrientationPortrait:
			rotationDegrees = -90.;
			break;
		case UIDeviceOrientationPortraitUpsideDown:
			rotationDegrees = 90.;
			break;
		case UIDeviceOrientationLandscapeLeft:
			if (isFrontFacing) rotationDegrees = 180.;
			else rotationDegrees = 0.;
			break;
		case UIDeviceOrientationLandscapeRight:
			if (isFrontFacing) rotationDegrees = 0.;
			else rotationDegrees = 180.;
			break;
		case UIDeviceOrientationFaceUp:
		case UIDeviceOrientationFaceDown:
		default:
			break; // leave the layer in its last known orientation
	}
	UIImage *rotatedSquareImage = [square imageRotatedByDegrees:rotationDegrees];
	
    // features found by the face detector
	for ( CIFaceFeature *ff in features ) {
		CGRect faceRect = [ff bounds];
		CGContextDrawImage(bitmapContext, faceRect, [rotatedSquareImage CGImage]);
	}
	returnImage = CGBitmapContextCreateImage(bitmapContext);
	CGContextRelease (bitmapContext);
	
	return returnImage;
}

// utility routine used after taking a still image to write the resulting image to the camera roll
- (BOOL)writeCGImageToCameraRoll:(CGImageRef)cgImage withMetadata:(NSDictionary *)metadata
{
	CFMutableDataRef destinationData = CFDataCreateMutable(kCFAllocatorDefault, 0);
	CGImageDestinationRef destination = CGImageDestinationCreateWithData(destinationData, 
																		 CFSTR("public.jpeg"), 
																		 1, 
																		 NULL);
	BOOL success = (destination != NULL);
	require(success, bail);

	const float JPEGCompQuality = 0.85f; // JPEGHigherQuality
	CFMutableDictionaryRef optionsDict = NULL;
	CFNumberRef qualityNum = NULL;
	
	qualityNum = CFNumberCreate(0, kCFNumberFloatType, &JPEGCompQuality);    
	if ( qualityNum ) {
		optionsDict = CFDictionaryCreateMutable(0, 0, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
		if ( optionsDict )
			CFDictionarySetValue(optionsDict, kCGImageDestinationLossyCompressionQuality, qualityNum);
		CFRelease( qualityNum );
	}
	
	CGImageDestinationAddImage( destination, cgImage, optionsDict );
	success = CGImageDestinationFinalize( destination );

	if ( optionsDict )
		CFRelease(optionsDict);
	
	require(success, bail);
	
	CFRetain(destinationData);
	ALAssetsLibrary *library = [ALAssetsLibrary new];
	[library writeImageDataToSavedPhotosAlbum:(id)destinationData metadata:metadata completionBlock:^(NSURL *assetURL, NSError *error) {
		if (destinationData)
			CFRelease(destinationData);
	}];
	[library release];


bail:
	if (destinationData)
		CFRelease(destinationData);
	if (destination)
		CFRelease(destination);
	return success;
}

// utility routine to display error aleart if takePicture fails
- (void)displayErrorOnMainQueue:(NSError *)error withMessage:(NSString *)message
{
	dispatch_async(dispatch_get_main_queue(), ^(void) {
		UIAlertView *alertView = [[UIAlertView alloc] initWithTitle:[NSString stringWithFormat:@"%@ (%d)", message, (int)[error code]]
															message:[error localizedDescription]
														   delegate:nil 
												  cancelButtonTitle:@"Dismiss" 
												  otherButtonTitles:nil];
		[alertView show];
		[alertView release];
	});
}

// main action method to take a still image -- if face detection has been turned on and a face has been detected
// the square overlay will be composited on top of the captured image and saved to the camera roll
- (IBAction)takePicture:(id)sender
{
    switch (predictionState) {
        case eWaiting: {
            [sender setTitle: @"Learning..." forState:UIControlStateNormal];
            [self triggerNextState];
        } break;
            
        case ePositiveLearning: {
            // Do nothing
        } break;
            
        case eNegativeWaiting: {
            [sender setTitle: @"Learning..." forState:UIControlStateNormal];
            [self triggerNextState];
        } break;
            
        case eNegativeLearning: {
            // Do nothing
        } break;
            
        case ePredicting: {
            [self triggerNextState];
        } break;
            
        default: {
            assert(FALSE); // Should never get here
        } break;
    }
}

// turn on/off face detection
- (IBAction)toggleFaceDetection:(id)sender
{
	detectFaces = [(UISwitch *)sender isOn];
	[[videoDataOutput connectionWithMediaType:AVMediaTypeVideo] setEnabled:detectFaces];
	if (!detectFaces) {
		dispatch_async(dispatch_get_main_queue(), ^(void) {
			// clear out any squares currently displaying.
			[self drawFaceBoxesForFeatures:[NSArray array] forVideoBox:CGRectZero orientation:UIDeviceOrientationPortrait];
		});
	}
}

// find where the video box is positioned within the preview layer based on the video size and gravity
+ (CGRect)videoPreviewBoxForGravity:(NSString *)gravity frameSize:(CGSize)frameSize apertureSize:(CGSize)apertureSize
{
    CGFloat apertureRatio = apertureSize.height / apertureSize.width;
    CGFloat viewRatio = frameSize.width / frameSize.height;
    
    CGSize size = CGSizeZero;
    if ([gravity isEqualToString:AVLayerVideoGravityResizeAspectFill]) {
        if (viewRatio > apertureRatio) {
            size.width = frameSize.width;
            size.height = apertureSize.width * (frameSize.width / apertureSize.height);
        } else {
            size.width = apertureSize.height * (frameSize.height / apertureSize.width);
            size.height = frameSize.height;
        }
    } else if ([gravity isEqualToString:AVLayerVideoGravityResizeAspect]) {
        if (viewRatio > apertureRatio) {
            size.width = apertureSize.height * (frameSize.height / apertureSize.width);
            size.height = frameSize.height;
        } else {
            size.width = frameSize.width;
            size.height = apertureSize.width * (frameSize.width / apertureSize.height);
        }
    } else if ([gravity isEqualToString:AVLayerVideoGravityResize]) {
        size.width = frameSize.width;
        size.height = frameSize.height;
    }
	
	CGRect videoBox;
	videoBox.size = size;
	if (size.width < frameSize.width)
		videoBox.origin.x = (frameSize.width - size.width) / 2;
	else
		videoBox.origin.x = (size.width - frameSize.width) / 2;
	
	if ( size.height < frameSize.height )
		videoBox.origin.y = (frameSize.height - size.height) / 2;
	else
		videoBox.origin.y = (size.height - frameSize.height) / 2;
    
	return videoBox;
}

// called asynchronously as the capture output is capturing sample buffers, this method asks the face detector (if on)
// to detect features and for each draw the red square in a layer and set appropriate orientation
- (void)drawFaceBoxesForFeatures:(NSArray *)features forVideoBox:(CGRect)clap orientation:(UIDeviceOrientation)orientation
{
	NSArray *sublayers = [NSArray arrayWithArray:[previewLayer sublayers]];
	NSInteger sublayersCount = [sublayers count], currentSublayer = 0;
	NSInteger featuresCount = [features count], currentFeature = 0;
	
	[CATransaction begin];
	[CATransaction setValue:(id)kCFBooleanTrue forKey:kCATransactionDisableActions];
	
	// hide all the face layers
	for ( CALayer *layer in sublayers ) {
		if ( [[layer name] isEqualToString:@"FaceLayer"] )
			[layer setHidden:YES];
	}	
	
	if ( featuresCount == 0 || !detectFaces ) {
		[CATransaction commit];
		return; // early bail.
	}
		
	CGSize parentFrameSize = [previewView frame].size;
	NSString *gravity = [previewLayer videoGravity];
	BOOL isMirrored = previewLayer.connection.videoMirrored;
	CGRect previewBox = [SquareCamViewController videoPreviewBoxForGravity:gravity 
															   frameSize:parentFrameSize 
															apertureSize:clap.size];
	
	for ( CIFaceFeature *ff in features ) {
		// find the correct position for the square layer within the previewLayer
		// the feature box originates in the bottom left of the video frame.
		// (Bottom right if mirroring is turned on)
		CGRect faceRect = [ff bounds];

		// flip preview width and height
		CGFloat temp = faceRect.size.width;
		faceRect.size.width = faceRect.size.height;
		faceRect.size.height = temp;
		temp = faceRect.origin.x;
		faceRect.origin.x = faceRect.origin.y;
		faceRect.origin.y = temp;
		// scale coordinates so they fit in the preview box, which may be scaled
		CGFloat widthScaleBy = previewBox.size.width / clap.size.height;
		CGFloat heightScaleBy = previewBox.size.height / clap.size.width;
		faceRect.size.width *= widthScaleBy;
		faceRect.size.height *= heightScaleBy;
		faceRect.origin.x *= widthScaleBy;
		faceRect.origin.y *= heightScaleBy;

		if ( isMirrored )
			faceRect = CGRectOffset(faceRect, previewBox.origin.x + previewBox.size.width - faceRect.size.width - (faceRect.origin.x * 2), previewBox.origin.y);
		else
			faceRect = CGRectOffset(faceRect, previewBox.origin.x, previewBox.origin.y);
		
		CALayer *featureLayer = nil;
		
		// re-use an existing layer if possible
		while ( !featureLayer && (currentSublayer < sublayersCount) ) {
			CALayer *currentLayer = [sublayers objectAtIndex:currentSublayer++];
			if ( [[currentLayer name] isEqualToString:@"FaceLayer"] ) {
				featureLayer = currentLayer;
				[currentLayer setHidden:NO];
			}
		}
		
		// create a new one if necessary
		if ( !featureLayer ) {
			featureLayer = [CALayer new];
			[featureLayer setContents:(id)[square CGImage]];
			[featureLayer setName:@"FaceLayer"];
			[previewLayer addSublayer:featureLayer];
			[featureLayer release];
		}
		[featureLayer setFrame:faceRect];
		
		switch (orientation) {
			case UIDeviceOrientationPortrait:
				[featureLayer setAffineTransform:CGAffineTransformMakeRotation(DegreesToRadians(0.))];
				break;
			case UIDeviceOrientationPortraitUpsideDown:
				[featureLayer setAffineTransform:CGAffineTransformMakeRotation(DegreesToRadians(180.))];
				break;
			case UIDeviceOrientationLandscapeLeft:
				[featureLayer setAffineTransform:CGAffineTransformMakeRotation(DegreesToRadians(90.))];
				break;
			case UIDeviceOrientationLandscapeRight:
				[featureLayer setAffineTransform:CGAffineTransformMakeRotation(DegreesToRadians(-90.))];
				break;
			case UIDeviceOrientationFaceUp:
			case UIDeviceOrientationFaceDown:
			default:
				break; // leave the layer in its last known orientation
		}
		currentFeature++;
	}
	
	[CATransaction commit];
}

- (void)captureOutput:(AVCaptureOutput *)captureOutput didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(AVCaptureConnection *)connection
{
  CVPixelBufferRef pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
  [self runCNNOnFrame:pixelBuffer];
}

- (void)runCNNOnFrame: (CVPixelBufferRef) pixelBuffer
{
    assert(pixelBuffer != NULL);
    
    OSType sourcePixelFormat = CVPixelBufferGetPixelFormatType( pixelBuffer );
    int doReverseChannels;
    if ( kCVPixelFormatType_32ARGB == sourcePixelFormat ) {
        doReverseChannels = 1;
    } else if ( kCVPixelFormatType_32BGRA == sourcePixelFormat ) {
        doReverseChannels = 0;
    } else {
        assert(false); // Unknown source format
    }
    
    const int sourceRowBytes = (int)CVPixelBufferGetBytesPerRow( pixelBuffer );
    const int width = (int)CVPixelBufferGetWidth( pixelBuffer );
    const int fullHeight = (int)CVPixelBufferGetHeight( pixelBuffer );
    CVPixelBufferLockBaseAddress( pixelBuffer, 0 );
    unsigned char* sourceBaseAddr = CVPixelBufferGetBaseAddress( pixelBuffer );
    int height;
    unsigned char* sourceStartAddr;
    if (fullHeight <= width) {
        height = fullHeight;
        sourceStartAddr = sourceBaseAddr;
    } else {
        height = width;
        const int marginY = ((fullHeight - width) / 2);
        sourceStartAddr = (sourceBaseAddr + (marginY * sourceRowBytes));
    }
    
    void* cnnInput = jpcnn_create_image_buffer_from_uint8_data(sourceStartAddr, width, height, 4, sourceRowBytes, doReverseChannels, 1);
    float* predictions;
    int predictionsLength;
    char** predictionsLabels;
    int predictionsLabelsLength;
    
    struct timeval start;
    gettimeofday(&start, NULL);
    jpcnn_classify_image(network, cnnInput, JPCNN_RANDOM_SAMPLE, -2, &predictions, &predictionsLength, &predictionsLabels, &predictionsLabelsLength);
    struct timeval end;
    gettimeofday(&end, NULL);
    
//    const long seconds  = end.tv_sec  - start.tv_sec;
//    const long useconds = end.tv_usec - start.tv_usec;
//    const float duration = ((seconds) * 1000 + useconds/1000.0) + 0.5;
//    NSLog(@"Took %f ms", duration);
    
    jpcnn_destroy_image_buffer(cnnInput);
    
    dispatch_async(dispatch_get_main_queue(), ^(void) {
        [self handleNetworkPredictions: predictions withLength: predictionsLength];
    });
}

- (void)dealloc
{
	[self teardownAVCapture];
	[faceDetector release];
	[square release];
    [_mainButton release];
	[super dealloc];
}

// use front/back camera
- (IBAction)switchCameras:(id)sender
{
	AVCaptureDevicePosition desiredPosition;
	if (isUsingFrontFacingCamera)
		desiredPosition = AVCaptureDevicePositionBack;
	else
		desiredPosition = AVCaptureDevicePositionFront;
	
	for (AVCaptureDevice *d in [AVCaptureDevice devicesWithMediaType:AVMediaTypeVideo]) {
		if ([d position] == desiredPosition) {
			[[previewLayer session] beginConfiguration];
			AVCaptureDeviceInput *input = [AVCaptureDeviceInput deviceInputWithDevice:d error:nil];
			for (AVCaptureInput *oldInput in [[previewLayer session] inputs]) {
				[[previewLayer session] removeInput:oldInput];
			}
			[[previewLayer session] addInput:input];
			[[previewLayer session] commitConfiguration];
			break;
		}
	}
	isUsingFrontFacingCamera = !isUsingFrontFacingCamera;
}

#pragma mark - View lifecycle

- (void)viewDidLoad
{
    [super viewDidLoad];

    NSString* networkPath = [[NSBundle mainBundle] pathForResource:@"jetpac" ofType:@"ntwk"];
    if (networkPath == NULL) {
        NSLog(@"Couldn't find the neural network parameters file - did you add it as a resource to your application?\n");
        assert(false);
    }
    network = jpcnn_create_network([networkPath UTF8String]);
    assert(network != NULL);

    [self setupLearning];
    
    [self setupAVCapture];
    square = [[UIImage imageNamed:@"squarePNG"] retain];
    NSDictionary *detectorOptions = [[NSDictionary alloc] initWithObjectsAndKeys:CIDetectorAccuracyLow, CIDetectorAccuracy, nil];
    faceDetector = [[CIDetector detectorOfType:CIDetectorTypeFace context:nil options:detectorOptions] retain];
    [detectorOptions release];

    synth = [[AVSpeechSynthesizer alloc] init];
    labelLayers = [[NSMutableArray alloc] init];
    oldPredictionValues = [[NSMutableDictionary alloc] init];

    // Create location, manager & start updating
    if (currentLocation == nil)
        currentLocation = [[CLLocation alloc] init];
    if (locationManager == nil)
        locationManager = [[CLLocationManager alloc] init];
    locationManager.delegate = self;
    locationManager.desiredAccuracy = kCLLocationAccuracyKilometer;
    // Set a movement threshold for new events
    locationManager.distanceFilter = kCLDistanceFilterNone; // was 500 meters
    
    _iCloudURLs = [[NSMutableArray alloc] init];
    // Add at beginning of a refresh method
    _iCloudURLsReady = NO;
    [_iCloudURLs removeAllObjects];
    
    [locationManager requestWhenInUseAuthorization];
    [locationManager startUpdatingLocation];
}

- (void)viewDidUnload
{
    [super viewDidUnload];
    // Release any retained subviews of the main view.
    // e.g. self.myOutlet = nil;
    [oldPredictionValues release];
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
}

- (void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];
    [_query enableUpdates];
}

- (void)viewWillDisappear:(BOOL)animated
{
	[super viewWillDisappear:animated];
    [_query disableUpdates];
}

- (void)viewDidDisappear:(BOOL)animated
{
	[super viewDidDisappear:animated];
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Release any cached data, images, etc that aren't in use.
}

#pragma mark - View and input management

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation
{
    // Return YES for supported orientations
	return (interfaceOrientation == UIInterfaceOrientationPortrait);
}

- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)gestureRecognizer
{
	if ( [gestureRecognizer isKindOfClass:[UIPinchGestureRecognizer class]] ) {
		beginGestureScale = effectiveScale;
	}
	return YES;
}

// scale image depending on users pinch gesture
- (IBAction)handlePinchGesture:(UIPinchGestureRecognizer *)recognizer
{
	BOOL allTouchesAreOnThePreviewLayer = YES;
	NSUInteger numTouches = [recognizer numberOfTouches], i;
	for ( i = 0; i < numTouches; ++i ) {
		CGPoint location = [recognizer locationOfTouch:i inView:previewView];
		CGPoint convertedLocation = [previewLayer convertPoint:location fromLayer:previewLayer.superlayer];
		if ( ! [previewLayer containsPoint:convertedLocation] ) {
			allTouchesAreOnThePreviewLayer = NO;
			break;
		}
	}
	
	if ( allTouchesAreOnThePreviewLayer ) {
		effectiveScale = beginGestureScale * recognizer.scale;
		if (effectiveScale < 1.0)
			effectiveScale = 1.0;
		CGFloat maxScaleAndCropFactor = [[stillImageOutput connectionWithMediaType:AVMediaTypeVideo] videoMaxScaleAndCropFactor];
		if (effectiveScale > maxScaleAndCropFactor)
			effectiveScale = maxScaleAndCropFactor;
		[CATransaction begin];
		[CATransaction setAnimationDuration:.025];
		[previewLayer setAffineTransform:CGAffineTransformMakeScale(effectiveScale, effectiveScale)];
		[CATransaction commit];
	}
}

- (BOOL)prefersStatusBarHidden
{
    return YES;
}

#pragma mark - DeepBelief predictor lifecycle

- (void) setPredictionValues: (NSDictionary*) newValues
{
    const float decayValue = 0.75f;
    const float updateValue = 0.25f;
    const float minimumThreshold = 0.01f;

    NSMutableDictionary* decayedPredictionValues = [[NSMutableDictionary alloc] init];
  
    for (NSString* label in oldPredictionValues) {
        NSNumber* oldPredictionValueObject = [oldPredictionValues objectForKey:label];
        const float oldPredictionValue = [oldPredictionValueObject floatValue];
        const float decayedPredictionValue = (oldPredictionValue * decayValue);
        if (decayedPredictionValue > minimumThreshold) {
            NSNumber* decayedPredictionValueObject = [NSNumber numberWithFloat: decayedPredictionValue];
            [decayedPredictionValues setObject: decayedPredictionValueObject forKey:label];
        }
    }
    [oldPredictionValues release];
    oldPredictionValues = decayedPredictionValues;

    for (NSString* label in newValues) {
        NSNumber* newPredictionValueObject = [newValues objectForKey:label];
        NSNumber* oldPredictionValueObject = [oldPredictionValues objectForKey:label];
        if (!oldPredictionValueObject) {
            oldPredictionValueObject = [NSNumber numberWithFloat: 0.0f];
        }
        const float newPredictionValue = [newPredictionValueObject floatValue];
        const float oldPredictionValue = [oldPredictionValueObject floatValue];
        const float updatedPredictionValue = (oldPredictionValue + (newPredictionValue * updateValue));
        NSNumber* updatedPredictionValueObject = [NSNumber numberWithFloat: updatedPredictionValue];
        [oldPredictionValues setObject: updatedPredictionValueObject forKey:label];
    }
    
    NSArray* candidateLabels = [NSMutableArray array];
    for (NSString* label in oldPredictionValues) {
        NSNumber* oldPredictionValueObject = [oldPredictionValues objectForKey:label];
        const float oldPredictionValue = [oldPredictionValueObject floatValue];
        if (oldPredictionValue > 0.05f) {
            NSDictionary *entry = @{
                                    @"label" : label,
                                    @"value" : oldPredictionValueObject
                                    };
            candidateLabels = [candidateLabels arrayByAddingObject: entry];
        }
    }
  
    NSSortDescriptor *sort = [NSSortDescriptor sortDescriptorWithKey:@"value" ascending:NO];
    NSArray* sortedLabels = [candidateLabels sortedArrayUsingDescriptors:[NSArray arrayWithObject:sort]];

    const float leftMargin = 10.0f;
    const float topMargin = 10.0f;

    const float valueWidth = 48.0f;
    const float valueHeight = 26.0f;

    const float labelWidth = 246.0f;
    const float labelHeight = 26.0f;

    const float labelMarginX = 5.0f;
    const float labelMarginY = 5.0f;

    [self removeAllLabelLayers];

    int labelCount = 0;
    for (NSDictionary* entry in sortedLabels) {
        NSString* label = [entry objectForKey: @"label"];
        NSNumber* valueObject =[entry objectForKey: @"value"];
        
        const float value = [valueObject floatValue];
        const float originY = (topMargin + ((labelHeight + labelMarginY) * labelCount));
        const int valuePercentage = (int)roundf(value * 100.0f);
        const float valueOriginX = leftMargin;
        NSString* valueText = [NSString stringWithFormat:@"%d%%", valuePercentage];

        [self addLabelLayerWithText:valueText
                            originX:valueOriginX originY:originY
                              width:valueWidth height:valueHeight
                          alignment: kCAAlignmentRight];

        const float labelOriginX = (leftMargin + valueWidth + labelMarginX);

        [self addLabelLayerWithText: [label capitalizedString]
                            originX: labelOriginX originY: originY
                              width: labelWidth height: labelHeight
                          alignment:kCAAlignmentLeft];

        if ((labelCount == 0) && (value > 0.5f)) {
            if ([[NSUserDefaults standardUserDefaults] boolForKey:@"useSpeech"])
                [self speak:[label capitalizedString]];
        }

        labelCount += 1;
        if (labelCount > 4) {
            break;
        }
    }
}

- (void) removeAllLabelLayers
{
    for (CATextLayer* layer in labelLayers) {
        [layer removeFromSuperlayer];
    }
    [labelLayers removeAllObjects];
}

- (void) addLabelLayerWithText: (NSString*) text originX:(float) originX originY:(float) originY
  width:(float) width height:(float) height alignment:(NSString*) alignment
{
    NSString* const font = @"HelveticaNeue";
    const float fontSize = 20.0f;

    const float marginSizeX = 5.0f;
    const float marginSizeY = 2.0f;

    const CGRect backgroundBounds = CGRectMake(originX, originY, width, height);
    const CGRect textBounds = CGRectMake((originX + marginSizeX), (originY + marginSizeY),
    (width - (marginSizeX * 2)), (height - (marginSizeY * 2)));

    CATextLayer* background = [CATextLayer layer];
    [background setBackgroundColor: [UIColor blackColor].CGColor];
    [background setOpacity:0.5f];
    [background setFrame: backgroundBounds];
    background.cornerRadius = 5.0f;

    [[self.view layer] addSublayer: background];
    [labelLayers addObject: background];

    CATextLayer *layer = [CATextLayer layer];
    [layer setForegroundColor: [UIColor whiteColor].CGColor];
    [layer setFrame: textBounds];
    [layer setAlignmentMode: alignment];
    [layer setWrapped: YES];
    [layer setFont: font];
    [layer setFontSize: fontSize];
    layer.contentsScale = [[UIScreen mainScreen] scale];
    [layer setString: text];

    [[self.view layer] addSublayer: layer];
    [labelLayers addObject: layer];
}

- (void) setPredictionText: (NSString*) text withDuration: (float) duration
{
    if (duration > 0.0) {
        CABasicAnimation *colorAnimation = [CABasicAnimation animationWithKeyPath:@"foregroundColor"];
        colorAnimation.duration = duration;
        colorAnimation.fillMode = kCAFillModeForwards;
        colorAnimation.removedOnCompletion = NO;
        colorAnimation.fromValue = (id)[UIColor darkGrayColor].CGColor;
        colorAnimation.toValue = (id)[UIColor whiteColor].CGColor;
        colorAnimation.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionLinear];
        [self.predictionTextLayer addAnimation:colorAnimation forKey:@"colorAnimation"];
    } else {
        self.predictionTextLayer.foregroundColor = [UIColor whiteColor].CGColor;
    }

    [self.predictionTextLayer removeFromSuperlayer];
    [[self.view layer] addSublayer: self.predictionTextLayer];
    [self.predictionTextLayer setString: text];
}

- (void) setupLearning {
    
    negativePredictionsCount = 0;
    
    trainer = NULL;
    predictor = NULL;
    predictionState = eWaiting;
    
    // Asynchronous nature of iCloud downloads means this fails!
    // I suspect we need to run on the main thread and wait...or use the downloadPredictorFile function that adds an observer on the copy...?
//    if ([self loadPredictorFileFromCloud: kcloudFilename]) {
//        
//        // Start predicting
//        predictionState = ePredicting;
//        self.lastFrameTime = [NSDate date];
//    }
//    else
//        NSLog(@"loadPredictorFileFromCloud failed");

    lastInfo = NULL;
    
    [self setupInfoDisplay];
    [self setupSound];
}

- (void) triggerNextState {
    switch (predictionState) {
        case eWaiting: {
            [self startPositiveLearning];
        } break;
            
        case ePositiveLearning: {
            [self startNegativeWaiting];
        } break;
            
        case eNegativeWaiting: {
            [self startNegativeLearning];
        } break;
            
        case eNegativeLearning: {
            [self startPredicting];
        } break;
            
        case ePredicting: {
            [self restartLearning];
        } break;
            
        default: {
            assert(FALSE); // Should never get here
        } break;
    }
}

- (void) startPositiveLearning {
    if (trainer != NULL) {
        jpcnn_destroy_trainer(trainer);
    }
    trainer = jpcnn_create_trainer();
    
    positivePredictionsCount = 0;
    predictionState = ePositiveLearning;
    
    [self updateInfoDisplay];
}

- (void) startNegativeWaiting {
    predictionState = eNegativeWaiting;
    [self updateInfoDisplay];
}

- (void) startNegativeLearning {
    negativePredictionsCount = 0;
    predictionState = eNegativeLearning;
    
    [self updateInfoDisplay];
}

- (void) startPredicting {
    if (predictor != NULL) {
        jpcnn_destroy_predictor(predictor);
    }
    predictor = jpcnn_create_predictor_from_trainer(trainer);

    [self savePredictorAlert];
    
    predictionState = ePredicting;
    
    [self updateInfoDisplay];
    
    self.lastFrameTime = [NSDate date];
}

- (void) restartLearning {
    [self startPositiveLearning];
}

- (void) savePredictorAlert {
    // Update the location
    [locationManager startUpdatingLocation];
    
    // Prompt for tag word...
    UIAlertView * tagAlertView =[[UIAlertView alloc ] initWithTitle:@"Predictor tag"
                                                            message:@"Enter tag word for the predictor filename"
                                                            delegate:self cancelButtonTitle:@"Done" otherButtonTitles: nil];
    tagAlertView.alertViewStyle = UIAlertViewStylePlainTextInput;
    UITextField *tagField = [tagAlertView textFieldAtIndex:0];
    tagField.placeholder = @"tag";
    [tagAlertView show];
    
    // ...and handle in the delegate below
}

- (void) alertView:(UIAlertView *)alertView clickedButtonAtIndex:(NSInteger)buttonIndex {
    // Done button pressed...
    if (buttonIndex == 0)
    {
        UITextField* tagField = [alertView textFieldAtIndex:0];
        tagField.keyboardType = UIKeyboardTypeASCIICapable;
        
        // TODO - strip out invalid characters for a filename from the tag?
        
        // Build the filename of the form: <tag>-<time>-<lat>-<long>.txt
        NSDate *time = [NSDate date];
        NSDateFormatter* df = [NSDateFormatter new];
        
        [df setDateFormat:@"dd-MM-yyyy-hh-mm-ss"];
        NSString *timeString = [df stringFromDate:time];
        NSString *fileName = [NSString stringWithFormat:@"%@-%@[%f][%f].%@",
                              tagField.text, timeString,
                              self.currentLocation.coordinate.latitude, self.currentLocation.coordinate.longitude,
                              PRED_FILE_EXTENSION];
        
        // And save it to iCloud
        [self savePredictorFileToCloud:predictor filename: fileName];
    }
}

#pragma mark - iCloud save & delete handlers

- (BOOL) savePredictorFileToCloud: (void *) predict filename: (NSString*) fileName {
    // If we're connected to the console, warn the user before re-routing stderr
    if (isatty(STDERR_FILENO)) {
        NSLog(@"Predictor output will be re-directed to file");
    }
    
    // get the local Documents directory path
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *documentsDirectory = [paths objectAtIndex:0];
    NSString *writableDBPath = [documentsDirectory stringByAppendingPathComponent:fileName];
    
    // redirect stderr (predictor's output) to this file
    int savedStdErr = dup(STDERR_FILENO);
    FILE *fp = freopen([writableDBPath cStringUsingEncoding:NSASCIIStringEncoding], "w", stderr);
    
    // output the predictor
    jpcnn_print_predictor(predict);

    // redirect stderr back to the original path
    fflush(stderr);
    dup2(savedStdErr, STDERR_FILENO);
    close(savedStdErr);
    
    // new local file created?
    if (fp != nil) {
        // if so, tidy up...
        fclose(fp);

        // ...delete any existing file on iCloud
        [self deleteCloudFile:fileName];
        
        // ...and move the new predictor file to iCloud
        __block BOOL success = NO;
        writableDBPath = [@"file:///" stringByAppendingString:writableDBPath];
        dispatch_async (dispatch_get_global_queue (DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^(void) {
            NSURL *sourceURL = [NSURL URLWithString:writableDBPath];
            NSFileManager *fileManager = [[[NSFileManager alloc] init] autorelease];
            NSURL *destURL = [[fileManager URLForUbiquityContainerIdentifier:nil]
                              URLByAppendingPathComponent:@"Documents" isDirectory:YES];
            destURL = [destURL URLByAppendingPathComponent:fileName];
            NSError *error = nil;
            success = [fileManager setUbiquitous:YES itemAtURL:sourceURL destinationURL:destURL error:&error];
            if (success) {
                NSLog(@"%@ moved from local to iCloud", destURL);
            } else {
                NSLog(@"%@ move from local to iCloud failed : error = %@", destURL, error);
            }
        });
        return success;
    } else {
        NSLog(@"Write failed : fp = %@", fp);
        return NO;
    }
}

- (void)deleteCloudFile:(NSString *)fileName {
    // Setup the path to delete from
    NSFileManager *fileManager = [[[NSFileManager alloc] init] autorelease];
    NSURL *deleteURL = [[fileManager URLForUbiquityContainerIdentifier:nil]
                        URLByAppendingPathComponent:@"Documents" isDirectory:YES];
    deleteURL = [deleteURL URLByAppendingPathComponent:fileName];
    
    // Wrap in file coordinator
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^(void) {
        NSFileCoordinator* fileCoordinator = [[NSFileCoordinator alloc] initWithFilePresenter:nil];
        [fileCoordinator coordinateWritingItemAtURL:deleteURL
                                            options:NSFileCoordinatorWritingForDeleting
                                              error:nil
                                         byAccessor:^(NSURL* writingURL) {
                                             // Simple delete to start
                                             [fileManager removeItemAtURL:deleteURL error:nil];
                                         }];
    });
}


#pragma mark - TODO : iCloud directory query handler

- (NSMetadataQuery *)documentQuery {
    NSMetadataQuery * query = [[NSMetadataQuery alloc] init];
    if (query) {
        
        // Search documents subdir only
        [query setSearchScopes:[NSArray arrayWithObject:NSMetadataQueryUbiquitousDocumentsScope]];
        
        // Add a predicate for finding the documents
        NSString * filePattern = [NSString stringWithFormat:@"*.%@", PRED_FILE_EXTENSION];
        [query setPredicate:[NSPredicate predicateWithFormat:@"%K LIKE %@",
                             NSMetadataItemFSNameKey, filePattern]];
        
    }
    return query;
}

- (void)stopQuery {
    if (_query) {
        NSLog(@"No longer watching iCloud dir...");
        
        [[NSNotificationCenter defaultCenter] removeObserver:self name:NSMetadataQueryDidFinishGatheringNotification object:nil];
        [[NSNotificationCenter defaultCenter] removeObserver:self name:NSMetadataQueryDidUpdateNotification object:nil];
        [_query stopQuery];
        _query = nil;
    }
}

- (void)startQuery {
    [self stopQuery];
    NSLog(@"Starting to watch iCloud dir...");
    _query = [self documentQuery];
    
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(processiCloudFiles:)
                                                 name:NSMetadataQueryDidFinishGatheringNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(processiCloudFiles:)
                                                 name:NSMetadataQueryDidUpdateNotification
                                               object:nil];
    [_query startQuery];
}

- (void)processiCloudFiles:(NSNotification *)notification {
    
    // Always disable updates while processing results
    [_query disableUpdates];
    
    [_iCloudURLs removeAllObjects];
    
    // The query reports all files found, every time.
    NSArray * queryResults = [_query results];
    for (NSMetadataItem * result in queryResults) {
        NSURL * fileURL = [result valueForAttribute:NSMetadataItemURLKey];
        NSNumber * aBool = nil;
        
        // Don't include hidden files
        [fileURL getResourceValue:&aBool forKey:NSURLIsHiddenKey error:nil];
        if (aBool && ![aBool boolValue]) {
            [_iCloudURLs addObject:fileURL];
        }
        
    }
    
    NSLog(@"Found %lu iCloud files.", (unsigned long)_iCloudURLs.count);
    _iCloudURLsReady = YES;
    
    [_query enableUpdates];
}


#pragma mark - TODO : iCloud read handlers

- (BOOL) loadPredictorFileFromCloud: (NSString*) fileName {
    // get the local Documents directory path
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *documentsDirectory = [paths objectAtIndex:0];
    NSString *writableDBPath = [documentsDirectory stringByAppendingPathComponent:fileName];
    
    //TODO : check that the iCloud-hosted file exists first...
    
    // ...if it does, move it to the local directory container
    __block BOOL wasMoved = NO;
    writableDBPath = [@"file:///" stringByAppendingString:writableDBPath];
    dispatch_async (dispatch_get_global_queue (DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^(void) {
        NSURL *destURL = [NSURL URLWithString:writableDBPath];
        NSFileManager *fileManager = [[[NSFileManager alloc] init] autorelease];
        NSURL *sourceURL = [[fileManager URLForUbiquityContainerIdentifier:nil]
                            URLByAppendingPathComponent:@"Documents" isDirectory:YES];
        sourceURL = [sourceURL URLByAppendingPathComponent:fileName];
        NSError *error = nil;
        BOOL success = [fileManager setUbiquitous:NO itemAtURL:sourceURL destinationURL:destURL error:&error];
        if (success) {
            NSLog(@"%@ moved from iCloud to local", destURL);
            
            // now load the predictor from the local file
            predictor = jpcnn_load_predictor([writableDBPath UTF8String]);
            assert(predictor != NULL);
            
        } else {
            NSLog(@"%@ move from iCloud to local failed : error = %@", destURL, error);
        }
        wasMoved = success;
    });
    return wasMoved;
}

- (void)downloadPredictorFileFromCloud:(NSURL *)url
{
    dispatch_queue_t q_default;
    q_default = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
    dispatch_async(q_default, ^{
        
        NSError *error = nil;
        BOOL success = [[NSFileManager defaultManager] startDownloadingUbiquitousItemAtURL:url error:&error];
        if (!success)
        {
            NSLog(@"Download to local for file: %@ : failed - error: %@", url, error);
        }
        else
        {
            NSDictionary *attrs = [url resourceValuesForKeys:@[NSURLUbiquitousItemDownloadingStatusKey] error:&error];
            if (attrs != nil)
            {
                if ([[attrs objectForKey:NSURLUbiquitousItemDownloadingStatusKey] boolValue])
                {
                    NSLog(@"Already downloaded file: %@", url);
                }
                else
                {
                    NSMetadataQuery *query = [[NSMetadataQuery alloc] init];
                    [query setPredicate:[NSPredicate predicateWithFormat:@"%K > 0", NSMetadataUbiquitousItemPercentDownloadedKey]];
                    [query setSearchScopes:@[url]]; // scope the search only on this item
                    
                    [query setValueListAttributes:@[NSMetadataUbiquitousItemPercentDownloadedKey, NSURLUbiquitousItemDownloadingStatusKey]];
                    
                    _fileDownloadMonitorQuery = query;
                    
                    [[NSNotificationCenter defaultCenter] addObserver:self
                                                             selector:@selector(liveUpdate:)
                                                                 name:NSMetadataQueryDidUpdateNotification
                                                               object:query];
                    
                    [self.fileDownloadMonitorQuery startQuery];
                }
            }
        }
    });
}

- (void)liveUpdate:(NSNotification *)notification
{
    NSMetadataQuery *query = [notification object];
    
    if (query != self.fileDownloadMonitorQuery)
        return; // it's not our query
    
    if ([self.fileDownloadMonitorQuery resultCount] == 0)
        return; // no items found
    
    NSMetadataItem *item = [self.fileDownloadMonitorQuery resultAtIndex:0];
    double progress = [[item valueForAttribute:NSMetadataUbiquitousItemPercentDownloadedKey] doubleValue];
    NSLog(@"Download progress = %f", progress);
    
    // report download progress somehow..
    
    if ([[item valueForAttribute:NSURLUbiquitousItemDownloadingStatusKey] boolValue])
    {
        // finished downloading, stop the query
        [query stopQuery];
        _fileDownloadMonitorQuery = nil;
    }
}


#pragma mark - Location Manager delegate

- (void)locationManager:(CLLocationManager *)manager didUpdateToLocation:(CLLocation *)newLocation fromLocation:(CLLocation *)oldLocation
{
    self.currentLocation = newLocation;
    [manager stopUpdatingLocation];
    
    NSLog(@"latitude: %f", self.currentLocation.coordinate.latitude);
    NSLog(@"longitude: %f", self.currentLocation.coordinate.longitude);
}


#pragma mark - DeepBelief predictor info display

- (void) setupInfoDisplay {
    NSString* const font = @"HelveticaNeue";
    const float fontSize = 20.0f;
    
    const float viewWidth = 320.0f;
    
    const float marginSizeX = 5.0f;
    const float marginSizeY = 5.0f;
    const float marginTopY = 7.0f;
    
    const float progressHeight = 20.0f;
    
    const float infoHeight = 120.0f;
    
    const CGRect progressBackgroundBounds = CGRectMake(marginSizeX, marginTopY, (viewWidth - (marginSizeX * 2)), progressHeight);
    
    self.progressBackground = [CATextLayer layer];
    [self.progressBackground setBackgroundColor: [UIColor blackColor].CGColor];
    [self.progressBackground setOpacity:0.5f];
    [self.progressBackground setFrame: progressBackgroundBounds];
    self.progressBackground.cornerRadius = 5.0f;
    
    [[self.view layer] addSublayer: self.progressBackground];
    
    const CGRect progressForegroundBounds = CGRectMake(marginSizeX, marginTopY, 0.0f, progressHeight);
    
    self.progressForeground = [CATextLayer layer];
    [self.progressForeground setBackgroundColor: [UIColor blueColor].CGColor];
    [self.progressForeground setOpacity:0.75f];
    [self.progressForeground setFrame: progressForegroundBounds];
    self.progressForeground.cornerRadius = 5.0f;
    
    [[self.view layer] addSublayer: self.progressForeground];
    
    // Show the OSD help prompts?
    if ([[NSUserDefaults standardUserDefaults] boolForKey:@"useOSDHelp"]) {

        const CGRect infoBackgroundBounds = CGRectMake(marginSizeX, (marginSizeY + progressHeight + marginSizeY), (viewWidth - (marginSizeX * 2)), infoHeight);
        
        self.infoBackground = [CATextLayer layer];
        [self.infoBackground setBackgroundColor: [UIColor blackColor].CGColor];
        [self.infoBackground setOpacity:0.5f];
        [self.infoBackground setFrame: infoBackgroundBounds];
        self.infoBackground.cornerRadius = 5.0f;
        
        [[self.view layer] addSublayer: self.infoBackground];
        
        const CGRect infoForegroundBounds = CGRectInset(infoBackgroundBounds, 5.0f, 5.0f);
        
        self.infoForeground = [CATextLayer layer];
        [self.infoForeground setBackgroundColor: [UIColor clearColor].CGColor];
        [self.infoForeground setForegroundColor: [UIColor whiteColor].CGColor];
        [self.infoForeground setOpacity:1.0f];
        [self.infoForeground setFrame: infoForegroundBounds];
        [self.infoForeground setWrapped: YES];
        [self.infoForeground setFont: font];
        [self.infoForeground setFontSize: fontSize];
        self.infoForeground.contentsScale = [[UIScreen mainScreen] scale];
        
        [self.infoForeground setString: @""];
        
        [[self.view layer] addSublayer: self.infoForeground];
   }
}

- (void) updateInfoDisplay {
    
    switch (predictionState) {
        case eWaiting: {
            [self setInfo: @"When you're ready to teach me, press the button at the bottom and point your phone at the thing you want to recognize"];
            [self setProgress: 0.0f];
        } break;
            
        case ePositiveLearning: {
            [self setInfo: @"Move around the thing you want to recognize, keeping the phone pointed at it, to capture different angles"];
            [self setProgress: (positivePredictionsCount / (float)kPositivePredictionTotal)];
        } break;
            
        case eNegativeWaiting: {
            [self setInfo: @"Now I need to see examples of things that aren't the object you're looking for. Press the button when you're ready"];
            [self setProgress: 0.0f];
            [self.mainButton setTitle: @"Continue Learning" forState:UIControlStateNormal];
        } break;
            
        case eNegativeLearning: {
            [self setInfo: @"Now move around the room pointing your phone at lots of things that are not the object you want to recognize"];
            [self setProgress: (negativePredictionsCount / (float)kNegativePredictionTotal)];
        } break;
            
        case ePredicting: {
            [self setInfo: @"You've taught the neural network to see! Now you should be able to scan around using the camera and detect the object's presence"];
            [self.mainButton setTitle: @"Learn Again" forState:UIControlStateNormal];
        } break;
            
        default: {
            assert(FALSE); // Should never get here
        } break;
    }
    
}

- (void) setInfo: (NSString*) info {
    if (![info isEqualToString: lastInfo]) {
        [self.infoForeground setString: info];
        
        if ([[NSUserDefaults standardUserDefaults] boolForKey:@"useSpeech"])
            [self speak: info];
        
        lastInfo = info;
    }
}

- (void) setProgress: (float) amount {
    const CGRect progressBackgroundBounds = [self.progressBackground frame];
    
    const float fullWidth = progressBackgroundBounds.size.width;
    const float foregroundWidth = (fullWidth * amount);
    
    CGRect progressForegroundBounds = [self.progressForeground frame];
    progressForegroundBounds.size.width = foregroundWidth;
    [self.progressForeground setFrame: progressForegroundBounds];
}

#pragma mark - DeepBelief network prediction handler

- (void) handleNetworkPredictions: (float*) predictions withLength: (int) predictionsLength {
    switch (predictionState) {
        case eWaiting: {
            // Do nothing
        } break;
            
        case ePositiveLearning: {
            jpcnn_train(trainer, 1.0f, predictions, predictionsLength);
            positivePredictionsCount += 1;
            if (positivePredictionsCount >= kPositivePredictionTotal) {
                [self triggerNextState];
            }
        } break;
            
        case eNegativeWaiting: {
            // Do nothing
        } break;
            
        case eNegativeLearning: {
            jpcnn_train(trainer, 0.0f, predictions, predictionsLength);
            negativePredictionsCount += 1;
            if (negativePredictionsCount >= kNegativePredictionTotal) {
                [self triggerNextState];
            }
        } break;
            
        case ePredicting: {
            const float predictionValue = jpcnn_predict(predictor, predictions, predictionsLength);
            [self setProgress: predictionValue];
            const float frameDuration = - [self.lastFrameTime timeIntervalSinceNow];
            self.lastFrameTime = [NSDate date];
            const float pingProgress = (predictionValue * frameDuration);
            timeToNextPing -= pingProgress;
            if (timeToNextPing < 0.0f) {
                AudioServicesPlaySystemSound(self.soundFileObject);
                timeToNextPing = kMinSecondsBetweenPings;
            }
        } break;
            
        default: {
            assert(FALSE); // Should never get here
        } break;
    }
    
    [self updateInfoDisplay];
}

#pragma mark - Sound and speech helpers

- (void) setupSound {
    // Create the URL for the source audio file. The URLForResource:withExtension: method is
    //    new in iOS 4.0.
    NSURL *soundUrl   = [[NSBundle mainBundle] URLForResource: @"32093__jbum__jsyd-ping"
                                                withExtension: @"wav"];
    self.soundFileURLRef = (CFURLRef) [soundUrl retain];
    
    // Create a system sound object representing the sound file.
    AudioServicesCreateSystemSoundID (
                                      self.soundFileURLRef,
                                      &_soundFileObject
                                      );
}

- (void) speak: (NSString*) words
{
    if ([synth isSpeaking]) {
        return;
    }
    AVSpeechUtterance *utterance = [AVSpeechUtterance speechUtteranceWithString: words];
    utterance.voice = [AVSpeechSynthesisVoice voiceWithLanguage:@"en-US"];
    utterance.rate = 0.50 * AVSpeechUtteranceDefaultSpeechRate;
    [synth speakUtterance:utterance];
}


@end
