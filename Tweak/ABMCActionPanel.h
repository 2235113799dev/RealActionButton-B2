#import <Foundation/Foundation.h>

@class ABMCActionExecutor;

/// SpringBoard-local, UIKit-only multi-action picker. It never loads or
/// embeds third-party code and uses no private shortcut-folder presentation.
@interface ABMCActionPanel : NSObject
+ (instancetype)sharedPanel;
- (void)showActions:(NSArray<NSString *> *)actions executor:(ABMCActionExecutor *)executor;
@end
