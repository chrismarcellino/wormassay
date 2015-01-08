//
//  OpticalFlowMotionAnalyzer.h
//  WormAssay
//
//  Created by Chris Marcellino on 5/12/11.
//  Copyright 2011 Chris Marcellino. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "AssayAnalyzer.h"

@class VideoFrame;

@interface OpticalFlowMotionAnalyzer : NSObject <AssayAnalyzer> {
    NSMutableArray *_lastFrames;
    VideoFrame *_prevFrame;
    NSTimeInterval _lastMovementThresholdPresentationTime;
}

@end
