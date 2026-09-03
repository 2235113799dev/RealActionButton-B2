#import <UIKit/UIKit.h>

UIImage *ABMCIconImage(NSString *token);
UIImage *ABMCTintedIcon(NSString *token, UIColor *color);
NSString *ABMCInferLinkIcon(NSString *urlString);
NSString *ABMCApplicationName(NSString *bundleID);
BOOL ABMCIsAllowedStoreApplicationProxy(id app);
