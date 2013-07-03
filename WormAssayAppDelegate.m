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
#import "LoggingAndNotificationsSettingsWindowController.h"
#import <QTKit/QTKit.h>
#import <IOKit/pwr_mgt/IOPMLib.h>

static NSString *const IgnoreBuiltInCamerasUserDefaultsKey = @"IgnoreBuiltInCameras";

@interface WormAssayAppDelegate ()

- (void)assayAnalyzerMenuItemSelected:(NSMenuItem *)sender;
- (void)loadCaptureDevices;
- (void)captureDevicesChanged;
- (void)loggingAndNotificationSettingsDidClose:(NSNotification *)note;

@end

@implementation WormAssayAppDelegate

@synthesize assayAnalyzerMenu, plateOrientationMenu, runLogTextView, runLogScrollView, encodingTableView;

- (void)applicationWillFinishLaunching:(NSNotification *)notification
{
    // Register default user defaults
    NSDictionary *defaults = [[NSDictionary alloc] initWithObjectsAndKeys:
                              [NSNumber numberWithBool:YES], IgnoreBuiltInCamerasUserDefaultsKey,
                              [NSNumber numberWithBool:YES], @"ApplePersistenceIgnoreState",    // ignore resume
                              nil];
    [[NSUserDefaults standardUserDefaults] registerDefaults:defaults];
    
    // Create our NSDocumentController subclass first
    [[DocumentController alloc] init];
    
    // Set up the logging panel
    [NSBundle loadNibNamed:@"LoggingPanel" owner:self];
    VideoProcessorController *videoProcessorController = [VideoProcessorController sharedInstance];
    [videoProcessorController setRunLogTextView:runLogTextView];
    [videoProcessorController setRunLogScrollView:runLogScrollView];
    [videoProcessorController setEncodingTableView:encodingTableView];
    
    // Log welcome message
    NSBundle *mainBundle = [NSBundle mainBundle];
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSString *folder = [videoProcessorController runOutputFolderPath];
    NSDictionary *fileAttributes = nil;
    while (!fileAttributes && folder) {
        fileAttributes = [fileManager attributesOfFileSystemForPath:folder error:nil];
        if (!fileAttributes) {
            NSString *parentFolder = [folder stringByDeletingLastPathComponent];
            folder = [parentFolder isEqual:folder] ? nil : parentFolder;
        }
    }
    unsigned long long fileSystemSize = [[fileAttributes objectForKey:NSFileSystemSize] unsignedLongLongValue];
    unsigned long long freeSpace = [[fileAttributes objectForKey:NSFileSystemFreeSize] unsignedLongLongValue];
    double percentFree = (double)freeSpace / (double)fileSystemSize * 100.0;
    
    RunLog(@"%@ version %@ launched. Storage has %@ (%.3g%%) free space.",
           [mainBundle objectForInfoDictionaryKey:(id)kCFBundleNameKey],
           [mainBundle objectForInfoDictionaryKey:(id)kCFBundleVersionKey],
           formattedDataSize(freeSpace),
           percentFree);
    
    // Log that the conversion executable isn't present
    if (![[VideoProcessorController sharedInstance] supportsConversion]) {
        RunLog(@"This version of %@ was built without H.264 encoding support. "
               "Instead, VLC (http://www.videolan.org/vlc/) can be used to view the video files recorded when assaying using a HDV or DV camera. ",
               [mainBundle objectForInfoDictionaryKey:(id)kCFBundleNameKey]);
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
                                (__bridge CFStringRef)[[NSBundle mainBundle] bundleIdentifier],
                                &assertionID);
    
    // Log if there are no devices attached
    if ([[[NSDocumentController sharedDocumentController] documents] count] == 0) {
        RunLog(@"Attach a camera or use \"File… Open for Testing\" to simulate one.");
    }
}

- (void)menuNeedsUpdate:(NSMenu *)menu
{
    if (menu == [self assayAnalyzerMenu]) {
        // Populate analyzer menu
        [menu removeAllItems];
        
        VideoProcessorController *videoProcessorController = [VideoProcessorController sharedInstance];
        for (Class class in [videoProcessorController assayAnalyzerClasses]) {
            NSMenuItem *item = [menu addItemWithTitle:[class analyzerName] action:@selector(assayAnalyzerMenuItemSelected:) keyEquivalent:@""];
            [item setState:([class isEqual:[videoProcessorController currentAssayAnalyzerClass]] ? NSOnState : NSOffState)];
        }
    } else if (menu == [self plateOrientationMenu]) {
        // Set enabled flags on plate orientation menu items
        PlateOrientation plateOrientation = [[VideoProcessorController sharedInstance] plateOrientation];
        for (NSInteger i = 0; i < [menu numberOfItems]; i++) {
            NSMenuItem *item = [menu itemAtIndex:i];
            [item setState:(i == plateOrientation) ? NSOnState : NSOffState];
        }
    }
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

- (NSApplicationTerminateReply)applicationShouldTerminate:(NSApplication *)sender
{
    NSApplicationTerminateReply reply = NSTerminateNow;
    
    if ([[VideoProcessorController sharedInstance] isTracking]) {
        NSAlert *alert = [[NSAlert alloc] init];
        [alert setMessageText:NSLocalizedString(@"There is a plate read in progress.", nil)]; 
        [alert setInformativeText:NSLocalizedString(@"The current read results and video will be lost if you exit before the plate is removed.", nil)];
        [alert addButtonWithTitle:NSLocalizedString(@"Cancel", nil)];
        [alert addButtonWithTitle:NSLocalizedString(@"Quit", nil)];
        NSInteger result = [alert runModal];
        if (result == NSAlertFirstButtonReturn) {
            reply = NSTerminateCancel;
        }
    } else if ([[VideoProcessorController sharedInstance] hasConversionJobsQueuedOrRunning]) {
        NSAlert *alert = [[NSAlert alloc] init];
        [alert setMessageText:NSLocalizedString(@"Videos are currently being encoded", nil)]; 
        [alert setInformativeText:NSLocalizedString(@"Videos will remain in their original captured format if you exit before the conversion jobs are complete.", nil)];
        [alert addButtonWithTitle:NSLocalizedString(@"Cancel", nil)];
        [alert addButtonWithTitle:NSLocalizedString(@"Quit", nil)];
        NSInteger result = [alert runModal];
        if (result == NSAlertFirstButtonReturn) {
            reply = NSTerminateCancel;
        }
    }
    
    return reply;
}

- (void)applicationWillTerminate:(NSNotification *)notification
{
    [[VideoProcessorController sharedInstance] terminateAllConversionJobsForAppTerminationSynchronously];
}

- (IBAction)openRunOutputFolder:(id)sender
{
    NSString *folder = [[VideoProcessorController sharedInstance] runOutputFolderPath];
    [[NSWorkspace sharedWorkspace] openFile:folder];
}

- (IBAction)showLoggingAndNotificationSettings:(id)sender
{
    if (!_loggingAndNotificationsWindowController) {
        _loggingAndNotificationsWindowController = [[LoggingAndNotificationsSettingsWindowController alloc] init];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(loggingAndNotificationSettingsDidClose:)
                                                     name:NSWindowWillCloseNotification
                                                   object:[_loggingAndNotificationsWindowController window]];
        
    }
    [_loggingAndNotificationsWindowController showWindow:sender];
}

- (void)loggingAndNotificationSettingsDidClose:(NSNotification *)note
{
    [[NSNotificationCenter defaultCenter] removeObserver:self name:[note name] object:[note object]];
    _loggingAndNotificationsWindowController = nil;
}

- (IBAction)plateOrientationWasSelected:(id)sender
{
    PlateOrientation plateOrientation = (PlateOrientation)[[self plateOrientationMenu] indexOfItem:sender];
    [[VideoProcessorController sharedInstance] setPlateOrientation:plateOrientation];
}

- (IBAction)manuallyReportResultsAndResetProcessor:(id)sender
{
    [[VideoProcessorController sharedInstance] manuallyReportResultsForCurrentProcessor];
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
