//
//  ProcessingController.m
//  NematodeAssay
//
//  Created by Chris Marcellino on 4/5/11.
//  Copyright 2011 Regents of the University of California. All rights reserved.
//

#import "ProcessingController.h"
#import "ImageProcessing.hpp"


@implementation ProcessingController

+ (ProcessingController *)sharedInstance
{
    static dispatch_once_t pred = 0;
    static ProcessingController *sharedInstance = nil;
    dispatch_once(&pred, ^{
        sharedInstance = [[self alloc] init];
    });
    return sharedInstance;
}

- (id)init
{
    if ((self = [super init])) {
        _queue = dispatch_queue_create("ProcessingController queue", NULL);
        _debugFrameCallbackQueue = dispatch_queue_create("Debug frame callback queue", NULL);
    }
    return self;
}

- (void)dealloc
{
    dispatch_release(_queue);
    dispatch_release(_debugFrameCallbackQueue);
    [super dealloc];
}

// Caller is responsible for calling cvReleaseImage() on debugFrame. Block will be called on an arbitrary thread. 
- (void)processVideoFrame:(IplImage *)videoFrame
     fromSourceIdentifier:(NSString *)sourceIdentifier
debugVideoFrameCompletionTakingOwnership:(void (^)(IplImage *debugFrame))callback
{
    // XXX TESTING
    
    std::vector<cv::Vec3f> wellCircles;
    int wellCount;
    bool success = findWellCircles(videoFrame, wellCount, wellCircles);        // gets wells in row major order
    
    // FONT
    CvFont font;
    double hScale=1.0;
    double vScale=1.0;
    int    lineWidth=1;
    cvInitFont(&font,CV_FONT_HERSHEY_SIMPLEX, hScale,vScale,0,lineWidth);        // XXX CLEANUP
    
    
    // Once we're done with the frame, draw debugging stuff on a copy and send it back
    IplImage *debugImage = cvCloneImage(videoFrame);
    for (size_t i = 0; i < wellCircles.size(); i++) {
        CvPoint center = cvPoint(cvRound(wellCircles[i][0]), cvRound(wellCircles[i][1]));
        int radius = cvRound(wellCircles[i][2]);
        // Draw the circle center
  //      cvCircle(debugImage, center, 3, CV_RGB(0, 255, i * 10), -1, 8, 0);
        // Draw the circle outline
        cvCircle(debugImage, center, radius, success ? CV_RGB(0, 0, 255) : CV_RGB(255, 255, 0), 3, 8, 0);

        // Draw text in the circle
        if (success) {
        cvPutText (debugImage, [[NSString stringWithFormat:@"%i", i] UTF8String], center, &font, cvScalar(255,255,0));
        }

    }
    
    dispatch_async(_debugFrameCallbackQueue, ^{
        callback(debugImage);
    });
}

- (void)logFormat:(NSString *)format, ...
{
    // XXX: todo, write documents folder appropriately, and show on screen in a window.
    // for now, syslog.  (remember to add locking)
    va_list args;
    va_start(args, format);
    NSLogv(format, args);
    va_end(args);
}

@end
