//
//  CvSmooth.h
//  TextAssist
//
//  Created by Chris Marcellino on 1/4/11.
//  Copyright 2011 Chris Marcellino. All rights reserved.
//

#import <Quartz/Quartz.h>


@interface CvSmooth : QCPlugIn

@property(assign) id<QCPlugInInputImageSource> inputImage;
@property NSUInteger inputRadius;
@property(assign) id<QCPlugInOutputImageProvider> outputImage;

@end
