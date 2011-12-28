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
        [menu addItemWithTitle:[class analyzerName] action:@selector(assayAnalyzerMenuItemSelected:) keyEquivalent:@""];
    }
    
    // Log welcome message
    NSDictionary *infoDictionary = [[NSBundle mainBundle] infoDictionary];
    RunLog(@"%@ version %@ launched.", [infoDictionary objectForKey:(id)kCFBundleNameKey], [infoDictionary objectForKey:(id)kCFBundleVersionKey]);
}

- (void)assayAnalyzerMenuItemSelected:(NSMenuItem *)sender
{
    VideoProcessorController *videoProcessorController = [VideoProcessorController sharedInstance];
    NSUInteger index = [[self assayAnalyzerMenu] indexOfItem:sender];
    Class class = [[videoProcessorController assayAnalyzerClasses] objectAtIndex:index];
    [videoProcessorController setAssayAnalyzerClass:class];
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
