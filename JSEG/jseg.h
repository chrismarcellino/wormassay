//
//  jseg.h
//  NematodeAssay
//
//  Created by Chris Marcellino on 4/10/11.
//  Copyright 2011 Regents of the University of California. All rights reserved.
//

#import "opencv2/core/core_c.h"

#ifdef __cplusplus
extern "C" {
#endif

// Performs segmentation using JSEG: "Unsupervised segmentation of color-texture regions in images and video,"
// IEEE Transactions on Pattern Analysis and Machine Intelligence (PAMI '01), August 2001.
//
// The region map file is a gray-scale image. It labels the image pixels. If pixel (0,0) belongs to region 1, its value is 1.
// The label starts at 1 and ends at the total number of regions. Your probably will only see black when you try to view the
// map image. That's because most values are too small. If you equalize the image, you'll see patches of regions. The
// equalization changes the original pixel values though.
// The region map is very useful for many applications, for example, if you want to process all the pixels in a particular
// region of interest. On the other hand, if you want to get the region boundaries, you need to do a little job by yourself.
// For example, you can check if each pixel is of same label as its neighboring pixels. If no, it indicates that pixel is
// at the boundary.
// Program limitation: The total number of regions in the image must be less than 256 before the region merging process.
// This works for most images smaller than 512x512. Minimum image size is 64x64.
//
// Optional Parameters
// Color quantization threshold: specify values 0-600, leave blank for automatic determination. The higher the value, the
// less number of quantized colors in the image. For color images, try 250. If you are unsatisfied with the result because
// two neighboring regions with similar colors are not getting separated, try a smaller value, say 150.
// Number of scales: the algorithm automatically determines the starting scale based on the image size and reduces the scale
// to refine the segmentation results. If you want to segment a small object in a large-sized image, use more number of scales.
// If you want to have a coarse segmentation, use 1 scale only.
// Region merge threshold: specify values 0.0-0.7, omit for default value of 0.4. If there are two neighboring regions having
// identical color, try smaller values to avoid the merging.
IplImage *createJSEGRegionMapFromImage(IplImage *image,
                                       int colorQuantizationThreshold = -1,
                                       int numberOfScales = -1,
                                       float regionMergeThreshold = 0.4);

// Converts the region map into a binary edge mask (edges are 255).
IplImage *createSegmentEdgeMaskImageForRegionMap(IplImage *regionMap);

#ifdef __cplusplus
}
#endif