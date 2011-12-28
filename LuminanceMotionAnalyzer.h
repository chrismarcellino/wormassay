//
//  LuminanceMotionAnalyzer.h
//  WormAssay
//
//  Created by Chris Marcellino on 4/19/11.
//  Copyright 2011 Chris Marcellino. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "WellAnalyzer.h"

@interface LuminanceMotionAnalyzer : NSObject <WellAnalyzer> {
    VideoFrame *_lastFrame;
    IplImage* _insetInvertedCircleMask;
    IplImage* _invertedCircleMask;
}

@end
