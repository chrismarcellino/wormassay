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
#import "DeckLinkCaptureDevice.h"
#import "LoggingAndNotificationsSettingsWindowController.h"
#import <IOKit/pwr_mgt/IOPMLib.h>

static NSString *const IgnoreBuiltInCamerasUserDefaultsKey = @"IgnoreBuiltInCameras";
static NSString *const UseBlackmagicDeckLinkDriverDefaultsKey = @"UseBlackmagicDeckLinkDriver";


@implementation WormAssayAppDelegate

@synthesize assayAnalyzerMenu, plateOrientationMenu, runLogTextView, runLogScrollView;

- (void)applicationWillFinishLaunching:(NSNotification *)notification
{
    // Register default user defaults
    NSDictionary *defaults = [[NSDictionary alloc] initWithObjectsAndKeys:
                              [NSNumber numberWithBool:YES], IgnoreBuiltInCamerasUserDefaultsKey,
                              [NSNumber numberWithBool:YES], UseBlackmagicDeckLinkDriverDefaultsKey,
                              [NSNumber numberWithBool:YES], @"ApplePersistenceIgnoreState",    // prevent 10.7+ style window resuming
                              nil];
    [[NSUserDefaults standardUserDefaults] registerDefaults:defaults];
    
    // Create our NSDocumentController subclass first
    [[DocumentController alloc] init];
    
    // Set up the logging panel
    NSArray *topLevelObjects = nil;
    [[NSBundle mainBundle] loadNibNamed:@"LoggingPanel" owner:self topLevelObjects:&topLevelObjects];
    _loggingPanelTopLevelObjects = topLevelObjects;
    VideoProcessorController *videoProcessorController = [VideoProcessorController sharedInstance];
    [videoProcessorController setRunLogTextView:runLogTextView];
    [videoProcessorController setRunLogScrollView:runLogScrollView];
    
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
    
    RunLog(@"%@ version %@ launched. Storage has %@ (%.3g%%) free space. Mac OS %@",
           [mainBundle objectForInfoDictionaryKey:(id)kCFBundleNameKey],
           [mainBundle objectForInfoDictionaryKey:(id)kCFBundleVersionKey],
           formattedDataSize(freeSpace),
           percentFree,
           [[NSProcessInfo processInfo] operatingSystemVersionString]);
    
    if ([DeckLinkCaptureDevice isDriverInstalled]) {
        RunLog(@"Blackmagic DeckLink API version %@ installed", [DeckLinkCaptureDevice deckLinkSystemVersion]);
    }
    
    RunLog(@"Important: for best results set camera to 1080p and 24-30 fps, "
           "with image stabilization OFF and Instant Autofocus OFF (normal AF/TTL is optional.)");
}

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification
{
    // Register for camera notifications and create windows for each camera
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(captureDevicesChanged)
                                                 name:CaptureDeviceWasConnectedOrDisconnectedNotification
                                               object:nil];
    
    // Register for defaults changes
    NSUserDefaultsController *defaultsController = [NSUserDefaultsController sharedUserDefaultsController];
    [defaultsController addObserver:self
                         forKeyPath:[@"values." stringByAppendingString:IgnoreBuiltInCamerasUserDefaultsKey]
                            options:0
                            context:NULL];
    [defaultsController addObserver:self
                         forKeyPath:[@"values." stringByAppendingString:UseBlackmagicDeckLinkDriverDefaultsKey]
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

// used by menu item bindings
- (BOOL)isBlackmagicDeckLinkDriverInstalled
{
#ifdef WORMASSAY_DEBUG
    return YES;
#endif
    
    return [DeckLinkCaptureDevice isDriverInstalled];
}

- (void)loadCaptureDevices
{
    NSDocumentController *documentController = [NSDocumentController sharedDocumentController];
    
    // Get currently attached capture devices
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    BOOL ignoreBuiltInCameras = [defaults boolForKey:IgnoreBuiltInCamerasUserDefaultsKey];
    BOOL useBlackmagicDeckLinkDriver = [defaults boolForKey:UseBlackmagicDeckLinkDriverDefaultsKey];
    NSArray *deviceURLs = [VideoSourceDocument cameraDeviceURLsIgnoringBuiltInCamera:ignoreBuiltInCameras
                                                         useBlackmagicDeckLinkDriver:useBlackmagicDeckLinkDriver];
    
    // Iterate through current capture devices, creating new documents for new ones
    for (NSURL *deviceURL in deviceURLs) {
        // If there is no open VideoSourceDocument document for this URL, create one
        if (![documentController documentForURL:deviceURL]) {
            NSError *error = nil;
            [documentController openDocumentWithContentsOfURL:deviceURL display:YES error:&error];
            if (error) {
                [[NSAlert alertWithError:error] runModal];
            }
        }
    }

    // Iterate through current documents and remove ones that no longer correspond to current capture devices
    for (NSDocument *document in [documentController documents]) {
        NSURL *url = [document fileURL];        // not necessarily a file URL
        if (![deviceURLs containsObject:url]) {
            [document close];
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
    } else if ([[VideoProcessorController sharedInstance] hasEncodingJobsRunning]) {
        NSAlert *alert = [[NSAlert alloc] init];
        [alert setMessageText:NSLocalizedString(@"Videos are currently being encoded", nil)]; 
        [alert setInformativeText:NSLocalizedString(@"Videos will not be saved if you exit before encoding is complete. The results data will not be affected.", nil)];
        [alert addButtonWithTitle:NSLocalizedString(@"Cancel", nil)];
        [alert addButtonWithTitle:NSLocalizedString(@"Quit", nil)];
        NSInteger result = [alert runModal];
        if (result == NSAlertFirstButtonReturn) {
            reply = NSTerminateCancel;
        }
    }
    
    return reply;
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
