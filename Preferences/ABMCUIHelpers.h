#import <UIKit/UIKit.h>

typedef NS_ENUM(NSInteger, ABMCApplicationKind) {
    ABMCApplicationKindAll = 0,
    ABMCApplicationKindUser,
    ABMCApplicationKindTrollStore,
    ABMCApplicationKindSystem,
};

/// Preferences-only system services. No third-party framework is loaded,
/// bundled, or injected by B2.
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
void ABMCApplyLargeIcon(UITableViewCell *cell, UIImage *image);
