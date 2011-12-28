//
//  CvCannyQcPlugin.h
//  TextAssist
//
//  Created by Chris Marcellino on 1/4/11.
//  Copyright 2011 Chris Marcellino. All rights reserved.
//

#import <Quartz/Quartz.h>


@interface CvCannyQcPlugin : QCPlugIn

@property(assign) id<QCPlugInInputImageSource> inputImage;
@property(assign) id<QCPlugInOutputImageProvider> outputImage;
@property double inputLowThreshold;
@property double inputHighThreshold;
@property BOOL inputLevel2Gradient;
@property NSUInteger inputApertureSizeIndex;

@end
