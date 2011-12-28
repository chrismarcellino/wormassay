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
    NSUInteger _numberOfVotingFrames;
    NSUInteger _quorum;
    
    NSMutableArray *_lastFrames;
    NSMutableArray *_deltaThresholded;
    IplImage* _insetInvertedCircleMask;
    IplImage* _circleMask;
}

@property NSUInteger numberOfVotingFrames;
@property NSUInteger quorum;

@end
