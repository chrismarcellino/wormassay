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
// Copyright (C) 2010-2012, MulticoreWare Inc., all rights reserved.
// Copyright (C) 2010-2012, Advanced Micro Devices, Inc., all rights reserved.
// Third party copyrights are property of their respective owners.
//
// @Authors
//    Liu Liujun, liujun@multicorewareinc.com
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
// This software is provided by the copyright holders and contributors as is and
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
__kernel void BlendLinear_C1_D0(
    __global uchar4 *dst,
    __global uchar4 *img1,
    __global uchar4 *img2,
    __global float4 *weight1,
    __global float4 *weight2,
    int rows,
    int cols,
    int istep,
    int wstep
    )
{
    int idx = get_global_id(0);
    int idy = get_global_id(1);
    if (idx << 2 < cols && idy < rows)
    {
        int pos = mad24(idy,istep >> 2,idx);
        int wpos = mad24(idy,wstep >> 2,idx);
        float4 w1 = weight1[wpos], w2 = weight2[wpos];
        dst[pos] = convert_uchar4((convert_float4(img1[pos]) * w1 +
            convert_float4(img2[pos]) * w2) / (w1 + w2 + 1e-5f));
    }
}

__kernel void BlendLinear_C4_D0(
    __global uchar4 *dst,
    __global uchar4 *img1,
    __global uchar4 *img2,
    __global float *weight1,
    __global float *weight2,
    int rows,
    int cols,
    int istep,
    int wstep
    )
{
    int idx = get_global_id(0);
    int idy = get_global_id(1);
    if (idx < cols && idy < rows)
    {
        int pos = mad24(idy,istep >> 2,idx);
        int wpos = mad24(idy,wstep, idx);
        float w1 = weight1[wpos];
        float w2 = weight2[wpos];
        dst[pos] = convert_uchar4((convert_float4(img1[pos]) * w1 +
            convert_float4(img2[pos]) * w2) / (w1 + w2 + 1e-5f));
    }
}


__kernel void BlendLinear_C1_D5(
    __global float4 *dst,
    __global float4 *img1,
    __global float4 *img2,
    __global float4 *weight1,
    __global float4 *weight2,
    int rows,
    int cols,
    int istep,
    int wstep
    )
{
    int idx = get_global_id(0);
    int idy = get_global_id(1);
    if (idx << 2 < cols && idy < rows)
    {
        int pos = mad24(idy,istep >> 2,idx);
        int wpos = mad24(idy,wstep >> 2,idx);
        float4 w1 = weight1[wpos], w2 = weight2[wpos];
        dst[pos] = (img1[pos] * w1 + img2[pos] * w2) / (w1 + w2 + 1e-5f);
    }
}

__kernel void BlendLinear_C4_D5(
    __global float4 *dst,
    __global float4 *img1,
    __global float4 *img2,
    __global float *weight1,
    __global float *weight2,
    int rows,
    int cols,
    int istep,
    int wstep
    )
{
    int idx = get_global_id(0);
    int idy = get_global_id(1);
    if (idx < cols && idy < rows)
    {
        int pos = mad24(idy,istep >> 2,idx);
        int wpos = mad24(idy,wstep, idx);
        float w1 = weight1[wpos];
        float w2 = weight2[wpos];
        dst[pos] = (img1[pos] * w1 + img2[pos] * w2) / (w1 + w2 + 1e-5f);
    }
}
