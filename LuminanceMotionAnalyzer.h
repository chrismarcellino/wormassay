//
//  LuminanceMotionAnalyzer.h
//  WormAssay
//
//  Created by Chris Marcellino on 4/19/11.
//  Copyright 2011 Chris Marcellino. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "AssayAnalzyer.h"

@interface LuminanceMotionAnalyzer : NSObject <AssayAnalzyer> {
    VideoFrame *_lastFrame;
    IplImage* _insetInvertedCircleMask;
    IplImage* _invertedCircleMask;
}

@end
