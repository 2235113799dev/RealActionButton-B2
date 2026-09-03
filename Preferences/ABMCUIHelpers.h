#import <UIKit/UIKit.h>

/// AltList is loaded only inside Preferences when already installed.
/// No third-party dylib is bundled or injected by this package.
NSArray *ABMCAltListUserApplications(void);
NSString *ABMCBundleIdentifierForApplication(id application);
NSString *ABMCDisplayNameForApplication(id application);
UIImage *ABMCIconImageForBundleID(NSString *bundleID);
UIImage *ABMCIconImageForProxy(id application);
UIImage *ABMCIconImage(NSString *token);
UIImage *ABMCTintedIcon(NSString *token, UIColor *color);
NSString *ABMCInferLinkIcon(NSString *urlString);
NSString *ABMCApplicationName(NSString *bundleID);
