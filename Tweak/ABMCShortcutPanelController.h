#import <UIKit/UIKit.h>

@interface ABMCShortcutPanelController : UIViewController
- (instancetype)initWithItems:(NSArray<NSDictionary *> *)items selection:(void (^)(NSDictionary *item))selection;
@end
