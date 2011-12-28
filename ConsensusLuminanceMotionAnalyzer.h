//
//  ConsensusLuminanceMotionAnalyzer.h
//  WormAssay
//
//  Created by Chris Marcellino on 4/19/11.
//  Copyright 2011 Chris Marcellino. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "AssayAnalyzer.h"

@interface ConsensusLuminanceMotionAnalyzer : NSObject <AssayAnalyzer> {
    NSMutableArray *_lastFrames;
    IplImage* _pixelwiseVotes;
}

@property NSUInteger numberOfVotingFrames;
@property NSUInteger quorum;
@property NSTimeInterval evaluateFramesAmongLastSeconds;
@property NSUInteger deltaThresholdCutoff;

@end
