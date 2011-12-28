//
//  CvNot.h
//  TextAssist
//
//  Created by Chris Marcellino on 1/4/11.
//  Copyright 2011 Chris Marcellino. All rights reserved.
//

#import <Quartz/Quartz.h>


@interface CvNot : QCPlugIn

@property(assign) id<QCPlugInInputImageSource> inputImage;
@property(assign) id<QCPlugInOutputImageProvider> outputImage;

@end
