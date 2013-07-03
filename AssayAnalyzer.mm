//
//  AssayAnalyzer.m
//  WormAssay
//
//  Created by Chris Marcellino on 4/19/11.
//  Copyright 2011 Chris Marcellino. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "opencv2/core/core_c.h"
#import "VideoProcessorController.h"        // for run log


NSTimeInterval IgnoreFramesPostMovementTimeInterval()
{
    static dispatch_once_t pred;
    static NSTimeInterval val;
    dispatch_once(&pred, ^{
        val = [[NSUserDefaults standardUserDefaults] doubleForKey:@"IgnoreFramesPostMovementTimeInterval"];
        if (val) {
            RunLog(@"*** NOTE ***: IgnoreFramesPostMovementTimeInterval user default set to %g", val);
        } else {
            val = 5.0;
        }
    });
    
    return val;
}
