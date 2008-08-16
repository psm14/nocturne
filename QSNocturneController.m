#import "QSNocturneController.h"
#include <stdio.h>
#include <IOKit/graphics/IOGraphicsLib.h>
#include <ApplicationServices/ApplicationServices.h>


void CGDisplayForceToGray();
void CGDisplaySetInvertedPolarity();
void CGSSetDebugOptions(int);

@interface NSStatusItem (QSNSStatusItemPrivate)
- (NSWindow *)_window;
@end

@implementation QSNocturneController 
+ (void)initialize {
  [[NSUserDefaults standardUserDefaults] registerDefaults:[[NSBundle mainBundle] objectForInfoDictionaryKey:@"NSUserDefaults"]];
  
  [NSColorPanel setPickerMode:NSHSBModeColorPanel];
  [self setKeys:[NSArray arrayWithObject:@"enabled"] triggerChangeNotificationsForDependentKey:@"toggleTitle"];
  [self setKeys:[NSArray arrayWithObject:@"enabled"] triggerChangeNotificationsForDependentKey:@"toggleImage"];
  [self setKeys:[NSArray arrayWithObject:@"useLightSensors"] triggerChangeNotificationsForDependentKey:@"lightMonitor"];
}
- (void)awakeFromNib {
  [prefsWindow setBackgroundColor:[NSColor whiteColor]];   
  [prefsWindow setLevel:NSFloatingWindowLevel];   
  [prefsWindow setHidesOnDeactivate:YES];   
  
  
  NSUserDefaultsController *dController = [NSUserDefaultsController sharedUserDefaultsController];
  [self bind:@"useLightSensors" toObject:dController withKeyPath:@"values.useLightSensors" options:nil];
  
}
- (BOOL)applicationShouldHandleReopen:(NSApplication *)sender hasVisibleWindows:(BOOL)flag{
  [self toggle:nil];
  return NO;
}
- (NSString *)toggleTitle {
  return enabled ? @"Switch to Day" : @"Switch to Night";  
}
- (NSImage *)toggleImage {
  return enabled ? [NSImage imageNamed:@"Sun"] : [NSImage imageNamed:@"Moon"];  
}
- (IBAction)showPreferences:(id)sender {
  [NSApp activateIgnoringOtherApps:YES];
  [prefsWindow makeKeyAndOrderFront:self];
}


- (void)applicationWillFinishLaunching:(NSNotification *)notification {
  CGTableCount sampleCount;
  CGGetDisplayTransferByTable( 0, 256, gOriginalRedTable, gOriginalGreenTable, gOriginalBlueTable, &sampleCount);
  
  originalBrightness = [self getDisplayBrightness];
  
  BOOL uiElement = [[[NSBundle mainBundle] objectForInfoDictionaryKey:@"LSUIElement"] boolValue];
  if (uiElement) {
    statusItem = [[NSStatusBar systemStatusBar] statusItemWithLength:22];
    [statusItem setMenu:statusMenu];
    [statusItem setHighlightMode:YES];
    [statusItem setImage:[NSImage imageNamed:@"NocturneMenu"]];
    [statusItem setAlternateImage:[NSImage imageNamed:@"NocturneMenuPressed"]];
    [statusItem retain];
  }
  
  NSRect screenFrame = [[NSScreen mainScreen] visibleFrame];
  NSRect windowFrame = [prefsWindow frame];
  windowFrame = NSOffsetRect(windowFrame, NSMaxX(screenFrame) - NSMaxX(windowFrame) - 20, NSMaxY(screenFrame) - NSMaxY(windowFrame) - 20);
  [prefsWindow setFrame:windowFrame display:YES animate:YES ];
  if (overlayWindows == NULL) {
    overlayWindows = [[NSMutableArray alloc] init];
  }
  if (desktopWindows == NULL) {
    desktopWindows = [[NSMutableArray alloc] init];
  }
}

- (void)applicationDidChangeScreenParameters:(NSNotification *)aNotification{
	if ([overlayWindows count] != 0) {
		[self setupOverlays];
	}
	[self updateGamma];
	if ([desktopWindows count] != 0) {
		[self setDesktopHidden:YES];
	}
}


- (void)applicationDidFinishLaunching:(NSNotification *)notification {
  
  NSNumber *enabledValue = [[NSUserDefaults standardUserDefaults] objectForKey:@"enabled"];  
  [self setEnabled: enabledValue ? [enabledValue boolValue] : YES];
  
  NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
  NSDate *lastLaunch = [defaults objectForKey:@"lastLaunchDate"];
  if (!lastLaunch) {
    [self showPreferences:self];
    [defaults setValue:[NSDate date] forKey:@"lastLaunchDate"];
  }
  
  
}
- (BOOL)canUseSensors {
  return [QSLMUMonitor hasSensors];
}
- (BOOL)useLightSensors {
  return monitor != nil; 
}
- (void)setUseLightSensors:(BOOL)value {
  if (value) {
    if (!monitor) {
      monitor = [[QSLMUMonitor alloc] init];
      [monitor setDelegate:self];
      [monitor setMonitorSensors:YES];
      NSUserDefaultsController *dController = [NSUserDefaultsController sharedUserDefaultsController];
      
      [monitor bind:@"lowerBound" toObject:dController withKeyPath:@"values.lowerLightValue" options:nil];
      [monitor bind:@"upperBound" toObject:dController withKeyPath:@"values.upperLightValue" options:nil];      
    }
  } else {
    [monitor unbind:@"lowerBound"];
    [monitor unbind:@"upperBound"];
    
    [monitor setMonitorSensors:NO];
    [monitor release];
    monitor = nil;
  }
}

- (QSLMUMonitor *)lightMonitor {
  return monitor;
}

- (void)monitor:(QSLMUMonitor *)monitor passedLowerBound:(SInt32)lowerBound withValue:(SInt32)value {
  [self setEnabled:YES];  
}

- (void)monitor:(QSLMUMonitor *)monitor passedUpperBound:(SInt32)upperBound withValue:(SInt32)value {
  [self setEnabled:NO];  
}





- (id)valueForUndefinedKey:(NSString *)key{
  return nil;
}
- (void)toggle {
  [self setEnabled:![self enabled]];
}
- (IBAction)toggle:(id)sender {
  [self performSelector:@selector(toggle) withObject:nil afterDelay:0.0];
}



- (void)applicationWillTerminate:(NSNotification *)notification{
  [[NSUserDefaults standardUserDefaults] setBool:enabled forKey:@"enabled"];
  shouldQuit = YES;
  [self setEnabled:NO];
}


- (void)setDesktopHidden:(BOOL)hidden {
	NSWindow *desktopWindow;
	while ([desktopWindows count] > 0) {
		desktopWindow = [desktopWindows lastObject];
		[desktopWindow release];
		desktopWindow = nil;
		[desktopWindows removeLastObject];
	}
	if (hidden) {
		for (int i = 0; i < [[NSScreen screens] count]; ++i) {
			desktopWindow = [[NSWindow alloc] initWithContentRect:[[[NSScreen screens] objectAtIndex:i] frame]
                                                  styleMask:NSBorderlessWindowMask
                                                    backing:NSBackingStoreBuffered
                                                      defer:NO];
			[desktopWindow setHidesOnDeactivate:NO];
			[desktopWindow setCanHide:NO];
			[desktopWindow setIgnoresMouseEvents:YES];
			[desktopWindow setLevel:kCGDesktopWindowLevel];
			[desktopWindow setBackgroundColor:[NSColor colorWithDeviceWhite:0.9 alpha:1.0]];
			[desktopWindow orderFront:nil];
			
			[desktopWindows addObject:desktopWindow];
		}
	}
}




- (float)getDisplayBrightness {
  CGDisplayErr      dErr;
  io_service_t      service;
  CGDirectDisplayID targetDisplay;
  
  CFStringRef key = CFSTR(kIODisplayBrightnessKey);
  
  targetDisplay = CGMainDisplayID();
  service = CGDisplayIOServicePort(targetDisplay);
  
  float brightness = 1.0;
  dErr = IODisplayGetFloatParameter(service, kNilOptions, key, &brightness);
  
  if (dErr == kIOReturnSuccess) {
    return brightness;
  } else {
    return 1.0;
  }
}

- (void)setDisplayBrightness:(float)brightness {
  CGDisplayErr      dErr;
  io_service_t      service;
  CGDirectDisplayID targetDisplay;
  
  CFStringRef key = CFSTR(kIODisplayBrightnessKey);
  
  targetDisplay = CGMainDisplayID();
  service = CGDisplayIOServicePort(targetDisplay);
  
  if (brightness != HUGE_VALF) { // set the brightness, if requested
    dErr = IODisplaySetFloatParameter(service, kNilOptions, key, brightness);
  }
}


#define PROGNAME "display-brightness"
- (void)setBrightness:(float)brightness {
  BOOL adjust = [[NSUserDefaults standardUserDefaults] boolForKey:@"adjustBrightness"];
  if (!adjust) brightness = originalBrightness;
  if (brightness == 0.0) brightness = 0.005;
  [self setDisplayBrightness:brightness];
}

- (void)setAdjustBrightness:(BOOL)value {
  float brightness = [[NSUserDefaults standardUserDefaults] floatForKey:@"brightness"];
  [self setBrightness:brightness];
}

- (IBAction)revertGamma:(id)sender {
  [[NSUserDefaults standardUserDefaults] removeObjectForKey:@"whiteColor"];
  [[NSUserDefaults standardUserDefaults] removeObjectForKey:@"blackColor"];
}
- (void)restoreGamma {
  CGDisplayRestoreColorSyncSettings(); 
}

- (void)setGammaEnabled:(BOOL)enabled {
  [self updateGamma];
}

- (void)updateGamma {
  if (![[NSUserDefaults standardUserDefaults] boolForKey:@"gammaEnabled"] || !(whiteColor || blackColor)) {
    [self restoreGamma];
    return;
  }
  
  NSColor *whitepoint = [whiteColor colorUsingColorSpaceName:NSCalibratedRGBColorSpace];
  NSColor *blackpoint = [blackColor colorUsingColorSpaceName:NSCalibratedRGBColorSpace];
  
  CGGammaValue redTable[ 256 ];
  CGGammaValue greenTable[ 256 ];
  CGGammaValue blueTable[ 256 ];
  CGDisplayErr cgErr;
  
  float maxR = whitepoint ? [whitepoint redComponent] : 1.0;
  float maxG = whitepoint ? [whitepoint greenComponent] : 1.0;
  float maxB = whitepoint ? [whitepoint blueComponent] : 1.0;
  
  float minR = blackpoint ? [blackpoint redComponent] : 0.0;
  float minG = blackpoint ? [blackpoint greenComponent] : 0.0;
  float minB = blackpoint ? [blackpoint blueComponent] : 0.0;
  
  
  if (fabs(maxR-minR) + fabs(maxG-minG) + fabs(maxB-minB) < 0.1) {
    //NSLog(@"adjusting colors to protect %f", fabs(maxR-minR) + fabs(maxG-minG) + fabs(maxB-minB));
    maxR += 0.1;
    maxB += 0.1;
    maxG += 0.1;
    minR -= 0.1;
    minB -= 0.1;
    minG -= 0.1;
  }
  
  for (int i = 0; i < 256 ; i++) {
    redTable[ i ] =  minR +  (maxR - minR) * gOriginalRedTable[ i ];
    greenTable[ i ] = minG + (maxG - minG) * gOriginalGreenTable[ i ];
    blueTable[ i ] = minB + (maxB - minG) * gOriginalBlueTable[ i ];
  }
  
  //get the number of displays
  CGDisplayCount numDisplays;
  CGGetActiveDisplayList(0, NULL, &numDisplays);
  
  //set the gamma on each display
  CGDirectDisplayID displays[numDisplays];
  CGGetActiveDisplayList(numDisplays, displays, NULL);
  for (int i = 0; i < 10; ++i) {
    cgErr = CGSetDisplayTransferByTable(displays[i], 256, redTable, greenTable, blueTable);
  }
}

- (void)setInverted:(BOOL)value{
  CGDisplaySetInvertedPolarity(value);
  //  NSRect screenFrame = [[NSScreen mainScreen] frame];
  //  NSRect cornerFrame1 = NSMakeRect(NSMinX(screenFrame), NSMaxY(screenFrame) - 8, 8, 8);
  //  NSRect cornerFrame2 = NSMakeRect(NSMaxX(screenFrame) - 8, NSMaxY(screenFrame) - 8, 8, 8);
  //  
  //  if (value) {
  //    NSWindow *cornerWindow1 = [[NSWindow alloc] initWithContentRect:cornerFrame1
  //                                                          styleMask:NSBorderlessWindowMask
  //                                                            backing:NSBackingStoreBuffered
  //                                                              defer:NO];
  //    NSWindow *cornerWindow2 = [[NSWindow alloc] initWithContentRect:cornerFrame2
  //                                                          styleMask:NSBorderlessWindowMask
  //                                                            backing:NSBackingStoreBuffered
  //                                                              defer:NO];
  //    [cornerWindow1 orderFront:nil];
  //    [cornerWindow1 setLevel:NSStatusWindowLevel+1];
  //    [cornerWindow2 orderFront:nil];
  //    [cornerWindow2 setLevel:NSStatusWindowLevel+1];
  //
  //  }
}

- (void)setMonochrome:(BOOL)value{
  CGDisplayForceToGray(value);  
}

- (void)setHueAngle:(float)hue {
	if (hue == 0) {
		[self removeOverlays];
	} else {
		[self setupOverlays];
	}    
}

- (void)removeOverlays{
	while([overlayWindows count] > 0) {
		QSCIFilterWindow *overlayWindow = [overlayWindows lastObject];
		[overlayWindow release];
		[overlayWindows removeLastObject];
		overlayWindow = nil;
	}
}

- (void)setupOverlays{
	for (int i = 0; i < [[NSScreen screens] count]; ++i) {
		QSCIFilterWindow *overlayWindow;
		if ([overlayWindows count] <= i) {
			overlayWindow = [[QSCIFilterWindow alloc] init];
			[overlayWindow setLevel:kCGMaximumWindowLevel];
			[overlayWindow setFilter:@"CIHueAdjust"];
			[overlayWindow setFilterValues:[NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithFloat:M_PI], @"inputAngle",nil]];
			[overlayWindow orderFront:nil];
      
      //OSX 10.4 compatible code that puts the overlays on all spaces
      // replacement for the line commented out below
      if ([overlayWindow respondsToSelector:@selector(setCollectionBehavior:)]) {
        [overlayWindow setCollectionBehavior:1];
      }
      //This line is OSX 10.5 specific. Comment out this line to compile for 10.4
      //[overlayWindow setCollectionBehavior:NSWindowCollectionBehaviorCanJoinAllSpaces];
			
			[overlayWindows addObject:overlayWindow];
		} else {
			overlayWindow = [overlayWindows objectAtIndex:i];
		}
		[overlayWindow setFrame:[[[NSScreen screens] objectAtIndex:i] frame] display:NO];
	}
	while ([overlayWindows count] > [[NSScreen screens] count]) {
		QSCIFilterWindow *overlayWindow = [overlayWindows lastObject];
		[overlayWindow release];
		[overlayWindows removeLastObject];
		overlayWindow = nil;
	}
}	

- (void)setHueCorrect:(BOOL)value{
  // if (![[dController valueForKeyPath: @"values.inverted"] boolValue]) value = NO;
  [self setHueAngle: value ? M_PI : 0];
}


#define kCGSDebugOptionNormal 0
#define kCGSDebugOptionNoShadows 16384
- (void)setShadowsHidden:(BOOL)value{
  CGSSetDebugOptions(value ? kCGSDebugOptionNoShadows : kCGSDebugOptionNormal);
}


- (BOOL)enabled {
  return enabled;
}

- (void)applyEnabled:(BOOL)value {
  
  if (statusItem) [[statusItem _window] display];
  
  if (enabled) {
    
    originalBrightness = [self getDisplayBrightness];
    
    NSUserDefaultsController *dController = [NSUserDefaultsController sharedUserDefaultsController];
    
    [self bind:@"inverted" toObject:dController withKeyPath:@"values.inverted" options:nil];
    [self bind:@"hueCorrect" toObject:dController withKeyPath:@"values.hueCorrect" options:nil];
    [self bind:@"shadowsHidden" toObject:dController withKeyPath:@"values.shadowsHidden" options:nil];
    [self bind:@"desktopHidden" toObject:dController withKeyPath:@"values.desktopHidden" options:nil];
    [self bind:@"monochrome" toObject:dController withKeyPath:@"values.monochrome" options:nil];
    [self bind:@"gammaEnabled" toObject:dController withKeyPath:@"values.gammaEnabled" options:nil];
    [self bind:@"brightness" toObject:dController withKeyPath:@"values.brightness" options:nil];
    [self bind:@"adjustBrightness" toObject:dController withKeyPath:@"values.adjustBrightness" options:nil];
    [self bind:@"whiteColor" toObject:dController withKeyPath:@"values.whiteColor"
       options:[NSDictionary dictionaryWithObject:NSUnarchiveFromDataTransformerName forKey:NSValueTransformerNameBindingOption]];
    [self bind:@"blackColor" toObject:dController withKeyPath:@"values.blackColor"
       options:[NSDictionary dictionaryWithObject:NSUnarchiveFromDataTransformerName forKey:NSValueTransformerNameBindingOption]];
    
  } else { 
    [self unbind:@"inverted"];
    [self unbind:@"hueCorrect"];
    [self unbind:@"shadowsHidden"];
    [self unbind:@"desktopHidden"];
    [self unbind:@"monochrome"];
    [self unbind:@"gammaEnabled"];
    [self unbind:@"adjustBrightness"];
    [self unbind:@"brightness"];
    [self unbind:@"whiteColor"];
    [self unbind:@"blackColor"];
    
    CGDisplayRestoreColorSyncSettings();
    [self setInverted:NO];
    [self setHueCorrect:NO];
    [self setMonochrome:NO];
    [self setShadowsHidden:NO];
    [self setDesktopHidden:NO];
    [self setDisplayBrightness:MAX(0.005, originalBrightness)];
  }
  if (shouldQuit) {
    [prefsWindow orderOut:nil];
    [[NSStatusBar systemStatusBar] removeStatusItem:statusItem];
    statusItem = nil;
  }
  [self willChangeValueForKey:@"toggleTitle"];
  [self didChangeValueForKey:@"toggleTitle"];
  [self willChangeValueForKey:@"toggleImage"];
  [self didChangeValueForKey:@"toggleImage"];
  [prefsWindow display];
}

- (void)applyEnabled:(BOOL)value withFade:(BOOL)fade {
  if (!fade) {
    [self applyEnabled:value]; 
  } else { 
    
    float fadeout = enabled ? 0.5 : 1.0;
    float fadein = enabled ? 0.5 : 1.0;
    CGDisplayFadeReservationToken token;
    CGDisplayErr err;
    err = CGAcquireDisplayFadeReservation (3.0, &token); // 1
    if (err == kCGErrorSuccess) {
      err = CGDisplayFade (token, 0.25, kCGDisplayBlendNormal,
                           kCGDisplayBlendSolidColor, fadeout, fadeout, fadeout, true); // 2
      // Your code to change the display mode and
      // set the full-screen context.
      @try {
        [self applyEnabled:value];
        //   [prefsWindow makeKeyAndOrderFront:nil];  
      }
      @catch (NSException *e) {
        NSLog(@"Error %@", e); 
      }
      
      err = CGDisplayFade (token, 0.75, kCGDisplayBlendSolidColor,
                           kCGDisplayBlendNormal, fadein, fadein, fadein, true); // 3
      err = CGReleaseDisplayFadeReservation (token); // 4
    }
    
  }
}

//CGDisplayFadeReservationToken token;
//CGDisplayErr err;
//
//err = CGAcquireDisplayFadeReservation (2.0, &token); // 1
//if (err == kCGErrorSuccess){
//  err = CGDisplayFade (token, 0.5, kCGDisplayBlendNormal,
//                       kCGDisplayBlendSolidColor, 1.0, 1.0, 1.0, true); // 2
//                                                                        // Your code to change the display mode and
//                                                                        // set the full-screen context.
//  
//  [self setEnabled:NO];
//  
//  [[NSApp windows] makeObjectsPerformSelector:@selector(orderOut:) withObject:nil];
//  
//  err = CGDisplayFade (token, 1.0, kCGDisplayBlendSolidColor,
//                       kCGDisplayBlendNormal, 1.0, 1.0, 1.0, true); // 3
//  err = CGReleaseDisplayFadeReservation (token); // 4
//}





- (void)setEnabled:(BOOL)value {
  if (enabled != value) {
    enabled = value;
    [self applyEnabled:value withFade:YES];
  }
}

- (NSColor *)whiteColor {
  return [[whiteColor retain] autorelease];
}

- (void)setWhiteColor:(NSColor *)value {
  if (whiteColor != value) {
    [whiteColor release];
    whiteColor = [value copy];
    [self updateGamma];
  }
}

- (NSColor *)blackColor {
  return [[blackColor retain] autorelease];
}

- (void)setBlackColor:(NSColor *)value {
  if (blackColor != value) {
    [blackColor release];
    blackColor = [value copy];
    [self updateGamma];
    
  }
}

@end


