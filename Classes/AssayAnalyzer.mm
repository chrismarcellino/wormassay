//
//  AssayAnalyzer.m
//  WormAssay
//
//  Created by Chris Marcellino on 4/19/11.
//  Copyright 2011 Chris Marcellino. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <opencv2/core/core_c.h>
#import "VideoProcessorController.h"        // for run log

static NSString *const IgnoreFramesPostMovementTimeIntervalKey = @"IgnoreFramesPostMovementTimeInterval";

NSTimeInterval IgnoreFramesPostMovementTimeInterval()
{
    static dispatch_once_t pred;
    static NSTimeInterval val;
    dispatch_once(&pred, ^{
        val = [[NSUserDefaults standardUserDefaults] doubleForKey:IgnoreFramesPostMovementTimeIntervalKey];
        if (val) {
            RunLog(@"Using custom frame hysteresis threshold of %g seconds set via IgnoreFramesPostMovementTimeInterval user default,", val);
        } else {
            val = 2.0;
        }
    });
    
    return val;
}
