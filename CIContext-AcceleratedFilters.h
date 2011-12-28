//
//  CIContext-AcceleratedFilters.h
//  WormAssay
//
//  Created by Chris Marcellino on 4/23/11.
//  Copyright 2011 Chris Marcellino. All rights reserved.
//

#import "opencv2/core/core_c.h"
#import <QuartzCore/QuartzCore.h>

@interface CIContext (AcceleratedFilters)

+ (CIContext *)contextForAcceleratedBitmapImageFiltering;

- (IplImage*)createOutputImageFromIplImage:(IplImage*)image usingCIFilterWithName:(NSString *)filterName, ...;
- (IplImage*)createGaussianImageFromImage:(IplImage*)inputImage withStdDev:(double)stddev;

@end
