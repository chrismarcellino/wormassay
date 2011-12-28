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
// Copyright (C) 2000-2008, Intel Corporation, all rights reserved.
// Copyright (C) 2009, Willow Garage Inc., all rights reserved.
// Third party copyrights are property of their respective owners.
//
// Redistribution and use in source and binary forms, with or without modification,
// are permitted provided that the following conditions are met:
//
//   * Redistribution's of source code must retain the above copyright notice,
//     this list of conditions and the following disclaimer.
//
//   * Redistribution's in binary form must reproduce the above copyright notice,
//     this list of conditions and the following disclaimer in the documentation
//     and/or other materials provided with the distribution.
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

#include "cuda_shared.hpp"
#include "border_interpolate.hpp"

using namespace cv::gpu;

/////////////////////////////////// Remap ///////////////////////////////////////////////
namespace cv { namespace gpu { namespace imgproc
{
    texture<unsigned char, 2, cudaReadModeNormalizedFloat> tex_remap;

    __global__ void remap_1c(const float* mapx, const float* mapy, size_t map_step, uchar* out, size_t out_step, int width, int height)
    {    
        int x = blockDim.x * blockIdx.x + threadIdx.x;
        int y = blockDim.y * blockIdx.y + threadIdx.y;
        if (x < width && y < height)
        {
            int idx = y * (map_step >> 2) + x; /* map_step >> 2  <=> map_step / sizeof(float)*/

            float xcoo = mapx[idx];
            float ycoo = mapy[idx];

            out[y * out_step + x] = (unsigned char)(255.f * tex2D(tex_remap, xcoo, ycoo));            
        }
    }

    __global__ void remap_3c(const uchar* src, size_t src_step, const float* mapx, const float* mapy, size_t map_step, 
                             uchar* dst, size_t dst_step, int width, int height)
    {    
        const int x = blockDim.x * blockIdx.x + threadIdx.x;
        const int y = blockDim.y * blockIdx.y + threadIdx.y;

        if (x < width && y < height)
        {
            const int idx = y * (map_step >> 2) + x; /* map_step >> 2  <=> map_step / sizeof(float)*/

            const float xcoo = mapx[idx];
            const float ycoo = mapy[idx];
            
            uchar3 out = make_uchar3(0, 0, 0);

            if (xcoo >= 0 && xcoo < width - 1 && ycoo >= 0 && ycoo < height - 1)
            {
                const int x1 = __float2int_rd(xcoo);
                const int y1 = __float2int_rd(ycoo);
                const int x2 = x1 + 1;
                const int y2 = y1 + 1;
                
                uchar src_reg = *(src + y1 * src_step + 3 * x1);
                out.x += src_reg * (x2 - xcoo) * (y2 - ycoo);
                src_reg = *(src + y1 * src_step + 3 * x1 + 1);
                out.y += src_reg * (x2 - xcoo) * (y2 - ycoo);
                src_reg = *(src + y1 * src_step + 3 * x1 + 2);
                out.z += src_reg * (x2 - xcoo) * (y2 - ycoo);

                src_reg = *(src + y1 * src_step + 3 * x2);                
                out.x += src_reg * (xcoo - x1) * (y2 - ycoo);
                src_reg = *(src + y1 * src_step + 3 * x2 + 1); 
                out.y += src_reg * (xcoo - x1) * (y2 - ycoo);
                src_reg = *(src + y1 * src_step + 3 * x2 + 2); 
                out.z += src_reg * (xcoo - x1) * (y2 - ycoo);

                src_reg = *(src + y2 * src_step + 3 * x1);                
                out.x += src_reg * (x2 - xcoo) * (ycoo - y1);
                src_reg = *(src + y2 * src_step + 3 * x1 + 1); 
                out.y += src_reg * (x2 - xcoo) * (ycoo - y1);
                src_reg = *(src + y2 * src_step + 3 * x1 + 2); 
                out.z += src_reg * (x2 - xcoo) * (ycoo - y1);

                src_reg = *(src + y2 * src_step + 3 * x2);                
                out.x += src_reg * (xcoo - x1) * (ycoo - y1);
                src_reg = *(src + y2 * src_step + 3 * x2 + 1);  
                out.y += src_reg * (xcoo - x1) * (ycoo - y1);
                src_reg = *(src + y2 * src_step + 3 * x2 + 2);  
                out.z += src_reg * (xcoo - x1) * (ycoo - y1);
            }

            /**(uchar3*)(dst + y * dst_step + 3 * x) = out;*/
            *(dst + y * dst_step + 3 * x) = out.x;
            *(dst + y * dst_step + 3 * x + 1) = out.y;
            *(dst + y * dst_step + 3 * x + 2) = out.z;
        }
    }

    void remap_gpu_1c(const DevMem2D& src, const DevMem2Df& xmap, const DevMem2Df& ymap, DevMem2D dst)
    {
        dim3 threads(16, 16, 1);
        dim3 grid(1, 1, 1);
        grid.x = divUp(dst.cols, threads.x);
        grid.y = divUp(dst.rows, threads.y);

        tex_remap.filterMode = cudaFilterModeLinear;	    
        tex_remap.addressMode[0] = tex_remap.addressMode[1] = cudaAddressModeWrap;
        cudaChannelFormatDesc desc = cudaCreateChannelDesc<unsigned char>();
        cudaSafeCall( cudaBindTexture2D(0, tex_remap, src.data, desc, src.cols, src.rows, src.step) );

        remap_1c<<<grid, threads>>>(xmap.data, ymap.data, xmap.step, dst.data, dst.step, dst.cols, dst.rows);

        cudaSafeCall( cudaThreadSynchronize() );  
        cudaSafeCall( cudaUnbindTexture(tex_remap) );
    }
    
    void remap_gpu_3c(const DevMem2D& src, const DevMem2Df& xmap, const DevMem2Df& ymap, DevMem2D dst)
    {
        dim3 threads(32, 8, 1);
        dim3 grid(1, 1, 1);
        grid.x = divUp(dst.cols, threads.x);
        grid.y = divUp(dst.rows, threads.y);

        remap_3c<<<grid, threads>>>(src.data, src.step, xmap.data, ymap.data, xmap.step, dst.data, dst.step, dst.cols, dst.rows);

        cudaSafeCall( cudaThreadSynchronize() ); 
    }

/////////////////////////////////// MeanShiftfiltering ///////////////////////////////////////////////

    texture<uchar4, 2> tex_meanshift;

    __device__ short2 do_mean_shift(int x0, int y0, unsigned char* out, 
                                    int out_step, int cols, int rows, 
                                    int sp, int sr, int maxIter, float eps)
    {
        int isr2 = sr*sr;
        uchar4 c = tex2D(tex_meanshift, x0, y0 );

        // iterate meanshift procedure
        for( int iter = 0; iter < maxIter; iter++ )
        {
            int count = 0;
            int s0 = 0, s1 = 0, s2 = 0, sx = 0, sy = 0;
            float icount;

            //mean shift: process pixels in window (p-sigmaSp)x(p+sigmaSp)
            int minx = x0-sp;
            int miny = y0-sp;
            int maxx = x0+sp;
            int maxy = y0+sp;

            for( int y = miny; y <= maxy; y++)
            {
                int rowCount = 0;
                for( int x = minx; x <= maxx; x++ )
                {                    
                    uchar4 t = tex2D( tex_meanshift, x, y );

                    int norm2 = (t.x - c.x) * (t.x - c.x) + (t.y - c.y) * (t.y - c.y) + (t.z - c.z) * (t.z - c.z);
                    if( norm2 <= isr2 )
                    {
                        s0 += t.x; s1 += t.y; s2 += t.z;
                        sx += x; rowCount++;
                    }
                }
                count += rowCount;
                sy += y*rowCount;
            }

            if( count == 0 )
                break;

            icount = 1.f/count;
            int x1 = __float2int_rz(sx*icount);
            int y1 = __float2int_rz(sy*icount);
            s0 = __float2int_rz(s0*icount);
            s1 = __float2int_rz(s1*icount);
            s2 = __float2int_rz(s2*icount);

            int norm2 = (s0 - c.x) * (s0 - c.x) + (s1 - c.y) * (s1 - c.y) + (s2 - c.z) * (s2 - c.z);

            bool stopFlag = (x0 == x1 && y0 == y1) || (abs(x1-x0) + abs(y1-y0) + norm2 <= eps);

            x0 = x1; y0 = y1;
            c.x = s0; c.y = s1; c.z = s2;

            if( stopFlag )
                break;
        }

        int base = (blockIdx.y * blockDim.y + threadIdx.y) * out_step + (blockIdx.x * blockDim.x + threadIdx.x) * 4 * sizeof(uchar);
        *(uchar4*)(out + base) = c;

        return make_short2((short)x0, (short)y0);
    }

    extern "C" __global__ void meanshift_kernel( unsigned char* out, int out_step, int cols, int rows, 
                                                 int sp, int sr, int maxIter, float eps )
    {
        int x0 = blockIdx.x * blockDim.x + threadIdx.x;
        int y0 = blockIdx.y * blockDim.y + threadIdx.y;

        if( x0 < cols && y0 < rows )
            do_mean_shift(x0, y0, out, out_step, cols, rows, sp, sr, maxIter, eps);
    }

    extern "C" __global__ void meanshiftproc_kernel( unsigned char* outr, int outrstep, 
                                                 unsigned char* outsp, int outspstep, 
                                                 int cols, int rows, 
                                                 int sp, int sr, int maxIter, float eps )
    {
        int x0 = blockIdx.x * blockDim.x + threadIdx.x;
        int y0 = blockIdx.y * blockDim.y + threadIdx.y;

        if( x0 < cols && y0 < rows )
        {            
            int basesp = (blockIdx.y * blockDim.y + threadIdx.y) * outspstep + (blockIdx.x * blockDim.x + threadIdx.x) * 2 * sizeof(short);
            *(short2*)(outsp + basesp) = do_mean_shift(x0, y0, outr, outrstep, cols, rows, sp, sr, maxIter, eps);
        }
    }

    extern "C" void meanShiftFiltering_gpu(const DevMem2D& src, DevMem2D dst, int sp, int sr, int maxIter, float eps)
    {                        
        dim3 grid(1, 1, 1);
        dim3 threads(32, 16, 1);
        grid.x = divUp(src.cols, threads.x);
        grid.y = divUp(src.rows, threads.y);

        cudaChannelFormatDesc desc = cudaCreateChannelDesc<uchar4>();
        cudaSafeCall( cudaBindTexture2D( 0, tex_meanshift, src.data, desc, src.cols, src.rows, src.step ) );

        meanshift_kernel<<< grid, threads >>>( dst.data, dst.step, dst.cols, dst.rows, sp, sr, maxIter, eps );
        cudaSafeCall( cudaThreadSynchronize() );
        cudaSafeCall( cudaUnbindTexture( tex_meanshift ) );        
    }
    extern "C" void meanShiftProc_gpu(const DevMem2D& src, DevMem2D dstr, DevMem2D dstsp, int sp, int sr, int maxIter, float eps) 
    {
        dim3 grid(1, 1, 1);
        dim3 threads(32, 16, 1);
        grid.x = divUp(src.cols, threads.x);
        grid.y = divUp(src.rows, threads.y);

        cudaChannelFormatDesc desc = cudaCreateChannelDesc<uchar4>();
        cudaSafeCall( cudaBindTexture2D( 0, tex_meanshift, src.data, desc, src.cols, src.rows, src.step ) );

        meanshiftproc_kernel<<< grid, threads >>>( dstr.data, dstr.step, dstsp.data, dstsp.step, dstr.cols, dstr.rows, sp, sr, maxIter, eps );
        cudaSafeCall( cudaThreadSynchronize() );
        cudaSafeCall( cudaUnbindTexture( tex_meanshift ) );        
    }

/////////////////////////////////// drawColorDisp ///////////////////////////////////////////////

    template <typename T>
    __device__ unsigned int cvtPixel(T d, int ndisp, float S = 1, float V = 1)
    {        
        unsigned int H = ((ndisp-d) * 240)/ndisp;

        unsigned int hi = (H/60) % 6;
        float f = H/60.f - H/60;
        float p = V * (1 - S);
        float q = V * (1 - f * S);
        float t = V * (1 - (1 - f) * S);

        float3 res;
        
        if (hi == 0) //R = V,	G = t,	B = p
        {
            res.x = p;
            res.y = t;
            res.z = V;
        }

        if (hi == 1) // R = q,	G = V,	B = p
        {
            res.x = p;
            res.y = V;
            res.z = q;
        }        
        
        if (hi == 2) // R = p,	G = V,	B = t
        {
            res.x = t;
            res.y = V;
            res.z = p;
        }
            
        if (hi == 3) // R = p,	G = q,	B = V
        {
            res.x = V;
            res.y = q;
            res.z = p;
        }

        if (hi == 4) // R = t,	G = p,	B = V
        {
            res.x = V;
            res.y = p;
            res.z = t;
        }

        if (hi == 5) // R = V,	G = p,	B = q
        {
            res.x = q;
            res.y = p;
            res.z = V;
        }
        const unsigned int b = (unsigned int)(max(0.f, min (res.x, 1.f)) * 255.f);
        const unsigned int g = (unsigned int)(max(0.f, min (res.y, 1.f)) * 255.f);
        const unsigned int r = (unsigned int)(max(0.f, min (res.z, 1.f)) * 255.f);
        const unsigned int a = 255U;

        return (a << 24) + (r << 16) + (g << 8) + b;    
    } 

    __global__ void drawColorDisp(uchar* disp, size_t disp_step, uchar* out_image, size_t out_step, int width, int height, int ndisp)
    {
        const int x = (blockIdx.x * blockDim.x + threadIdx.x) << 2;
        const int y = blockIdx.y * blockDim.y + threadIdx.y;

        if(x < width && y < height) 
        {
            uchar4 d4 = *(uchar4*)(disp + y * disp_step + x);

            uint4 res;
            res.x = cvtPixel(d4.x, ndisp);
            res.y = cvtPixel(d4.y, ndisp);
            res.z = cvtPixel(d4.z, ndisp);
            res.w = cvtPixel(d4.w, ndisp);
                    
            uint4* line = (uint4*)(out_image + y * out_step);
            line[x >> 2] = res;
        }
    }

    __global__ void drawColorDisp(short* disp, size_t disp_step, uchar* out_image, size_t out_step, int width, int height, int ndisp)
    {
        const int x = (blockIdx.x * blockDim.x + threadIdx.x) << 1;
        const int y = blockIdx.y * blockDim.y + threadIdx.y;

        if(x < width && y < height) 
        {
            short2 d2 = *(short2*)(disp + y * disp_step + x);

            uint2 res;
            res.x = cvtPixel(d2.x, ndisp);            
            res.y = cvtPixel(d2.y, ndisp);

            uint2* line = (uint2*)(out_image + y * out_step);
            line[x >> 1] = res;
        }
    }


    void drawColorDisp_gpu(const DevMem2D& src, const DevMem2D& dst, int ndisp, const cudaStream_t& stream)
    {
        dim3 threads(16, 16, 1);
        dim3 grid(1, 1, 1);
        grid.x = divUp(src.cols, threads.x << 2);
        grid.y = divUp(src.rows, threads.y);
         
        drawColorDisp<<<grid, threads, 0, stream>>>(src.data, src.step, dst.data, dst.step, src.cols, src.rows, ndisp);

        if (stream == 0)
            cudaSafeCall( cudaThreadSynchronize() ); 
    }

    void drawColorDisp_gpu(const DevMem2D_<short>& src, const DevMem2D& dst, int ndisp, const cudaStream_t& stream)
    {
        dim3 threads(32, 8, 1);
        dim3 grid(1, 1, 1);
        grid.x = divUp(src.cols, threads.x << 1);
        grid.y = divUp(src.rows, threads.y);
         
        drawColorDisp<<<grid, threads, 0, stream>>>(src.data, src.step / sizeof(short), dst.data, dst.step, src.cols, src.rows, ndisp);
        
        if (stream == 0)
            cudaSafeCall( cudaThreadSynchronize() );
    }

/////////////////////////////////// reprojectImageTo3D ///////////////////////////////////////////////

    __constant__ float cq[16];

    template <typename T>
    __global__ void reprojectImageTo3D(const T* disp, size_t disp_step, float* xyzw, size_t xyzw_step, int rows, int cols)
    {        
        const int x = blockIdx.x * blockDim.x + threadIdx.x;
        const int y = blockIdx.y * blockDim.y + threadIdx.y;

        if (y < rows && x < cols)
        {

            float qx = cq[1] * y + cq[3], qy = cq[5] * y + cq[7];
            float qz = cq[9] * y + cq[11], qw = cq[13] * y + cq[15];

            qx += x * cq[0]; 
            qy += x * cq[4];
            qz += x * cq[8];
            qw += x * cq[12];

            T d = *(disp + disp_step * y + x);

            float iW = 1.f / (qw + cq[14] * d);
            float4 v;
            v.x = (qx + cq[2] * d) * iW;
            v.y = (qy + cq[6] * d) * iW;
            v.z = (qz + cq[10] * d) * iW;
            v.w = 1.f;

            *(float4*)(xyzw + xyzw_step * y + (x * 4)) = v;
        }
    }

    template <typename T>
    inline void reprojectImageTo3D_caller(const DevMem2D_<T>& disp, const DevMem2Df& xyzw, const float* q, const cudaStream_t& stream)
    {
        dim3 threads(32, 8, 1);
        dim3 grid(1, 1, 1);
        grid.x = divUp(disp.cols, threads.x);
        grid.y = divUp(disp.rows, threads.y);

        cudaSafeCall( cudaMemcpyToSymbol(cq, q, 16 * sizeof(float)) );

        reprojectImageTo3D<<<grid, threads, 0, stream>>>(disp.data, disp.step / sizeof(T), xyzw.data, xyzw.step / sizeof(float), disp.rows, disp.cols);

        if (stream == 0)
            cudaSafeCall( cudaThreadSynchronize() );
    }

    void reprojectImageTo3D_gpu(const DevMem2D& disp, const DevMem2Df& xyzw, const float* q, const cudaStream_t& stream)
    {
        reprojectImageTo3D_caller(disp, xyzw, q, stream);
    }

    void reprojectImageTo3D_gpu(const DevMem2D_<short>& disp, const DevMem2Df& xyzw, const float* q, const cudaStream_t& stream)
    {
        reprojectImageTo3D_caller(disp, xyzw, q, stream);
    }

//////////////////////////////////////// Extract Cov Data ////////////////////////////////////////////////

    __global__ void extractCovData_kernel(const int cols, const int rows, const PtrStepf Dx, 
                                          const PtrStepf Dy, PtrStepf dst)
    {
        const int x = blockIdx.x * blockDim.x + threadIdx.x;
        const int y = blockIdx.y * blockDim.y + threadIdx.y;

        if (x < cols && y < rows)
        {            
            float dx = Dx.ptr(y)[x];
            float dy = Dy.ptr(y)[x];

            dst.ptr(y)[x] = dx * dx;
            dst.ptr(y + rows)[x] = dx * dy;
            dst.ptr(y + (rows << 1))[x] = dy * dy;
        }
    }

    void extractCovData_caller(const DevMem2Df Dx, const DevMem2Df Dy, PtrStepf dst)
    {
        dim3 threads(32, 8);
        dim3 grid(divUp(Dx.cols, threads.x), divUp(Dx.rows, threads.y));

        extractCovData_kernel<<<grid, threads>>>(Dx.cols, Dx.rows, Dx, Dy, dst);
        cudaSafeCall(cudaThreadSynchronize());
    }

/////////////////////////////////////////// Corner Harris /////////////////////////////////////////////////

    texture<float, 2> harrisDxTex;
    texture<float, 2> harrisDyTex;

    template <typename B>
    __global__ void cornerHarris_kernel(const int cols, const int rows, const int block_size, const float k,
                                        PtrStep dst, B border_row, B border_col)
    {
        const unsigned int x = blockIdx.x * blockDim.x + threadIdx.x;
        const unsigned int y = blockIdx.y * blockDim.y + threadIdx.y;

        if (x < cols && y < rows)
        {
            float a = 0.f;
            float b = 0.f;
            float c = 0.f;

            const int ibegin = y - (block_size / 2);
            const int jbegin = x - (block_size / 2);
            const int iend = ibegin + block_size;
            const int jend = jbegin + block_size;

            for (int i = ibegin; i < iend; ++i)
            {
                int y = border_col.idx(i);
                for (int j = jbegin; j < jend; ++j)
                {
                    int x = border_row.idx(j);
                    float dx = tex2D(harrisDxTex, x, y);
                    float dy = tex2D(harrisDyTex, x, y);
                    a += dx * dx;
                    b += dx * dy;
                    c += dy * dy;
                }
            }

            ((float*)dst.ptr(y))[x] = a * c - b * b - k * (a + c) * (a + c);
        }
    }

    void cornerHarris_caller(const int block_size, const float k, const DevMem2D Dx, const DevMem2D Dy, DevMem2D dst, 
                             int border_type)
    {
        const int rows = Dx.rows;
        const int cols = Dx.cols;

        dim3 threads(32, 8);
        dim3 grid(divUp(cols, threads.x), divUp(rows, threads.y));

        cudaChannelFormatDesc desc = cudaCreateChannelDesc<float>();
        cudaBindTexture2D(0, harrisDxTex, Dx.data, desc, Dx.cols, Dx.rows, Dx.step);
        cudaBindTexture2D(0, harrisDyTex, Dy.data, desc, Dy.cols, Dy.rows, Dy.step);
        harrisDxTex.filterMode = cudaFilterModePoint;
        harrisDyTex.filterMode = cudaFilterModePoint;

        switch (border_type) 
        {
        case BORDER_REFLECT101:
            cornerHarris_kernel<<<grid, threads>>>(
                    cols, rows, block_size, k, dst, BrdReflect101(cols), BrdReflect101(rows));
            break;
        }

        cudaSafeCall(cudaThreadSynchronize());
        cudaSafeCall(cudaUnbindTexture(harrisDxTex));
        cudaSafeCall(cudaUnbindTexture(harrisDyTex));
    }

/////////////////////////////////////////// Corner Min Eigen Val /////////////////////////////////////////////////

    texture<float, 2> minEigenValDxTex;
    texture<float, 2> minEigenValDyTex;

    template <typename B>
    __global__ void cornerMinEigenVal_kernel(const int cols, const int rows, const int block_size, 
                                             PtrStep dst, B border_row, B border_col)
    {
        const unsigned int x = blockIdx.x * blockDim.x + threadIdx.x;
        const unsigned int y = blockIdx.y * blockDim.y + threadIdx.y;

        if (x < cols && y < rows)
        {
            float a = 0.f;
            float b = 0.f;
            float c = 0.f;

            const int ibegin = y - (block_size / 2);
            const int jbegin = x - (block_size / 2);
            const int iend = ibegin + block_size;
            const int jend = jbegin + block_size;

            for (int i = ibegin; i < iend; ++i)
            {
                int y = border_col.idx(i);
                for (int j = jbegin; j < jend; ++j)
                {
                    int x = border_row.idx(j);
                    float dx = tex2D(minEigenValDxTex, x, y);
                    float dy = tex2D(minEigenValDyTex, x, y);
                    a += dx * dx;
                    b += dx * dy;
                    c += dy * dy;
                }
            }

            a *= 0.5f;
            c *= 0.5f;
            ((float*)dst.ptr(y))[x] = (a + c) - sqrtf((a - c) * (a - c) + b * b);
        }
    }

    void cornerMinEigenVal_caller(const int block_size, const DevMem2D Dx, const DevMem2D Dy, DevMem2D dst,
                                  int border_type)
    {
        const int rows = Dx.rows;
        const int cols = Dx.cols;

        dim3 threads(32, 8);
        dim3 grid(divUp(cols, threads.x), divUp(rows, threads.y));

        cudaChannelFormatDesc desc = cudaCreateChannelDesc<float>();
        cudaBindTexture2D(0, minEigenValDxTex, Dx.data, desc, Dx.cols, Dx.rows, Dx.step);
        cudaBindTexture2D(0, minEigenValDyTex, Dy.data, desc, Dy.cols, Dy.rows, Dy.step);
        minEigenValDxTex.filterMode = cudaFilterModePoint;
        minEigenValDyTex.filterMode = cudaFilterModePoint;

        switch (border_type)
        {
        case BORDER_REFLECT101:
            cornerMinEigenVal_kernel<<<grid, threads>>>(
                    cols, rows, block_size, dst, 
                    BrdReflect101(cols), BrdReflect101(rows));
            break;
        }

        cudaSafeCall(cudaThreadSynchronize());
        cudaSafeCall(cudaUnbindTexture(minEigenValDxTex));
        cudaSafeCall(cudaUnbindTexture(minEigenValDyTex));
    }
}}}

