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

#include "precomp.hpp"

#include <pthread.h>
#include <sys/time.h>
#include <time.h>

#if defined __MACH__ && defined __APPLE__
#include <mach/mach.h>
#include <mach/mach_time.h>
#endif

#ifdef _OPENMP
#include "omp.h"
#endif

#include <stdarg.h>

#if defined __linux__ || defined __APPLE__ || defined __EMSCRIPTEN__ || defined __QNX__
#include <unistd.h>
#include <stdio.h>
#include <sys/types.h>
#if defined ANDROID
#include <sys/sysconf.h>
#endif
#endif

#ifdef ANDROID
# include <android/log.h>
#endif

namespace cv
{

Exception::Exception() { code = 0; line = 0; }

Exception::Exception(int _code, const string& _err, const string& _func, const string& _file, int _line)
: code(_code), err(_err), func(_func), file(_file), line(_line)
{
    formatMessage();
}

Exception::~Exception() throw() {}

/*!
 \return the error description and the context as a text string.
 */
const char* Exception::what() const throw() { return msg.c_str(); }

void Exception::formatMessage()
{
    if( func.size() > 0 )
        msg = format("%s:%d: error: (%d) %s in function %s\n", file.c_str(), line, code, err.c_str(), func.c_str());
    else
        msg = format("%s:%d: error: (%d) %s\n", file.c_str(), line, code, err.c_str());
}

string format( const char* fmt, ... )
{
    char buf[1 << 16];
    va_list args;
    va_start( args, fmt );
    vsprintf( buf, fmt, args );
    return string(buf);
}

static CvErrorCallback customErrorCallback = 0;
static void* customErrorCallbackData = 0;
static bool breakOnError = false;

bool setBreakOnError(bool value)
{
    bool prevVal = breakOnError;
    breakOnError = value;
    return prevVal;
}

void error( const Exception& exc )
{
    if (customErrorCallback != 0)
        customErrorCallback(exc.code, exc.func.c_str(), exc.err.c_str(),
                            exc.file.c_str(), exc.line, customErrorCallbackData);
    else
    {
        const char* errorStr = cvErrorStr(exc.code);
        char buf[1 << 16];

        sprintf( buf, "OpenCV Error: %s (%s) in %s, file %s, line %d",
            errorStr, exc.err.c_str(), exc.func.size() > 0 ?
            exc.func.c_str() : "unknown function", exc.file.c_str(), exc.line );
        fprintf( stderr, "%s\n", buf );
        fflush( stderr );
#  ifdef __ANDROID__
        __android_log_print(ANDROID_LOG_ERROR, "cv::error()", "%s", buf);
#  endif
    }

    if(breakOnError)
    {
        static volatile int* p = 0;
        *p = 0;
    }

    throw exc;
}

CvErrorCallback
redirectError( CvErrorCallback errCallback, void* userdata, void** prevUserdata)
{
    if( prevUserdata )
        *prevUserdata = customErrorCallbackData;

    CvErrorCallback prevCallback = customErrorCallback;

    customErrorCallback     = errCallback;
    customErrorCallbackData = userdata;

    return prevCallback;
}

}

CV_IMPL CvErrorCallback
cvRedirectError( CvErrorCallback errCallback, void* userdata, void** prevUserdata)
{
    return cv::redirectError(errCallback, userdata, prevUserdata);
}

CV_IMPL int cvNulDevReport( int, const char*, const char*,
                            const char*, int, void* )
{
    return 0;
}

CV_IMPL int cvStdErrReport( int, const char*, const char*,
                            const char*, int, void* )
{
    return 0;
}

CV_IMPL int cvGuiBoxReport( int, const char*, const char*,
                            const char*, int, void* )
{
    return 0;
}

CV_IMPL int cvGetErrInfo( const char**, const char**, const char**, int* )
{
    return 0;
}


CV_IMPL const char* cvErrorStr( int status )
{
    static char buf[256];

    switch (status)
    {
    case CV_StsOk :                  return "No Error";
    case CV_StsBackTrace :           return "Backtrace";
    case CV_StsError :               return "Unspecified error";
    case CV_StsInternal :            return "Internal error";
    case CV_StsNoMem :               return "Insufficient memory";
    case CV_StsBadArg :              return "Bad argument";
    case CV_StsNoConv :              return "Iterations do not converge";
    case CV_StsAutoTrace :           return "Autotrace call";
    case CV_StsBadSize :             return "Incorrect size of input array";
    case CV_StsNullPtr :             return "Null pointer";
    case CV_StsDivByZero :           return "Division by zero occured";
    case CV_BadStep :                return "Image step is wrong";
    case CV_StsInplaceNotSupported : return "Inplace operation is not supported";
    case CV_StsObjectNotFound :      return "Requested object was not found";
    case CV_BadDepth :               return "Input image depth is not supported by function";
    case CV_StsUnmatchedFormats :    return "Formats of input arguments do not match";
    case CV_StsUnmatchedSizes :      return "Sizes of input arguments do not match";
    case CV_StsOutOfRange :          return "One of arguments\' values is out of range";
    case CV_StsUnsupportedFormat :   return "Unsupported format or combination of formats";
    case CV_BadCOI :                 return "Input COI is not supported";
    case CV_BadNumChannels :         return "Bad number of channels";
    case CV_StsBadFlag :             return "Bad flag (parameter or structure field)";
    case CV_StsBadPoint :            return "Bad parameter of type CvPoint";
    case CV_StsBadMask :             return "Bad type of mask argument";
    case CV_StsParseError :          return "Parsing error";
    case CV_StsNotImplemented :      return "The function/feature is not implemented";
    case CV_StsBadMemBlock :         return "Memory block has been corrupted";
    case CV_StsAssert :              return "Assertion failed";
    case CV_GpuNotSupported :        return "No GPU support";
    case CV_GpuApiCallError :        return "Gpu API call";
    case CV_OpenGlNotSupported :     return "No OpenGL support";
    case CV_OpenGlApiCallError :     return "OpenGL API call";
    };

    sprintf(buf, "Unknown %s code %d", status >= 0 ? "status":"error", status);
    return buf;
}

CV_IMPL int cvGetErrMode(void)
{
    return 0;
}

CV_IMPL int cvSetErrMode(int)
{
    return 0;
}

CV_IMPL int cvGetErrStatus(void)
{
    return 0;
}

CV_IMPL void cvSetErrStatus(int)
{
}


CV_IMPL void cvError( int code, const char* func_name,
                      const char* err_msg,
                      const char* file_name, int line )
{
    cv::error(cv::Exception(code, err_msg, func_name, file_name, line));
}

/* function, which converts int to int */
CV_IMPL int
cvErrorFromIppStatus( int status )
{
    switch (status)
    {
    case CV_BADSIZE_ERR:               return CV_StsBadSize;
    case CV_BADMEMBLOCK_ERR:           return CV_StsBadMemBlock;
    case CV_NULLPTR_ERR:               return CV_StsNullPtr;
    case CV_DIV_BY_ZERO_ERR:           return CV_StsDivByZero;
    case CV_BADSTEP_ERR:               return CV_BadStep;
    case CV_OUTOFMEM_ERR:              return CV_StsNoMem;
    case CV_BADARG_ERR:                return CV_StsBadArg;
    case CV_NOTDEFINED_ERR:            return CV_StsError;
    case CV_INPLACE_NOT_SUPPORTED_ERR: return CV_StsInplaceNotSupported;
    case CV_NOTFOUND_ERR:              return CV_StsObjectNotFound;
    case CV_BADCONVERGENCE_ERR:        return CV_StsNoConv;
    case CV_BADDEPTH_ERR:              return CV_BadDepth;
    case CV_UNMATCHED_FORMATS_ERR:     return CV_StsUnmatchedFormats;
    case CV_UNSUPPORTED_COI_ERR:       return CV_BadCOI;
    case CV_UNSUPPORTED_CHANNELS_ERR:  return CV_BadNumChannels;
    case CV_BADFLAG_ERR:               return CV_StsBadFlag;
    case CV_BADRANGE_ERR:              return CV_StsBadArg;
    case CV_BADCOEF_ERR:               return CV_StsBadArg;
    case CV_BADFACTOR_ERR:             return CV_StsBadArg;
    case CV_BADPOINT_ERR:              return CV_StsBadPoint;

    default:
      return CV_StsError;
    }
}

CvModuleInfo* CvModule::first = 0, *CvModule::last = 0;

CvModule::CvModule( CvModuleInfo* _info )
{
    cvRegisterModule( _info );
    info = last;
}

CvModule::~CvModule(void)
{
    if( info )
    {
        CvModuleInfo* p = first;
        for( ; p != 0 && p->next != info; p = p->next )
            ;

        if( p )
            p->next = info->next;

        if( first == info )
            first = info->next;

        if( last == info )
            last = p;

        free( info );
        info = 0;
    }
}

CV_IMPL int
cvRegisterModule( const CvModuleInfo* module )
{
    CV_Assert( module != 0 && module->name != 0 && module->version != 0 );

    size_t name_len = strlen(module->name);
    size_t version_len = strlen(module->version);

    CvModuleInfo* module_copy = (CvModuleInfo*)malloc( sizeof(*module_copy) +
                                name_len + 1 + version_len + 1 );

    *module_copy = *module;
    module_copy->name = (char*)(module_copy + 1);
    module_copy->version = (char*)(module_copy + 1) + name_len + 1;

    memcpy( (void*)module_copy->name, module->name, name_len + 1 );
    memcpy( (void*)module_copy->version, module->version, version_len + 1 );
    module_copy->next = 0;

    if( CvModule::first == 0 )
        CvModule::first = module_copy;
    else
        CvModule::last->next = module_copy;

    CvModule::last = module_copy;

    return 0;
}

CV_IMPL void
cvGetModuleInfo( const char* name, const char **version, const char **plugin_list )
{
    static char joint_verinfo[1024]   = "";
    static char plugin_list_buf[1024] = "";

    if( version )
        *version = 0;

    if( plugin_list )
        *plugin_list = 0;

    CvModuleInfo* module;

    if( version )
    {
        if( name )
        {
            size_t i, name_len = strlen(name);

            for( module = CvModule::first; module != 0; module = module->next )
            {
                if( strlen(module->name) == name_len )
                {
                    for( i = 0; i < name_len; i++ )
                    {
                        int c0 = toupper(module->name[i]), c1 = toupper(name[i]);
                        if( c0 != c1 )
                            break;
                    }
                    if( i == name_len )
                        break;
                }
            }
            if( !module )
                CV_Error( CV_StsObjectNotFound, "The module is not found" );

            *version = module->version;
        }
        else
        {
            char* ptr = joint_verinfo;

            for( module = CvModule::first; module != 0; module = module->next )
            {
                sprintf( ptr, "%s: %s%s", module->name, module->version, module->next ? ", " : "" );
                ptr += strlen(ptr);
            }

            *version = joint_verinfo;
        }
    }

    if( plugin_list )
        *plugin_list = plugin_list_buf;
}

namespace cv
{

#if defined __APPLE__

#if defined(__clang__)
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
#endif

#include <libkern/OSAtomic.h>

struct Mutex::Impl
{
    Impl() { sl = OS_SPINLOCK_INIT; refcount = 1; }
    ~Impl() {}

    void lock() { OSSpinLockLock(&sl); }
    bool trylock() { return OSSpinLockTry(&sl); }
    void unlock() { OSSpinLockUnlock(&sl); }

    OSSpinLock sl;
    int refcount;
};

#if defined(__clang__)
#pragma clang diagnostic pop
#endif

#elif defined __linux__ && !defined ANDROID && !defined __LINUXTHREADS_OLD__

struct Mutex::Impl
{
    Impl() { pthread_spin_init(&sl, 0); refcount = 1; }
    ~Impl() { pthread_spin_destroy(&sl); }

    void lock() { pthread_spin_lock(&sl); }
    bool trylock() { return pthread_spin_trylock(&sl) == 0; }
    void unlock() { pthread_spin_unlock(&sl); }

    pthread_spinlock_t sl;
    int refcount;
};

#else

struct Mutex::Impl
{
    Impl() { pthread_mutex_init(&sl, 0); refcount = 1; }
    ~Impl() { pthread_mutex_destroy(&sl); }

    void lock() { pthread_mutex_lock(&sl); }
    bool trylock() { return pthread_mutex_trylock(&sl) == 0; }
    void unlock() { pthread_mutex_unlock(&sl); }

    pthread_mutex_t sl;
    int refcount;
};

#endif

Mutex::Mutex()
{
    impl = new Mutex::Impl;
}

Mutex::~Mutex()
{
    if( CV_XADD(&impl->refcount, -1) == 1 )
        delete impl;
    impl = 0;
}

Mutex::Mutex(const Mutex& m)
{
    impl = m.impl;
    CV_XADD(&impl->refcount, 1);
}

Mutex& Mutex::operator = (const Mutex& m)
{
    CV_XADD(&m.impl->refcount, 1);
    if( CV_XADD(&impl->refcount, -1) == 1 )
        delete impl;
    impl = m.impl;
    return *this;
}

void Mutex::lock() { impl->lock(); }
void Mutex::unlock() { impl->unlock(); }
bool Mutex::trylock() { return impl->trylock(); }


//////////////////////////////// thread-local storage ////////////////////////////////

class TLSStorage
{
    std::vector<void*> tlsData_;
public:
    TLSStorage() { tlsData_.reserve(16); }
    ~TLSStorage();
    inline void* getData(int key) const
    {
        CV_DbgAssert(key >= 0);
        return (key < (int)tlsData_.size()) ? tlsData_[key] : NULL;
    }
    inline void setData(int key, void* data)
    {
        CV_DbgAssert(key >= 0);
        if (key >= (int)tlsData_.size())
        {
            tlsData_.resize(key + 1, NULL);
        }
        tlsData_[key] = data;
    }

    inline static TLSStorage* get();
};

    static pthread_key_t tlsKey = 0;
    static pthread_once_t tlsKeyOnce = PTHREAD_ONCE_INIT;

    static void deleteTLSStorage(void* data)
    {
        delete (TLSStorage*)data;
    }

    static void makeKey()
    {
        int errcode = pthread_key_create(&tlsKey, deleteTLSStorage);
        CV_Assert(errcode == 0);
    }

    inline TLSStorage* TLSStorage::get()
    {
        pthread_once(&tlsKeyOnce, makeKey);
        TLSStorage* d = (TLSStorage*)pthread_getspecific(tlsKey);
        if( !d )
        {
            d = new TLSStorage;
            pthread_setspecific(tlsKey, d);
        }
        return d;
    }

class TLSContainerStorage
{
    cv::Mutex mutex_;
    std::vector<TLSDataContainer*> tlsContainers_;
public:
    TLSContainerStorage() { }
    ~TLSContainerStorage()
    {
        for (size_t i = 0; i < tlsContainers_.size(); i++)
        {
            CV_DbgAssert(tlsContainers_[i] == NULL); // not all keys released
            tlsContainers_[i] = NULL;
        }
    }

    int allocateKey(TLSDataContainer* pContainer)
    {
        cv::AutoLock lock(mutex_);
        tlsContainers_.push_back(pContainer);
        return (int)tlsContainers_.size() - 1;
    }
    void releaseKey(int id, TLSDataContainer* pContainer)
    {
        cv::AutoLock lock(mutex_);
        CV_Assert(tlsContainers_[id] == pContainer);
        tlsContainers_[id] = NULL;
        // currently, we don't go into thread's TLSData and release data for this key
    }

    void destroyData(int key, void* data)
    {
        cv::AutoLock lock(mutex_);
        TLSDataContainer* k = tlsContainers_[key];
        if (!k)
            return;
        try
        {
            k->deleteDataInstance(data);
        }
        catch (...)
        {
            CV_DbgAssert(k == NULL); // Debug this!
        }
    }
};

// This is a wrapper function that will ensure 'tlsContainerStorage' is constructed on first use.
// For more information: http://www.parashift.com/c++-faq/static-init-order-on-first-use.html
static TLSContainerStorage& getTLSContainerStorage()
{
    static TLSContainerStorage *tlsContainerStorage = new TLSContainerStorage();
    return *tlsContainerStorage;
}

TLSDataContainer::TLSDataContainer()
    : key_(-1)
{
    key_ = getTLSContainerStorage().allocateKey(this);
}

TLSDataContainer::~TLSDataContainer()
{
    getTLSContainerStorage().releaseKey(key_, this);
    key_ = -1;
}

void* TLSDataContainer::getData() const
{
    CV_Assert(key_ >= 0);
    TLSStorage* tlsData = TLSStorage::get();
    void* data = tlsData->getData(key_);
    if (!data)
    {
        data = this->createDataInstance();
        CV_DbgAssert(data != NULL);
        tlsData->setData(key_, data);
    }
    return data;
}

TLSStorage::~TLSStorage()
{
    for (int i = 0; i < (int)tlsData_.size(); i++)
    {
        void*& data = tlsData_[i];
        if (data)
        {
            getTLSContainerStorage().destroyData(i, data);
            data = NULL;
        }
    }
    tlsData_.clear();
}

} // namespace cv

/* End of file. */
