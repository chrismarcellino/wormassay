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

extern std::vector<int> knownPlateWellCounts();

// Returns true if wellCount corresponds to a known plate configuration, and in that case returns the well arrangment values.
// Microplates have more columns than rows, by convention. 
extern bool getPlateConfigurationForWellCount(int wellCount, int &rows, int &columns);

// Returns true if the circles found correspond to the intended plate configuration. Well circles are returned in 
// row major order, as (x-center, y-center, radius) triples. The first version determines the well count automatically. 
extern bool findWellCircles(IplImage *inputImage, int &wellCount, std::vector<cv::Vec3f> &circles,  int wellCountHint = 0);
extern bool findWellCirclesForPlateCount(IplImage *inputImage, int wellCount, std::vector<cv::Vec3f> &circlesVec, float &score);
    
#ifdef __cplusplus
}
#endif
