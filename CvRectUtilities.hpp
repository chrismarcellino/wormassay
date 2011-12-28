//
//  CvRectUtilities.hpp
//  TextAssist
//
//  Created by Chris Marcellino on 1/24/11.
//  Copyright 2011 Chris Marcellino. All rights reserved.
//

#import "opencv2/opencv.hpp"

static inline int rectArea(const CvRect& rect)
{
    return rect.width * rect.height;
}

static inline int rectPerimeter(const CvRect& rect)
{
    return (rect.width + rect.height) * 2;
}

static inline bool rectContainsPoint(const CvRect& rect, int x, int y)
{
    return rect.x <= x && x < rect.x + rect.width && rect.y <= y && y < rect.y + rect.height;
}

static inline bool rectContainsRect(const CvRect& parent, const CvRect &child)        // contains or equals, but not associative
{
    return rectContainsPoint(parent, child.x, child.y) && 
        rectContainsPoint(parent, child.x + child.width - 1, child.y + child.height - 1);
}

static inline bool rectIntersectsRect(const CvRect& rect1, const CvRect& rect2)
{
    return rect1.x <= rect2.x + rect2.width &&
        rect1.x + rect1.width >= rect2.x &&
        rect1.y <= rect2.y + rect2.height &&
        rect1.y + rect1.height >= rect2.y;
}

static inline CvRect rectUnion(const CvRect& rect1, const CvRect& rect2)    // similar to cvMaxRect
{
    CvRect unionRect;
    unionRect.x = MIN(rect1.x, rect2.x);
    unionRect.y = MIN(rect1.y, rect2.y);
    unionRect.width = MAX(rect1.x + rect1.width, rect2.x + rect2.width) - unionRect.x;
    unionRect.height = MAX(rect1.y + rect1.height, rect2.y + rect2.height) - unionRect.y;
    return unionRect;
}

static inline CvRect outsetRect(CvRect rect, int dx, int dy)
{
    rect.x -= dx;
    rect.y -= dy;
    rect.width += dx * 2;
    rect.height += dy * 2;
    return rect;
}

static inline void fastSetImageZero(IplImage *image)
{
    assert(image->nChannels != 4);
    memset(image->imageData, 0, image->imageSize);
}

static inline void fastFillImage(IplImage *image, uint8_t val)
{
    memset(image->imageData, val, image->imageSize);
}
