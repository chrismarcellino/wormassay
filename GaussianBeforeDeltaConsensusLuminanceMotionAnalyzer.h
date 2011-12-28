//
//  FrameGaussianConsensusLuminanceMotionAnalyzer.h
//  WormAssay
//
//  Created by Chris Marcellino on 4/19/11.
//  Copyright 2011 Chris Marcellino. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "AssayAnalyzer.h"

@interface GaussianBeforeDeltaConsensusLuminanceMotionAnalyzer : NSObject <AssayAnalyzer> {
    NSMutableArray *_lastGaussianFrames;
    NSMutableArray *_deltaThresholded;
    IplImage* _insetInvertedCircleMask;
    IplImage* _circleMask;
}

@property NSUInteger numberOfVotingFrames;
@property NSUInteger quorum;

@end
