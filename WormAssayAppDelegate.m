//
//  WormAssayAppDelegate.m
//  WormAssay
//
//  Created by Chris Marcellino on 3/31/11.
//  Copyright 2011 Chris Marcellino. All rights reserved.
//

#import "WormAssayAppDelegate.h"
#import "VideoSourceDocument.h"
#import "DocumentController.h"
#import "VideoProcessorController.h"
#import "VideoProcessor.h"
#import "AssayAnalyzer.h"
#import <QTKit/QTKit.h>
#import <IOKit/pwr_mgt/IOPMLib.h>

static NSString *const IgnoreBuiltInCamerasUserDefaultsKey = @"IgnoreBuiltInCameras";
static NSString *const LoggingWindowAutosaveName = @"LoggingWindow";

@interface WormAssayAppDelegate ()

- (void)assayAnalyzerMenuItemSelected:(NSMenuItem *)sender;
- (void)loadCaptureDevices;
- (void)captureDevicesChanged;

@end

@implementation WormAssayAppDelegate

@synthesize assayAnalyzerMenu;

- (void)applicationWillFinishLaunching:(NSNotification *)notification
{
    // Register default user defaults
    NSDictionary *defaults = [[NSDictionary alloc] initWithObjectsAndKeys:
                              [NSNumber numberWithBool:YES], IgnoreBuiltInCamerasUserDefaultsKey, nil];
    [[NSUserDefaults standardUserDefaults] registerDefaults:defaults];
    [defaults release];
    
    // Create our NSDocumentController subclass first
    [[[DocumentController alloc] init] autorelease];
    
    // Create the logging window and associate it with the VideoProcessorController
    NSRect screenFrame = [[NSScreen mainScreen] visibleFrame];
    NSRect rect = screenFrame;
    rect.size.width = MIN(1000, rect.size.width);
    rect.size.height = MIN(200, rect.size.height);
    NSUInteger styleMask = NSTitledWindowMask | NSMiniaturizableWindowMask | NSResizableWindowMask | NSUtilityWindowMask;
    _loggingPanel = [[NSPanel alloc] initWithContentRect:rect styleMask:styleMask backing:NSBackingStoreBuffered defer:YES];
    [_loggingPanel setTitle:NSLocalizedString(@"Run Log", nil)];
    [_loggingPanel setFrameUsingName:LoggingWindowAutosaveName];
    [_loggingPanel setFrameAutosaveName:LoggingWindowAutosaveName];
    
    rect.origin = NSZeroPoint;
    NSScrollView *scrollView = [[NSScrollView alloc] initWithFrame:rect];
    [scrollView setBorderType:NSNoBorder];
    [scrollView setHasVerticalScroller:YES];
    [scrollView setHasHorizontalScroller:YES];
    [scrollView setAutohidesScrollers:YES];
    [scrollView setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
    NSTextView *textView = [[NSTextView alloc] initWithFrame:rect];
    [textView setEditable:NO];
    [textView setVerticallyResizable:YES];
    [textView setHorizontallyResizable:YES];
    [textView setContinuousSpellCheckingEnabled:NO];
    [textView setAllowsUndo:NO];
    [textView setAutoresizingMask:NSViewWidthSizable];
    [[textView textContainer] setWidthTracksTextView:NO];
    [[textView textContainer] setContainerSize:NSMakeSize(FLT_MAX, FLT_MAX)];
    [scrollView setDocumentView:textView];
    [_loggingPanel setContentView:scrollView];
    [_loggingPanel orderFront:self];
        
    VideoProcessorController *videoProcessorController = [VideoProcessorController sharedInstance];
    [videoProcessorController setRunLogTextView:textView];
    [videoProcessorController setRunLogScrollView:scrollView];
    
    [textView release];
    [scrollView release];
    
    // Set up analyzer menu
    NSMenu *menu = [self assayAnalyzerMenu];
    for (Class class in [videoProcessorController assayAnalyzerClasses]) {
        NSMenuItem *item = [menu addItemWithTitle:[class analyzerName] action:@selector(assayAnalyzerMenuItemSelected:) keyEquivalent:@""];
        [item setState:([class isEqual:[videoProcessorController currentAssayAnalyzerClass]] ? NSOnState : NSOffState)];
    }
    
    // Log welcome message
    NSDictionary *infoDictionary = [[NSBundle mainBundle] infoDictionary];
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSDictionary *fileAttributes = [fileManager attributesOfFileSystemForPath:[videoProcessorController runOutputFolderPath] error:nil];
    unsigned long long fileSystemSize = [[fileAttributes objectForKey:NSFileSystemSize] unsignedLongLongValue];
    unsigned long long freeSpace = [[fileAttributes objectForKey:NSFileSystemFreeSize] unsignedLongLongValue];
    double percentFree = (double)freeSpace / (double)fileSystemSize * 100.0;
    
    RunLog(@"%@ version %@ launched. Data storage has %@ (%.3g%%) free space.",
           [infoDictionary objectForKey:(id)kCFBundleNameKey], [infoDictionary objectForKey:(id)kCFBundleVersionKey], formattedDataSize(freeSpace), percentFree);
    RunLog(@"VLC can be used to view the video files recorded when assaying using a HDV or DV camera. Download it free at http://www.videolan.org/vlc/.");
}

- (void)assayAnalyzerMenuItemSelected:(NSMenuItem *)sender
{
    NSMenu *menu = [self assayAnalyzerMenu];
    VideoProcessorController *videoProcessorController = [VideoProcessorController sharedInstance];
    NSInteger selectedIndex = [menu indexOfItem:sender];
    Class class = [[videoProcessorController assayAnalyzerClasses] objectAtIndex:selectedIndex];
    [videoProcessorController setCurrentAssayAnalyzerClass:class];
    
    for (NSInteger i = 0; i < [menu numberOfItems]; i++) {
        [[menu itemAtIndex:i] setState:i == selectedIndex ? NSOnState : NSOffState];
    }
}

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification
{
    // Register for camera notifications and create windows for each camera
    NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
    [center addObserver:self selector:@selector(captureDevicesChanged) name:QTCaptureDeviceWasConnectedNotification object:nil];
    [center addObserver:self selector:@selector(captureDevicesChanged) name:QTCaptureDeviceWasDisconnectedNotification object:nil];
    
    // Register for defaults changes
    [[NSUserDefaultsController sharedUserDefaultsController] addObserver:self
                                                              forKeyPath:[@"values." stringByAppendingString:IgnoreBuiltInCamerasUserDefaultsKey]
                                                                 options:0
                                                                 context:NULL];
    
    [self loadCaptureDevices];
    
    // Prevent display and system idle sleep for the life of the application
    IOPMAssertionID assertionID;
    IOPMAssertionCreateWithName(kIOPMAssertionTypeNoDisplaySleep,
                                kIOPMAssertionLevelOn,
                                (CFStringRef)[[NSBundle mainBundle] bundleIdentifier],
                                &assertionID);
    
    // Log if there are no devices attached
    if ([[[NSDocumentController sharedDocumentController] documents] count] == 0) {
        RunLog(@"Attach a camera or use \"File… Open for Testing\" to simulate one.");
    }
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
    [self loadCaptureDevices];
}

- (void)loadCaptureDevices
{
    NSDocumentController *documentController = [NSDocumentController sharedDocumentController];
    NSMutableSet *presentUniqueIds = [[NSMutableSet alloc] init];
    
    BOOL ignoreBuiltInCameras = [[NSUserDefaults standardUserDefaults] boolForKey:IgnoreBuiltInCamerasUserDefaultsKey];
    
    // Iterate through current capture devices, creating new documents for new ones
    for (QTCaptureDevice *device in [QTCaptureDevice inputDevices]) {
        NSString *uniqueID = [device uniqueID];
        
        BOOL isBuiltInCamera = DeviceIsAppleUSBDevice(device);
        
        // Only consider devices capable of video output and that meet our built-in device criteria
        if (([device hasMediaType:QTMediaTypeVideo] || [device hasMediaType:QTMediaTypeMuxed]) && 
            (!isBuiltInCamera || !ignoreBuiltInCameras)) {
            [presentUniqueIds addObject:uniqueID];
            
            // Construct the URL for the capture device
            NSURL *url = URLForCaptureDeviceUniqueID(uniqueID);
            
            // If there is no open VideoSourceDocument document for this URL, create one
            if (![documentController documentForURL:url]) {                
                NSError *error = nil;
                [documentController openDocumentWithContentsOfURL:url display:YES error:&error];
                if (error) {
                    [[NSAlert alertWithError:error] runModal];
                }
            }
        }
    }
    
    // Iterate through current documents and remove ones that no longer correspond to current capture devices
    for (NSDocument *document in [documentController documents]) {
        NSURL *url = [document fileURL];        // not necessarily a file URL
        NSString *captureDeviceUniqueID = UniqueIDForCaptureDeviceURL(url);
        if (captureDeviceUniqueID) {
            if (![presentUniqueIds containsObject:captureDeviceUniqueID]) {
                [document close];
            }
        }
    }
    
    [presentUniqueIds release];
}

- (void)captureDevicesChanged
{
    [self performSelector:@selector(loadCaptureDevices) withObject:nil afterDelay:0.0];
}

- (BOOL)applicationShouldOpenUntitledFile:(NSApplication *)sender
{
    return NO;
}

- (BOOL)applicationShouldHandleReopen:(NSApplication *)sender hasVisibleWindows:(BOOL)flag
{
    return NO;
}

@end

NSString *formattedDataSize(unsigned long long bytes)
{
    NSString *factors[] = { (bytes == 1 ? @"byte" : @"bytes"), @"KB", @"MB", @"GB", @"TB", @"PB", @"EB", @"ZB", @"YB", nil };
    int factorIndex = 0;
    double value = bytes;
    while (value > 1024 && factors[factorIndex + 1]) {
        value /= 1024;
        factorIndex++;
    }
    return [NSString stringWithFormat:@"%.4g %@", value, factors[factorIndex]];
}
