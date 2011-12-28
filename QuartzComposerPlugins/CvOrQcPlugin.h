//
//  CvOrQcPlugin.h
//  TextAssist
//
//  Created by Chris Marcellino on 1/4/11.
//  Copyright 2011 Chris Marcellino. All rights reserved.
//

#import <Quartz/Quartz.h>


@interface CvOrQcPlugin : QCPlugIn

@property(assign) id<QCPlugInInputImageSource> inputImageA;
@property(assign) id<QCPlugInInputImageSource> inputImageB;
@property(assign) id<QCPlugInOutputImageProvider> outputImage;

@end
