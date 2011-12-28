//
//  CvChannelSplitterQcPlugin.h
//  TextAssist
//
//  Created by Chris Marcellino on 1/4/11.
//  Copyright 2011 Chris Marcellino. All rights reserved.
//

#import <Quartz/Quartz.h>


@interface CvChannelSplitterQcPlugin : QCPlugIn

@property(assign) id<QCPlugInInputImageSource> inputImage;
@property(assign) id<QCPlugInOutputImageProvider> outputImageR;
@property(assign) id<QCPlugInOutputImageProvider> outputImageG;
@property(assign) id<QCPlugInOutputImageProvider> outputImageB;
@property(assign) id<QCPlugInOutputImageProvider> outputImageA;

@end
