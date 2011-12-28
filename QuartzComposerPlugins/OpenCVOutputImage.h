//
//  OpenCVOutputImage.h
//  TextAssist
//
//  Created by Chris Marcellino on 1/4/11.
//  Copyright 2011 Chris Marcellino. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <Quartz/Quartz.h>
#import <ApplicationServices/ApplicationServices.h>
#import "opencv2/opencv.hpp"


@interface OpenCVOutputImage : NSObject <QCPlugInOutputImageProvider> {
    IplImage *iplImage;
}

+ (OpenCVOutputImage *)outputImageWithIplImageAssumingOwnership:(IplImage *)image;
- (id)initWithIplImageAssumingOwnership:(IplImage *)image;

@end
