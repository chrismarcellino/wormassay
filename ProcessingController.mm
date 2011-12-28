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
    
    std::vector<cv::Vec3f> circles = findWellCircles(videoFrame, 24);
    
    // Once we're done with the frame, draw debugging stuff on a copy and send it back
    IplImage *debugImage = cvCloneImage(videoFrame);
    for (size_t i = 0; i < circles.size(); i++) {
        CvPoint center = cvPoint(cvRound(circles[i][0]), cvRound(circles[i][1]));
        int radius = cvRound(circles[i][2]);
        // draw the circle center
        cvCircle(debugImage, center, 3, CV_RGB(0, 255, 0), -1, 8, 0);
        // draw the circle outline
        cvCircle(debugImage, center, radius, CV_RGB(0, 0, 255), 3, 8, 0);
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
