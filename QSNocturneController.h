/* QSNocturneController */

#import <Cocoa/Cocoa.h>
#import "CGSPrivate.h"

#import "QSCIFilterWindow.h"
#import "QSLMUMonitor.h"

@interface QSNocturneController : NSObject
{
  CGGammaValue gOriginalRedTable[ 256 ];
  CGGammaValue gOriginalGreenTable[ 256 ];
  CGGammaValue gOriginalBlueTable[ 256 ];
  NSMutableArray *desktopWindows;
  NSMutableArray *overlayWindows;
  IBOutlet NSWindow *prefsWindow;
  IBOutlet NSMenu *statusMenu;
  BOOL shouldQuit;
  
  BOOL enabled;
  
  NSColor *whiteColor;
  NSColor *blackColor;
  NSStatusItem *statusItem;
  float originalBrightness;
  QSLMUMonitor *monitor;
}
- (IBAction)toggle:(id)sender;

- (void)setDesktopHidden:(BOOL)hidden;

- (IBAction)showPreferences:(id)sender;
- (BOOL)enabled;
- (void)setEnabled:(BOOL)value;

- (NSColor *)whiteColor;
- (void)setWhiteColor:(NSColor *)value;

- (NSColor *)blackColor;
- (void)setBlackColor:(NSColor *)value;

- (void)updateGamma;

- (float)getDisplayBrightness;
- (IBAction)revertGamma:(id)sender;

- (QSLMUMonitor *)lightMonitor;

- (void)removeOverlays;
- (void)setupOverlays;

@end
