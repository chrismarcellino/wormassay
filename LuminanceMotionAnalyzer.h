//
//  LuminanceMotionAnalyzer.h
//  WormAssay
//
//  Created by Chris Marcellino on 4/19/11.
//  Copyright 2011 Chris Marcellino. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "AssayAnalyzer.h"

@interface LuminanceMotionAnalyzer : NSObject <AssayAnalyzer> {
    VideoFrame *_lastFrame;
    IplImage* _insetInvertedCircleMask;
    IplImage* _invertedCircleMask;
    IplImage* _deltaThresholded;
}

@end
