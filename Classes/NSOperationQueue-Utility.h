//
//  NSOperationQueue-Utility.h
//  WormAssay
//
//  Created by Chris Marcellino on 12/21/20.
//  Copyright 2020 Chris Marcellino. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface NSOperationQueue (Utility)

+ (void)addOperationToGlobalQueueWithBlock:(void (^)(void))block;
+ (void)addOperationWithDelay:(NSTimeInterval)delay toGlobalQueueForBlock:(void (^)(void))block;

// this convenience requires an underlying queue to have been previously set given the lack of another option currently
// as it is implemented with dispatch_after()
- (void)addOperationWithDelay:(NSTimeInterval)delay forBlock:(void (^)(void))block;

// Runs 'count' instances of the work block in parallel to the extent possible, each with an i which is unique in the
// set [0,count-1]. The second argument in the block is an object to @synchronize on during the critical section (i.e.
// merge or reduce step) of the block, and is shared by all instances. Its use is not required.
+ (void)addOperationsInParallelWithInstances:(NSUInteger)iterations
                       onGlobalQueueForBlock:(NS_NOESCAPE void (^)(NSUInteger i, id criticalSection))block;

@end
