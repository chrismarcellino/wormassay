//
//  NullMotionAnalyzer.mm
//  WormAssay
//
//  Created by Chris Marcellino on 5/12/11.
//  Copyright 2011 Chris Marcellino. All rights reserved.
//

#import "NullMotionAnalyzer.h"
#import "VideoFrame.h"
#import "CvUtilities.hpp"

@implementation NullMotionAnalyzer

+ (NSString *)analyzerName
{
    return NSLocalizedString(@"(none)", nil);
}

- (BOOL)canProcessInParallel
{
    return YES;
}

- (void)willBeginPlateTrackingWithPlateData:(PlateData *)plateData
{
}

- (BOOL)willBeginFrameProcessing:(VideoFrame *)videoFrame debugImage:(IplImage*)debugImage plateData:(PlateData *)plateData
{
    // Draw the movement text
    CvFont wellFont = fontForNormalizedScale(3.5, debugImage);
    cvPutText(debugImage,
              "ANALYSIS DISABLED",
              cvPoint(debugImage->width * 0.2, debugImage->height * 0.55),
              &wellFont,
              CV_RGBA(0, 0, 255, 255));
    return NO;
}

- (void)processVideoFrameWellSynchronously:(IplImage*)wellImage
                                   forWell:(int)well
                                debugImage:(IplImage*)debugImage
                          presentationTime:(NSTimeInterval)presentationTime
                                 plateData:(PlateData *)plateData
{
    // nothing
}

- (void)didEndFrameProcessing:(VideoFrame *)videoFrame plateData:(PlateData *)plateData
{
    // nothing
}

- (void)didEndTrackingPlateWithPlateData:(PlateData *)plateData
{
    // nothing
}

- (NSTimeInterval)minimumTimeIntervalProcessedToReportData
{
    return FLT_MAX;
}

- (NSUInteger)minimumSamplesProcessedToReportData
{
    return NSIntegerMax;
}

@end
