//
//  DeckLinkCaptureDevice.mm
//  WormAssay
//
//  Created by Chris Marcellino on 10/16/13.
//  Copyright (c) 2013 Chris Marcellino. All rights reserved.
//

#import "DeckLinkCaptureDevice.h"
#import "DeckLinkAPI.h"

@implementation DeckLinkCaptureDevice

+ (BOOL)isDriverInstalled
{
    BOOL installed = NO;
    
	IDeckLinkIterator *deckLinkIterator = CreateDeckLinkIteratorInstance();
    if (deckLinkIterator) {
        installed = YES;
        deckLinkIterator->Release();
    }
    
    return installed;
}

+ (NSString *)deckLinkSystemVersion
{
    NSString *systemVersion = nil;
    
    IDeckLinkAPIInformation *apiInfo = CreateDeckLinkAPIInformationInstance();
    if (apiInfo) {
        CFStringRef retainedString = NULL;
        apiInfo->GetString(BMDDeckLinkAPIVersion, &retainedString);   // this returns a +1 retained string
        if (retainedString) {
            systemVersion = [(__bridge id)retainedString copy];
            CFRelease(retainedString);
        }
        apiInfo->Release();
    }
    
    return systemVersion;
}

+ (NSArray *)getDeckLinkInputNames
{
  /*  NSMutableArray *names = [[NSMutableArray alloc] init];
	
	// Create an iterator
	IDeckLinkIterator *deckLinkIterator = CreateDeckLinkIteratorInstance();
	if (deckLinkIterator) {
        // List all DeckLink devices
        IDeckLink* deckLink = NULL;
        while (deckLinkIterator->Next(&deckLink) == S_OK) {
            // Get the name of this device
            CFStringRef	cfStrName = NULL;
            if (deviceList[deviceIndex]->GetDisplayName(&cfStrName) == S_OK)
            {
                [nameList addObject:(NSString *)cfStrName];
                CFRelease(cfStrName);
            }
        }
    }
    
    if (deckLinkIterator) {
		deckLinkIterator->Release();
		deckLinkIterator = NULL;
	}

    
    
    
    NSMutableArray*		nameList = [NSMutableArray array];
	int					deviceIndex = 0;
	
	while (deviceIndex < deviceList.size())
	{
		CFStringRef	cfStrName;
		
		// Get the name of this device
		if (deviceList[deviceIndex]->GetDisplayName(&cfStrName) == S_OK)
		{
			[nameList addObject:(NSString *)cfStrName];
			CFRelease(cfStrName);
		}
		else
		{
			[nameList addObject:@"DeckLink"];
		}
        
		deviceIndex++;
	}
	
	return nameList;

    
    */
    return nil;
    
    
    
}

/*- (id)initSourceWithName:(NSString *)name frameHandler:(void (^)(void ))frameHandler
{
    
}*/

- (void)close
{
    
}

- (NSString *)uniqueID
{
    return @"123234234234";//xx fix me
}

@end

