//
//  ImageProcessing.h
//  NematodeAssay
//
//  Created by Chris Marcellino on 4/4/11.
//  Copyright 2011 Regents of the University of California. All rights reserved.
//

#import "opencv2/core/core_c.h"

#ifdef __cplusplus
extern "C" {
#endif
    
extern std::vector<cv::Vec3f> findWellCircles(IplImage *inputImage, int numberOfWellsInPlate);
    
#ifdef __cplusplus
}
#endif
