#import <UIKit/UIKit.h>

typedef NS_ENUM(NSInteger, ABMCApplicationKind) {
    ABMCApplicationKindAll = 0,
    ABMCApplicationKindUser,
    ABMCApplicationKindTrollStore,
    ABMCApplicationKindSystem,
};

/// B2-owned Preferences-only enumeration, modeled on AltList's public source.
/// It does not load, bundle, or inject any third-party library.
NSArray *ABMCInstalledApplications(void);
ABMCApplicationKind ABMCApplicationKindForProxy(id application);
NSString *ABMCBundleIdentifierForApplication(id application);
NSString *ABMCDisplayNameForApplication(id application);
UIImage *ABMCIconImageForBundleID(NSString *bundleID);
UIImage *ABMCIconImageForProxy(id application);
UIImage *ABMCIconImage(NSString *token);
UIImage *ABMCTintedIcon(NSString *token, UIColor *color);
NSString *ABMCInferLinkIcon(NSString *urlString);
NSString *ABMCApplicationName(NSString *bundleID);
