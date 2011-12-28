//
//  ConsensusLuminanceMotionAnalyzer.h
//  WormAssay
//
//  Created by Chris Marcellino on 4/19/11.
//  Copyright 2011 Chris Marcellino. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "AssayAnalyzer.h"

#define FRAME_MAX_SAMPLE_SIZE 4

@interface ConsensusLuminanceMotionAnalyzer : NSObject <AssayAnalyzer> {
    NSMutableArray *_lastFrames;
    IplImage* _insetInvertedCircleMask;
    IplImage* _invertedCircleMask;
    IplImage* _deltaThresholded[FRAME_MAX_SAMPLE_SIZE];
    
    BOOL _hadEnoughFramesAtLeastOnce;
}

@end
