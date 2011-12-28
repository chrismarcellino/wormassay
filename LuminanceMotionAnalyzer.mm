//
//  LuminanceMotionAnalyzer.mm
//  WormAssay
//
//  Created by Chris Marcellino on 4/19/11.
//  Copyright 2011 Chris Marcellino. All rights reserved.
//

#import "LuminanceMotionAnalyzer.h"

@implementation LuminanceMotionAnalyzer

+ (NSString *)analyzerName
{
    return NSLocalizedString(@"Last Frame Luminance Difference", nil);
}

- (id)init
{
    if ((self = [super init])) {
        [self setNumberOfVotingFrames:1];
        [self setQuorum:1];
        [self setEvaluateFramesAmongLastSeconds:0.0];
        [self setDeltaThresholdCutoff:15];
    }
    return self;
}

@end
