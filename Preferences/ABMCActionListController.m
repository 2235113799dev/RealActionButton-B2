#import "ABMCActionListController.h"
#import "ABMCApplicationListController.h"
#import "ABMCShortcutListController.h"
#import "ABMCLinkListController.h"
#import "ABMCBuiltinListController.h"
#import "ABMCUIHelpers.h"
#import <Preferences/PSSpecifier.h>

#define ABMCDomain CFSTR("com.huynguyen.actionbuttonmulticlick")
#define ABMCTestNotification CFSTR("com.huynguyen.actionbuttonmulticlick/testCurrentAction")
#define ABMCLinksKey CFSTR("savedLinks")

typedef struct { NSString *identifier; NSString *title; } ABMCBuiltinAction;
static const ABMCBuiltinAction kBuiltinActions[] = {
    {@"default", @"系统默认"}, {@"flashlight", @"手电筒"}, {@"camera", @"相机"}, {@"silent", @"静音切换"},
    {@"screenshot", @"截屏"}, {@"lock", @"锁屏"}, {@"controlCenter", @"控制中心"},
    {@"notificationCenter", @"通知中心"}, {@"settings", @"打开设置"}, {@"respring", @"重启界面"}, {@"wechatScan", @"微信扫码"},
    {@"wechatPay", @"微信付款码"}, {@"alipayScan", @"支付宝扫码"}, {@"alipayPay", @"支付宝付款码"}, {@"none", @"无操作"}
};

static NSString *ABMCLinkTitle(NSString *linkID) {
    CFPropertyListRef value = CFPreferencesCopyAppValue(ABMCLinksKey, ABMCDomain);
    NSString *title = nil;
    if (value && CFGetTypeID(value) == CFArrayGetTypeID()) {
        for (NSDictionary *item in (__bridge NSArray *)value) {
            if ([item isKindOfClass:[NSDictionary class]] && [item[@"id"] isEqualToString:linkID]) { title = [item[@"title"] copy]; break; }
        }
    }
    if (value) CFRelease(value);
    return title;
}

@interface ABMCActionListController ()
- (void)openCategory:(PSSpecifier *)specifier;
- (void)testCurrentAction:(PSSpecifier *)specifier;
@end

@implementation ABMCActionListController {
    NSString *_preferenceKey;
    NSString *_defaultValue;
    NSString *_currentValue;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    PSSpecifier *parent = self.specifier;
    _preferenceKey = [[parent propertyForKey:@"key"] copy];
    _defaultValue = [[parent propertyForKey:@"default"] copy];
    NSString *label = [parent name];
    self.title = label.length ? label : @"选择动作";
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    CFStringRef value = (CFStringRef)CFPreferencesCopyAppValue((__bridge CFStringRef)_preferenceKey, ABMCDomain);
    _currentValue = value ? (__bridge_transfer NSString *)value : (_defaultValue ?: @"none");
    _specifiers = nil;
    [self reloadSpecifiers];
}

- (NSString *)displayAction:(NSString *)action {
    if (!action.length || [action isEqualToString:@"none"]) return @"无操作";
    for (NSUInteger i = 0; i < sizeof(kBuiltinActions) / sizeof(kBuiltinActions[0]); i++) {
        if ([action isEqualToString:kBuiltinActions[i].identifier]) return [NSString stringWithFormat:@"内置：%@", kBuiltinActions[i].title];
    }
    if ([action hasPrefix:@"app:"]) return [NSString stringWithFormat:@"应用：%@", ABMCApplicationName([action substringFromIndex:4])];
    if ([action hasPrefix:@"shortcutid:"]) {
        NSArray *parts = [[action substringFromIndex:11] componentsSeparatedByString:@"|"];
        return [NSString stringWithFormat:@"指令：%@", parts.count > 1 ? parts[1] : parts.firstObject];
    }
    if ([action hasPrefix:@"shortcut:"]) return [NSString stringWithFormat:@"指令：%@", [action substringFromIndex:9]];
    if ([action hasPrefix:@"link:"]) return [NSString stringWithFormat:@"链接：%@", ABMCLinkTitle([action substringFromIndex:5]) ?: @"未找到"];
    if ([action hasPrefix:@"url:"]) return [NSString stringWithFormat:@"链接：%@", [action substringFromIndex:4]];
    return action;
}

- (NSArray *)specifiers {
    if (!_specifiers) {
        NSMutableArray *items = [NSMutableArray array];
        [items addObject:[PSSpecifier groupSpecifierWithName:@"已选动作"]];
        PSSpecifier *chosen = [PSSpecifier preferenceSpecifierNamed:[self displayAction:_currentValue] target:self set:NULL get:NULL detail:Nil cell:PSStaticTextCell edit:Nil];
        [chosen setProperty:@YES forKey:@"chosenAction"];
        [items addObject:chosen];

        [items addObject:[PSSpecifier groupSpecifierWithName:@"动作测试"]];
        PSSpecifier *test = [PSSpecifier preferenceSpecifierNamed:@"立即测试当前动作" target:self set:NULL get:NULL detail:Nil cell:PSButtonCell edit:Nil];
        test->action = @selector(testCurrentAction:);
        [items addObject:test];

        NSArray *categories = @[
            @[@"内置动作", @"内置动作", @"builtin", @"sparkles"], @[@"应用列表", @"应用列表", @"app", @"app.fill"],
            @[@"指令列表", @"指令列表", @"shortcut", @"square.stack.3d.up.fill"], @[@"链接管理", @"链接管理", @"link", @"link"]
        ];
        for (NSArray *category in categories) {
            [items addObject:[PSSpecifier groupSpecifierWithName:category[0]]];
            PSSpecifier *entry = [PSSpecifier preferenceSpecifierNamed:category[1] target:self set:NULL get:NULL detail:Nil cell:PSLinkCell edit:Nil];
            [entry setProperty:category[2] forKey:@"category"];
            [entry setProperty:category[3] forKey:@"iconToken"];
            entry->action = @selector(openCategory:);
            [items addObject:entry];
        }
        _specifiers = items;
    }
    return _specifiers;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [super tableView:tableView cellForRowAtIndexPath:indexPath];
    PSSpecifier *spec = [self specifierAtIndexPath:indexPath];
    cell.textLabel.font = [UIFont systemFontOfSize:17.0 weight:UIFontWeightRegular];
    if ([spec propertyForKey:@"chosenAction"]) {
        UIColor *blue = UIColor.systemBlueColor;
        cell.tintColor = blue;
        cell.textLabel.textColor = blue;
        cell.detailTextLabel.textColor = blue;
        cell.textLabel.attributedText = [[NSAttributedString alloc] initWithString:cell.textLabel.text ?: @"" attributes:@{NSForegroundColorAttributeName: blue, NSFontAttributeName: cell.textLabel.font}];
        cell.textLabel.font = [UIFont systemFontOfSize:17.0 weight:UIFontWeightRegular];
        UIImageView *light = [[UIImageView alloc] initWithImage:ABMCTintedIcon(@"lightbulb.max", blue)];
        light.frame = CGRectMake(0, 0, 30, 30);
        light.contentMode = UIViewContentModeScaleAspectFit;
        cell.imageView.image = nil;
        cell.accessoryView = light;
    }
    NSString *icon = [spec propertyForKey:@"iconToken"];
    if (icon.length) cell.imageView.image = ABMCTintedIcon(icon, UIColor.systemBlueColor);
    return cell;
}

- (void)openCategory:(PSSpecifier *)specifier {
    NSString *category = [specifier propertyForKey:@"category"];
    UIViewController *controller = nil;
    if ([category isEqualToString:@"builtin"]) controller = [[ABMCBuiltinListController alloc] initWithPreferenceKey:_preferenceKey];
    else if ([category isEqualToString:@"app"]) controller = [[ABMCApplicationListController alloc] initWithPreferenceKey:_preferenceKey];
    else if ([category isEqualToString:@"shortcut"]) controller = [[ABMCShortcutListController alloc] initWithPreferenceKey:_preferenceKey];
    else if ([category isEqualToString:@"link"]) controller = [[ABMCLinkListController alloc] initWithPreferenceKey:_preferenceKey];
    if (controller) [self.navigationController pushViewController:controller animated:YES];
}

- (void)testCurrentAction:(PSSpecifier *)specifier {
    if (!_currentValue.length || [_currentValue isEqualToString:@"none"]) return;
    CFPreferencesSetAppValue(CFSTR("testAction"), (__bridge CFPropertyListRef)_currentValue, ABMCDomain);
    CFPreferencesAppSynchronize(ABMCDomain);
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), ABMCTestNotification, NULL, NULL, YES);
}
@end
