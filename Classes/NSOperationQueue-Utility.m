//
//  NSOperationQueue-Utility.m
//  WormAssay
//
//  Created by Chris Marcellino on 12/21/20.
//  Copyright 2020 Chris Marcellino. All rights reserved.
//

#import "NSOperationQueue-Utility.h"

@implementation NSOperationQueue (Utility)

+ (NSOperationQueue *)sharedGlobalQueue
{
    static dispatch_once_t pred = 0;
    static NSOperationQueue *sharedInstance = nil;
    dispatch_once(&pred, ^{
        sharedInstance = [[NSOperationQueue alloc] init];
        [sharedInstance setUnderlyingQueue:dispatch_queue_create(NULL, DISPATCH_QUEUE_CONCURRENT)];
    });
    return sharedInstance;
}

+ (void)addOperationToGlobalQueueWithBlock:(void (^)(void))block
{
    [[self sharedGlobalQueue] addOperationWithBlock:block];
}

+ (void)addOperationWithDelay:(NSTimeInterval)delay toGlobalQueueForBlock:(void (^)(void))block
{
    [[self sharedGlobalQueue] addOperationWithDelay:delay forBlock:block];
}

- (void)addOperationWithDelay:(NSTimeInterval)delay forBlock:(void (^)(void))block
{
    dispatch_queue_t queue = [self underlyingQueue];
    if (!queue && [self isEqual:[NSOperationQueue mainQueue]]) {
        queue = dispatch_get_main_queue();
    }
    NSAssert(queue, @"no underlying queue was set");
    dispatch_time_t dispatchTime = dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC));
    dispatch_after(dispatchTime, queue, block);
}

+ (void)addOperationsInParallelWithInstances:(NSUInteger)iterations
                       onGlobalQueueForBlock:(NS_NOESCAPE void (^)(NSUInteger i, id criticalSection))block
{
    id criticalSectionMutex = [[NSObject alloc] init];
    dispatch_apply(iterations, DISPATCH_APPLY_AUTO, ^(size_t i) {
        block(i, criticalSectionMutex);
    });
}

@end
