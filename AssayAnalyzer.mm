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
    return 2.0;
}
