#import "ABMCActionListController.h"
#import "ABMCApplicationListController.h"
#import "ABMCShortcutListController.h"
#import "ABMCLinkListController.h"
#import <Preferences/PSSpecifier.h>

#define ABMCDomain @"com.huynguyen.actionbuttonmulticlick"
#define ABMCChanged @"com.huynguyen.actionbuttonmulticlick/prefsChanged"

typedef struct { NSString *actionID; NSString *title; } ABMCAction;
static const ABMCAction kActions[] = {
    {@"default", @"系统默认"}, {@"flashlight", @"手电筒"}, {@"camera", @"相机"},
    {@"silent", @"静音切换"}, {@"screenshot", @"截屏"}, {@"lock", @"锁屏"},
    {@"respring", @"重启界面"}, {@"wechatScan", @"微信扫码"},
    {@"wechatPay", @"微信付款码"}, {@"alipayScan", @"支付宝扫码"},
    {@"alipayPay", @"支付宝付款码"}, {@"none", @"无操作"}
};

@implementation ABMCActionListController {
    NSString *_preferenceKey;
    NSString *_defaultValue;
    NSString *_currentValue;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    PSSpecifier *parent = [self specifier];
    _preferenceKey = [[parent propertyForKey:@"key"] copy];
    _defaultValue = [[parent propertyForKey:@"default"] copy];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    CFPreferencesAppSynchronize((__bridge CFStringRef)ABMCDomain);
    CFStringRef value = (CFStringRef)CFPreferencesCopyAppValue((__bridge CFStringRef)_preferenceKey, (__bridge CFStringRef)ABMCDomain);
    _currentValue = value ? (__bridge_transfer NSString *)value : (_defaultValue.length ? _defaultValue : @"none");
    [self.table reloadData];
}

- (NSArray *)specifiers {
    if (!_specifiers) {
        NSMutableArray *result = [NSMutableArray array];
        [result addObject:[PSSpecifier groupSpecifierWithName:@"内置动作"]];
        NSUInteger count = sizeof(kActions) / sizeof(kActions[0]);
        for (NSUInteger i = 0; i < count; i++) {
            PSSpecifier *item = [PSSpecifier preferenceSpecifierNamed:kActions[i].title target:self set:NULL get:NULL detail:Nil cell:PSStaticTextCell edit:Nil];
            [item setProperty:kActions[i].actionID forKey:@"actionID"];
            item->action = @selector(selectAction:);
            [result addObject:item];
        }
        PSSpecifier *group = [PSSpecifier groupSpecifierWithName:@"自定义动作"];
        [group setProperty:@"从已安装应用、快捷指令库或本地链接库选择动作。" forKey:@"footerText"];
        [result addObject:group];
        for (NSArray *entry in @[@[@"应用", @"customApp"], @[@"指令", @"customShortcut"], @[@"链接", @"customURL"]]) {
            PSSpecifier *item = [PSSpecifier preferenceSpecifierNamed:entry[0] target:self set:NULL get:NULL detail:Nil cell:PSStaticTextCell edit:Nil];
            [item setProperty:entry[1] forKey:@"actionID"];
            item->action = @selector(selectAction:);
            [result addObject:item];
        }
        _specifiers = result;
    }
    return _specifiers;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [super tableView:tableView cellForRowAtIndexPath:indexPath];
    NSString *actionID = [[self specifierAtIndexPath:indexPath] propertyForKey:@"actionID"];
    BOOL selected = [_currentValue isEqualToString:actionID];
    if ([actionID isEqualToString:@"customApp"]) selected = [_currentValue hasPrefix:@"app:"];
    if ([actionID isEqualToString:@"customShortcut"]) selected = [_currentValue hasPrefix:@"shortcut:"] || [_currentValue hasPrefix:@"shortcutid:"];
    if ([actionID isEqualToString:@"customURL"]) selected = [_currentValue hasPrefix:@"url:"] || [_currentValue hasPrefix:@"link:"];
    cell.accessoryType = selected ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
    return cell;
}

- (void)selectAction:(PSSpecifier *)specifier {
    NSString *actionID = [specifier propertyForKey:@"actionID"];
    if ([actionID isEqualToString:@"customApp"]) {
        [self.navigationController pushViewController:[[ABMCApplicationListController alloc] initWithPreferenceKey:_preferenceKey] animated:YES];
    } else if ([actionID isEqualToString:@"customShortcut"]) {
        [self.navigationController pushViewController:[[ABMCShortcutListController alloc] initWithPreferenceKey:_preferenceKey] animated:YES];
    } else if ([actionID isEqualToString:@"customURL"]) {
        [self.navigationController pushViewController:[[ABMCLinkListController alloc] initWithPreferenceKey:_preferenceKey] animated:YES];
    } else {
        [self saveAction:actionID];
    }
}

- (void)saveAction:(NSString *)actionID {
    if (!actionID.length) return;
    _currentValue = [actionID copy];
    CFPreferencesSetAppValue((__bridge CFStringRef)_preferenceKey, (__bridge CFPropertyListRef)actionID, (__bridge CFStringRef)ABMCDomain);
    CFPreferencesAppSynchronize((__bridge CFStringRef)ABMCDomain);
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), (__bridge CFStringRef)ABMCChanged, NULL, NULL, YES);
    [self.table reloadData];
}

@end
