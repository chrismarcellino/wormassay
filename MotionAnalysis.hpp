//
//  MotionAnalysis.hpp
//  WormAssay
//
//  Created by Chris Marcellino on 4/4/11.
//  Copyright 2011 Regents of the University of California. All rights reserved.
//

#import "opencv2/core/core_c.h"
#import "WellFinding.hpp"

#ifdef __cplusplus
extern "C" {
#endif

// Counts the proportion of pixels that represent moved well contents between two frames. An empty vector is returned if the plate
// (or camera) has physically moved between the prev and cur images. 
extern std::vector<double> calculateMovedWellFractionForWellsFromImages(IplImage* plateImagePrev,
                                                                                 IplImage* plateImageCur,
                                                                                 const std::vector<Circle> &circles,
                                                                                 IplImage* debugImage);

// Calculates the proportion of edge pixels in the image using the Canny edge detector. This can be used to determine well occupancy. 
extern std::vector<double> calculateCannyEdgePixelProportionForWellsFromImages(IplImage* plateImage, const std::vector<Circle> &circles, IplImage* debugImage);

#ifdef __cplusplus
}
#endif
