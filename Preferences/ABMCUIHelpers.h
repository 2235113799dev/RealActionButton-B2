#import <UIKit/UIKit.h>

UIImage *ABMCIconImage(NSString *token);
UIImage *ABMCIconImageForProxy(id proxy);
UIImage *ABMCIconImageForBundleID(NSString *bundleID);
UIImage *ABMCTintedIcon(NSString *token, UIColor *color);
NSString *ABMCInferLinkIcon(NSString *urlString);
NSString *ABMCApplicationName(NSString *bundleID);
BOOL ABMCIsAllowedStoreApplicationProxy(id app);
NSDictionary *ABMCAppListApplications(NSArray **sortedIdentifiers);
NSString *ABMCAppListDisplayName(NSString *bundleID);
UIImage *ABMCAppListIcon(NSString *bundleID, NSUInteger size);
