#import "ABMCActionListController.h"
#import "ABMCApplicationListController.h"
#import "ABMCShortcutListController.h"
#import "ABMCLinkListController.h"
#import "ABMCBuiltinListController.h"
#import <Preferences/PSSpecifier.h>
#import <UIKit/UIKit.h>
#import <objc/message.h>

#define ABMCDomain CFSTR("com.huynguyen.actionbuttonmulticlick")
#define ABMCChanged CFSTR("com.huynguyen.actionbuttonmulticlick/prefsChanged")
#define ABMCTestNotification CFSTR("com.huynguyen.actionbuttonmulticlick/testCurrentAction")
#define ABMCTestActionKey CFSTR("testAction")
#define ABMCLinksKey CFSTR("savedLinks")

typedef struct { NSString *identifier; NSString *title; } ABMCBuiltinAction;
static const ABMCBuiltinAction kBuiltinActions[] = {
    {@"default", @"系统默认"}, {@"flashlight", @"手电筒"}, {@"camera", @"相机"},
    {@"silent", @"静音切换"}, {@"screenshot", @"截屏"}, {@"lock", @"锁屏"},
    {@"respring", @"重启界面"}, {@"wechatScan", @"微信扫码"},
    {@"wechatPay", @"微信付款码"}, {@"alipayScan", @"支付宝扫码"},
    {@"alipayPay", @"支付宝付款码"}, {@"none", @"无操作"}
};

static NSString *ABMCSelectedLinkTitle(NSString *linkID) {
    if (!linkID.length) return nil;
    CFPropertyListRef value = CFPreferencesCopyAppValue(ABMCLinksKey, ABMCDomain);
    NSString *title = nil;
    if (value && CFGetTypeID(value) == CFArrayGetTypeID()) {
        for (NSDictionary *link in (__bridge NSArray *)value) {
            if ([link isKindOfClass:[NSDictionary class]] && [link[@"id"] isEqualToString:linkID]) { title = [link[@"title"] copy]; break; }
        }
    }
    if (value) CFRelease(value);
    return title;
}

static NSString *ABMCApplicationName(NSString *bundleID) {
    if (!bundleID.length) return @"未知应用";
    @try {
        Class workspaceClass = NSClassFromString(@"LSApplicationWorkspace");
        SEL defaultSel = NSSelectorFromString(@"defaultWorkspace");
        SEL appSel = NSSelectorFromString(@"applicationProxyForBundleIdentifier:");
        id workspace = workspaceClass && [workspaceClass respondsToSelector:defaultSel] ? ((id (*)(id, SEL))objc_msgSend)(workspaceClass, defaultSel) : nil;
        id proxy = workspace && [workspace respondsToSelector:appSel] ? ((id (*)(id, SEL, id))objc_msgSend)(workspace, appSel, bundleID) : nil;
        SEL nameSel = NSSelectorFromString(@"localizedName");
        id name = proxy && [proxy respondsToSelector:nameSel] ? ((id (*)(id, SEL))objc_msgSend)(proxy, nameSel) : nil;
        if ([name isKindOfClass:[NSString class]] && [name length]) return name;
    } @catch (NSException *exception) {}
    return bundleID;
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
    PSSpecifier *parent = [self specifier];
    _preferenceKey = [[parent propertyForKey:@"key"] copy];
    _defaultValue = [[parent propertyForKey:@"default"] copy];
    self.title = @"选择动作";
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self loadCurrentValue];
    _specifiers = nil;
    [self reloadSpecifiers];
}

- (void)loadCurrentValue {
    if (!_preferenceKey.length) return;
    CFStringRef value = (CFStringRef)CFPreferencesCopyAppValue((__bridge CFStringRef)_preferenceKey, ABMCDomain);
    _currentValue = value ? (__bridge_transfer NSString *)value : (_defaultValue.length ? [_defaultValue copy] : @"none");
}

- (NSString *)displayForAction:(NSString *)action {
    if (!action.length || [action isEqualToString:@"none"]) return @"无操作";
    for (NSUInteger i = 0; i < sizeof(kBuiltinActions) / sizeof(kBuiltinActions[0]); i++) {
        if ([action isEqualToString:kBuiltinActions[i].identifier]) return [NSString stringWithFormat:@"内置：%@", kBuiltinActions[i].title];
    }
    if ([action hasPrefix:@"app:"]) return [NSString stringWithFormat:@"应用：%@", ABMCApplicationName([action substringFromIndex:4])];
    if ([action hasPrefix:@"shortcutid:"]) {
        NSArray *parts = [[action substringFromIndex:11] componentsSeparatedByString:@"|"];
        return [NSString stringWithFormat:@"指令：%@", parts.count > 1 && [parts[1] length] ? parts[1] : parts.firstObject];
    }
    if ([action hasPrefix:@"shortcut:"]) return [NSString stringWithFormat:@"指令：%@", [action substringFromIndex:9]];
    if ([action hasPrefix:@"link:"]) return [NSString stringWithFormat:@"链接：%@", ABMCSelectedLinkTitle([action substringFromIndex:5]) ?: @"未找到"];
    if ([action hasPrefix:@"url:"]) return [NSString stringWithFormat:@"链接：%@", [action substringFromIndex:4]];
    return action;
}

- (NSArray *)specifiers {
    if (!_specifiers) {
        NSMutableArray *items = [NSMutableArray array];
        [items addObject:[PSSpecifier groupSpecifierWithName:@"已选择动作"]];
        PSSpecifier *selected = [PSSpecifier preferenceSpecifierNamed:[self displayForAction:_currentValue] target:self set:NULL get:NULL detail:Nil cell:PSStaticTextCell edit:Nil];
        [selected setProperty:@YES forKey:@"selectedActionCell"];
        [items addObject:selected];

        [items addObject:[PSSpecifier groupSpecifierWithName:@"动作测试"]];
        PSSpecifier *test = [PSSpecifier preferenceSpecifierNamed:@"立即测试当前动作" target:self set:NULL get:NULL detail:Nil cell:PSButtonCell edit:Nil];
        test->action = @selector(testCurrentAction:);
        [items addObject:test];

        NSArray *categories = @[@[@"内置动作", @"builtin", @"选择内置动作"], @[@"应用", @"app", @"选择应用"], @[@"指令", @"shortcut", @"选择指令"], @[@"链接", @"link", @"选择链接"]];
        for (NSArray *category in categories) {
            [items addObject:[PSSpecifier groupSpecifierWithName:category[0]]];
            PSSpecifier *entry = [PSSpecifier preferenceSpecifierNamed:category[2] target:self set:NULL get:NULL detail:Nil cell:PSLinkCell edit:Nil];
            [entry setProperty:category[1] forKey:@"actionCategory"];
            entry->action = @selector(openCategory:);
            [items addObject:entry];
        }
        _specifiers = items;
    }
    return _specifiers;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [super tableView:tableView cellForRowAtIndexPath:indexPath];
    PSSpecifier *specifier = [self specifierAtIndexPath:indexPath];
    if ([specifier propertyForKey:@"selectedActionCell"]) {
        UIImage *image = [UIImage systemImageNamed:@"lightbulb.max"];
        if (image) image = [image imageWithTintColor:[UIColor systemBlueColor] renderingMode:UIImageRenderingModeAlwaysOriginal];
        cell.accessoryView = image ? [[UIImageView alloc] initWithImage:image] : nil;
        cell.textLabel.textColor = [UIColor secondaryLabelColor];
        cell.textLabel.font = [UIFont systemFontOfSize:22.0 weight:UIFontWeightRegular];
    }
    return cell;
}

- (void)openCategory:(PSSpecifier *)specifier {
    NSString *category = [specifier propertyForKey:@"actionCategory"];
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
