#import <UIKit/UIKit.h>

typedef NS_ENUM(NSInteger, ABMCIconStyleMode) { ABMCIconStyleModeSize, ABMCIconStyleModeColor, ABMCIconStyleModeTextSize, ABMCIconStyleModeTextColor };
@interface ABMCIconStyleController : UITableViewController
- (instancetype)initWithMode:(ABMCIconStyleMode)mode;
@end
