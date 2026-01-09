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
// Copyright (C) 2009-2011, Willow Garage Inc., all rights reserved.
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

#include "precomp.hpp"

#if defined __linux__ || defined __APPLE__
    #include <unistd.h>
    #include <stdio.h>
    #include <sys/types.h>
    #if defined ANDROID
        #include <sys/sysconf.h>
    #elif defined __APPLE__
        #include <sys/sysctl.h>
    #endif
#endif

#ifdef _OPENMP
    #define HAVE_OPENMP
#endif

#ifdef __APPLE__
    #define HAVE_GCD
#endif

#if defined _MSC_VER && _MSC_VER >= 1600
    #define HAVE_CONCURRENCY
#endif

/* IMPORTANT: always use the same order of defines
   1. HAVE_TBB         - 3rdparty library, should be explicitly enabled
   2. HAVE_CSTRIPES    - 3rdparty library, should be explicitly enabled
   3. HAVE_OPENMP      - integrated to compiler, should be explicitly enabled
   4. HAVE_GCD         - system wide, used automatically        (APPLE only)
   5. HAVE_CONCURRENCY - part of runtime, used automatically    (Windows only - MSVS 10, MSVS 11)
*/

#if defined HAVE_TBB
    #include "tbb/tbb_stddef.h"
    #if TBB_VERSION_MAJOR*100 + TBB_VERSION_MINOR >= 202
        #include "tbb/tbb.h"
        #include "tbb/task.h"
        #if TBB_INTERFACE_VERSION >= 6100
            #include "tbb/task_arena.h"
        #endif
        #undef min
        #undef max
    #else
        #undef HAVE_TBB
    #endif // end TBB version
#endif

#ifndef HAVE_TBB
    #if defined HAVE_CSTRIPES
        #include "C=.h"
        #undef shared
    #elif defined HAVE_OPENMP
        #include <omp.h>
    #elif defined HAVE_GCD
        #include <dispatch/dispatch.h>
        #include <pthread.h>
    #elif defined HAVE_CONCURRENCY
        #include <ppl.h>
    #endif
#endif

#if defined HAVE_TBB && TBB_VERSION_MAJOR*100 + TBB_VERSION_MINOR >= 202
#  define CV_PARALLEL_FRAMEWORK "tbb"
#elif defined HAVE_CSTRIPES
#  define CV_PARALLEL_FRAMEWORK "cstripes"
#elif defined HAVE_OPENMP
#  define CV_PARALLEL_FRAMEWORK "openmp"
#elif defined HAVE_GCD
#  define CV_PARALLEL_FRAMEWORK "gcd"
#elif defined HAVE_CONCURRENCY
#  define CV_PARALLEL_FRAMEWORK "ms-concurrency"
#endif

namespace cv
{
    ParallelLoopBody::~ParallelLoopBody() {}
}

namespace
{
#ifdef CV_PARALLEL_FRAMEWORK
    class ParallelLoopBodyWrapper
    {
    public:
        ParallelLoopBodyWrapper(const cv::ParallelLoopBody& _body, const cv::Range& _r, double _nstripes)
        {
            body = &_body;
            wholeRange = _r;
            double len = wholeRange.end - wholeRange.start;
            nstripes = cvRound(_nstripes <= 0 ? len : MIN(MAX(_nstripes, 1.), len));
        }
        void operator()(const cv::Range& sr) const
        {
            cv::Range r;
            r.start = (int)(wholeRange.start +
                            ((uint64)sr.start*(wholeRange.end - wholeRange.start) + nstripes/2)/nstripes);
            r.end = sr.end >= nstripes ? wholeRange.end : (int)(wholeRange.start +
                            ((uint64)sr.end*(wholeRange.end - wholeRange.start) + nstripes/2)/nstripes);
            (*body)(r);
        }
        cv::Range stripeRange() const { return cv::Range(0, nstripes); }

    protected:
        const cv::ParallelLoopBody* body;
        cv::Range wholeRange;
        int nstripes;
    };

#if defined HAVE_TBB
    class ProxyLoopBody : public ParallelLoopBodyWrapper
    {
    public:
        ProxyLoopBody(const cv::ParallelLoopBody& _body, const cv::Range& _r, double _nstripes)
        : ParallelLoopBodyWrapper(_body, _r, _nstripes)
        {}

        void operator ()(const tbb::blocked_range<int>& range) const
        {
            this->ParallelLoopBodyWrapper::operator()(cv::Range(range.begin(), range.end()));
        }
    };
#elif defined HAVE_CSTRIPES || defined HAVE_OPENMP
    typedef ParallelLoopBodyWrapper ProxyLoopBody;
#elif defined HAVE_GCD
    typedef ParallelLoopBodyWrapper ProxyLoopBody;
    static void block_function(void* context, size_t index)
    {
        ProxyLoopBody* ptr_body = static_cast<ProxyLoopBody*>(context);
        (*ptr_body)(cv::Range((int)index, (int)index + 1));
    }
#elif defined HAVE_CONCURRENCY
    class ProxyLoopBody : public ParallelLoopBodyWrapper
    {
    public:
        ProxyLoopBody(const cv::ParallelLoopBody& _body, const cv::Range& _r, double _nstripes)
        : ParallelLoopBodyWrapper(_body, _r, _nstripes)
        {}

        void operator ()(int i) const
        {
            this->ParallelLoopBodyWrapper::operator()(cv::Range(i, i + 1));
        }
    };
#else
    typedef ParallelLoopBodyWrapper ProxyLoopBody;
#endif

static int numThreads = -1;

#if defined HAVE_TBB
static tbb::task_scheduler_init tbbScheduler(tbb::task_scheduler_init::deferred);
#elif defined HAVE_CSTRIPES
// nothing for C=
#elif defined HAVE_OPENMP
static int numThreadsMax = omp_get_max_threads();
#elif defined HAVE_GCD
// nothing for GCD
#elif defined HAVE_CONCURRENCY
class SchedPtr
{
    Concurrency::Scheduler* sched_;
public:
    Concurrency::Scheduler* operator->() { return sched_; }
    operator Concurrency::Scheduler*() { return sched_; }

    void operator=(Concurrency::Scheduler* sched)
    {
        if (sched_) sched_->Release();
        sched_ = sched;
    }

    SchedPtr() : sched_(0) {}
    ~SchedPtr() { *this = 0; }
};
static SchedPtr pplScheduler;
#endif

#endif // CV_PARALLEL_FRAMEWORK

} //namespace

/* ================================   parallel_for_  ================================ */

void cv::parallel_for_(const cv::Range& range, const cv::ParallelLoopBody& body, double nstripes)
{
#ifdef CV_PARALLEL_FRAMEWORK

    if(numThreads != 0)
    {
        ProxyLoopBody pbody(body, range, nstripes);
        cv::Range stripeRange = pbody.stripeRange();

#if defined HAVE_TBB

        tbb::parallel_for(tbb::blocked_range<int>(stripeRange.start, stripeRange.end), pbody);

#elif defined HAVE_CSTRIPES

        parallel(MAX(0, numThreads))
        {
            int offset = stripeRange.start;
            int len = stripeRange.end - offset;
            Range r(offset + CPX_RANGE_START(len), offset + CPX_RANGE_END(len));
            pbody(r);
            barrier();
        }

#elif defined HAVE_OPENMP

        #pragma omp parallel for schedule(dynamic)
        for (int i = stripeRange.start; i < stripeRange.end; ++i)
            pbody(Range(i, i + 1));

#elif defined HAVE_GCD

        dispatch_queue_t concurrent_queue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
        dispatch_apply_f(stripeRange.end - stripeRange.start, concurrent_queue, &pbody, block_function);

#elif defined HAVE_CONCURRENCY

        if(!pplScheduler || pplScheduler->Id() == Concurrency::CurrentScheduler::Id())
        {
            Concurrency::parallel_for(stripeRange.start, stripeRange.end, pbody);
        }
        else
        {
            pplScheduler->Attach();
            Concurrency::parallel_for(stripeRange.start, stripeRange.end, pbody);
            Concurrency::CurrentScheduler::Detach();
        }

#else

#error You have hacked and compiling with unsupported parallel framework

#endif

    }
    else

#endif // CV_PARALLEL_FRAMEWORK
    {
        (void)nstripes;
        body(range);
    }
}

const char* cv::currentParallelFramework() {
#ifdef CV_PARALLEL_FRAMEWORK
    return CV_PARALLEL_FRAMEWORK;
#else
    return NULL;
#endif
}
