/*M///////////////////////////////////////////////////////////////////////////////////////
//
//  IMPORTANT: READ BEFORE DOWNLOADING, COPYING, INSTALLING OR USING.
//
//  By downloading, copying, installing or using the software you agree to this license.
//  If you do not agree to this license, do not download, install,
//  copy or use the software.
//
//
//                           License Agreement
//                For Open Source Computer Vision Library
//
// Copyright (C) 2010-2012, Institute Of Software Chinese Academy Of Science, all rights reserved.
// Copyright (C) 2010-2012, Advanced Micro Devices, Inc., all rights reserved.
// Third party copyrights are property of their respective owners.
//
// @Authors
//   Long Guoping , longguoping@gmail.com
//
// Redistribution and use in source and binary forms, with or without modification,
// are permitted provided that the following conditions are met:
//
//   * Redistribution's of source code must retain the above copyright notice,
//     this list of conditions and the following disclaimer.
//
//   * Redistribution's in binary form must reproduce the above copyright notice,
//     this list of conditions and the following disclaimer in the documentation
//     and/or other GpuMaterials provided with the distribution.
//
//   * The name of the copyright holders may not be used to endorse or promote products
//     derived from this software without specific prior written permission.
//
// This software is provided by the copyright holders and contributors "as is" and
// any express or implied warranties, including, but not limited to, the implied
// warranties of merchantability and fitness for a particular purpose are disclaimed.
// In no event shall the Intel Corporation or contributors be liable for any direct,
// indirect, incidental, special, exemplary, or consequential damages
// (including, but not limited to, procurement of substitute goods or services;
// loss of use, data, or profits; or business interruption) however caused
// and on any theory of liability, whether in contract, strict liability,
// or tort (including negligence or otherwise) arising in any way out of
// the use of this software, even if advised of the possibility of such damage.
//
//M*/

#ifndef __OPENCV_OPENCL_SAFE_CALL_HPP__
#define __OPENCV_OPENCL_SAFE_CALL_HPP__

#if defined __APPLE__
#include <OpenCL/opencl.h>
#else
#include <CL/cl.h>
#endif

#if defined(__GNUC__)
#define openCLSafeCall(expr)  ___openCLSafeCall(expr, __FILE__, __LINE__, __func__)
#define openCLVerifyCall(res) ___openCLSafeCall(res, __FILE__, __LINE__, __func__)
#else /* defined(__OPENCLCC__) || defined(__MSVC__) */
#define openCLSafeCall(expr)  ___openCLSafeCall(expr, __FILE__, __LINE__)
#define openCLVerifyCall(res) ___openCLSafeCall(res, __FILE__, __LINE__)
#endif


namespace cv
{
    namespace ocl
    {
        void error( const char *error_string, const char *file, const int line, const char *func = "");
        const char *getOpenCLErrorString( int err );

        static inline void ___openCLSafeCall(int err, const char *file, const int line, const char *func = "")
        {
            if( CL_SUCCESS != err)
                cv::ocl::error(getOpenCLErrorString(err), file, line, func);
        }
    }
}

#endif /* __OPENCV_OPENCL_SAFE_CALL_HPP__ */
