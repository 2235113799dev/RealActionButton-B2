#import "ABMCPreferences.h"
#import "ABMCUIHelpers.h"
#import <Preferences/PSSpecifier.h>

#define PREFS_DOMAIN @"com.huynguyen.actionbuttonmulticlick"
#define PREFS_NOTIFICATION @"com.huynguyen.actionbuttonmulticlick/prefsChanged"

static NSString *titleForActionID(NSString *actionID) {
    if (!actionID || [actionID isEqualToString:@"none"]) return @"无操作";
    if ([actionID isEqualToString:@"default"]) return @"系统默认";
    if ([actionID isEqualToString:@"flashlight"]) return @"手电筒";
    if ([actionID isEqualToString:@"camera"]) return @"相机";
    if ([actionID isEqualToString:@"silent"]) return @"静音切换";
    if ([actionID isEqualToString:@"screenshot"]) return @"截屏";
    if ([actionID isEqualToString:@"lock"]) return @"锁屏";
    if ([actionID isEqualToString:@"controlCenter"]) return @"控制中心";
    if ([actionID isEqualToString:@"notificationCenter"]) return @"通知中心";
    if ([actionID isEqualToString:@"settings"]) return @"打开设置";
    if ([actionID isEqualToString:@"respring"]) return @"重启界面";
    if ([actionID isEqualToString:@"wechatScan"]) return @"微信扫码";
    if ([actionID isEqualToString:@"wechatPay"]) return @"微信付款码";
    if ([actionID isEqualToString:@"alipayScan"]) return @"支付宝扫码";
    if ([actionID isEqualToString:@"alipayPay"]) return @"支付宝付款码";
    if ([actionID hasPrefix:@"app:"]) return [actionID substringFromIndex:4];
    if ([actionID hasPrefix:@"shortcutid:"]) {
        NSString *payload = [actionID substringFromIndex:11];
        NSArray *parts = [payload componentsSeparatedByString:@"|"];
        return [NSString stringWithFormat:@"指令：%@", parts.count > 1 ? parts[1] : parts.firstObject];
    }
    if ([actionID hasPrefix:@"shortcut:"]) return [NSString stringWithFormat:@"指令：%@", [actionID substringFromIndex:9]];
    if ([actionID hasPrefix:@"link:"]) {
        NSString *linkID = [actionID substringFromIndex:5];
        CFPreferencesAppSynchronize((__bridge CFStringRef)PREFS_DOMAIN);
        CFPropertyListRef links = CFPreferencesCopyAppValue(CFSTR("savedLinks"), (__bridge CFStringRef)PREFS_DOMAIN);
        NSString *title = nil;
        if (links && CFGetTypeID(links) == CFArrayGetTypeID()) {
            for (NSDictionary *link in (__bridge NSArray *)links) {
                if ([link isKindOfClass:[NSDictionary class]] && [link[@"id"] isEqualToString:linkID]) { title = [link[@"title"] copy]; break; }
            }
        }
        if (links) CFRelease(links);
        return title.length ? title : @"URL（未找到）";
    }
    if ([actionID hasPrefix:@"url:"]) return [NSString stringWithFormat:@"URL：%@", [actionID substringFromIndex:4]];
    return actionID;
}

@implementation ABMCPreferences

- (NSArray *)specifiers {
    if (!_specifiers) {
        NSMutableArray *specs = [NSMutableArray array];

        PSSpecifier *group1 = [PSSpecifier groupSpecifierWithName:@"按键动作"];
        [group1 setProperty:@"单击在松开后最多等待 240 毫秒；第二次松开后会立即执行双击。长按仍由系统原生时机识别。" forKey:@"footerText"];
        [specs addObject:group1];

        PSSpecifier *single = [PSSpecifier preferenceSpecifierNamed:@"单击动作"
                                                             target:self
                                                                set:NULL
                                                                get:NULL
                                                             detail:NSClassFromString(@"ABMCActionListController")
                                                               cell:PSLinkCell
                                                               edit:Nil];
        [single setProperty:@"singleClickAction" forKey:@"key"];
        [single setProperty:@"default" forKey:@"default"];
        [single setProperty:PREFS_DOMAIN forKey:@"defaults"];
        [single setProperty:@"hand.tap.fill" forKey:@"iconToken"];
        [single setProperty:ABMCTintedIcon(@"hand.tap.fill", UIColor.systemBlueColor) forKey:@"iconImage"];
        [specs addObject:single];

        PSSpecifier *dbl = [PSSpecifier preferenceSpecifierNamed:@"双击动作"
                                                          target:self
                                                             set:NULL
                                                             get:NULL
                                                          detail:NSClassFromString(@"ABMCActionListController")
                                                            cell:PSLinkCell
                                                            edit:Nil];
        [dbl setProperty:@"doubleClickAction" forKey:@"key"];
        [dbl setProperty:@"none" forKey:@"default"];
        [dbl setProperty:PREFS_DOMAIN forKey:@"defaults"];
        [dbl setProperty:@"hand.tap.fill" forKey:@"iconToken"];
        [dbl setProperty:ABMCTintedIcon(@"hand.tap.fill", UIColor.systemBlueColor) forKey:@"iconImage"];
        [specs addObject:dbl];

        PSSpecifier *longPress = [PSSpecifier preferenceSpecifierNamed:@"长按动作"
                                                                target:self
                                                                   set:NULL
                                                                   get:NULL
                                                                detail:NSClassFromString(@"ABMCActionListController")
                                                                  cell:PSLinkCell
                                                                  edit:Nil];
        [longPress setProperty:@"longPressAction" forKey:@"key"];
        [longPress setProperty:@"default" forKey:@"default"];
        [longPress setProperty:PREFS_DOMAIN forKey:@"defaults"];
        [longPress setProperty:@"hand.tap.fill" forKey:@"iconToken"];
        [longPress setProperty:ABMCTintedIcon(@"hand.tap.fill", UIColor.systemBlueColor) forKey:@"iconImage"];
        [specs addObject:longPress];

        PSSpecifier *launchGroup = [PSSpecifier groupSpecifierWithName:@"启动方式"];
        [launchGroup setProperty:@"开启时优先由系统全屏执行；关闭时使用兼容启动路线，供 FV 等分屏插件接管。快捷指令始终优先后台直接运行，只有后台接口不可用才使用后备启动方式。" forKey:@"footerText"];
        [specs addObject:launchGroup];

        PSSpecifier *urlMode = [PSSpecifier preferenceSpecifierNamed:@"URL全屏"
                                                               target:self
                                                                  set:@selector(setOpenMode:specifier:)
                                                                  get:@selector(openModeForSpecifier:)
                                                               detail:Nil
                                                                 cell:PSSwitchCell
                                                                 edit:Nil];
        [urlMode setProperty:@"urlOpenMode" forKey:@"key"];
        [urlMode setProperty:@"urlOpenMode" forKey:@"id"];
        [urlMode setProperty:PREFS_DOMAIN forKey:@"defaults"];
        [urlMode setProperty:@YES forKey:@"default"];
        [urlMode setProperty:@"link" forKey:@"iconToken"];
        [urlMode setProperty:ABMCTintedIcon(@"link", UIColor.systemBlueColor) forKey:@"iconImage"];
        [specs addObject:urlMode];

        NSArray *launchModes = @[
            @[@"应用全屏", @"appOpenMode", @"app.badge.checkmark"],
            @[@"快捷方式全屏", @"appShortcutOpenMode", @"square.grid.2x2.fill"]
        ];
        for (NSArray *item in launchModes) {
            PSSpecifier *mode = [PSSpecifier preferenceSpecifierNamed:item[0] target:self set:@selector(setOpenMode:specifier:) get:@selector(openModeForSpecifier:) detail:Nil cell:PSSwitchCell edit:Nil];
            [mode setProperty:item[1] forKey:@"key"];
            [mode setProperty:item[1] forKey:@"id"];
            [mode setProperty:PREFS_DOMAIN forKey:@"defaults"];
            [mode setProperty:@YES forKey:@"default"];
            [mode setProperty:item[2] forKey:@"iconToken"];
            [mode setProperty:ABMCTintedIcon(item[2], UIColor.systemBlueColor) forKey:@"iconImage"];
            [specs addObject:mode];
        }

        _specifiers = specs;
    }
    return _specifiers;
}

- (NSNumber *)openModeForSpecifier:(PSSpecifier *)specifier {
    NSString *key = [specifier propertyForKey:@"key"];
    CFPreferencesAppSynchronize((__bridge CFStringRef)PREFS_DOMAIN);
    CFPropertyListRef value = CFPreferencesCopyAppValue((__bridge CFStringRef)key, (__bridge CFStringRef)PREFS_DOMAIN);
    NSNumber *result = @YES;
    if (value && CFGetTypeID(value) == CFBooleanGetTypeID()) result = @(CFBooleanGetValue((CFBooleanRef)value));
    if (value) CFRelease(value);
    return result;
}

- (void)setOpenMode:(id)value specifier:(PSSpecifier *)specifier {
    NSString *key = [specifier propertyForKey:@"key"];
    BOOL enabled = [value respondsToSelector:@selector(boolValue)] ? [value boolValue] : YES;
    CFPreferencesSetAppValue((__bridge CFStringRef)key, enabled ? kCFBooleanTrue : kCFBooleanFalse, (__bridge CFStringRef)PREFS_DOMAIN);
    CFPreferencesAppSynchronize((__bridge CFStringRef)PREFS_DOMAIN);
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), (__bridge CFStringRef)PREFS_NOTIFICATION, NULL, NULL, YES);
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self reload];
}

- (void)reloadSpecifiers {
    [super reloadSpecifiers];
    for (PSSpecifier *spec in _specifiers) {
        NSString *key = [spec propertyForKey:@"key"];
        if ([key hasSuffix:@"Action"]) {
            CFPreferencesAppSynchronize((__bridge CFStringRef)PREFS_DOMAIN);
            CFStringRef val = (CFStringRef)CFPreferencesCopyAppValue((__bridge CFStringRef)key, (__bridge CFStringRef)PREFS_DOMAIN);
            NSString *actionID = val ? (__bridge_transfer NSString *)val : [spec propertyForKey:@"default"];
            [spec setProperty:titleForActionID(actionID) forKey:@"cellValue"];
        }
    }
    for (NSString *identifier in @[@"urlOpenMode", @"appOpenMode", @"appShortcutOpenMode"]) [self reloadSpecifierID:identifier];
}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [super tableView:tableView cellForRowAtIndexPath:indexPath];
    // Icons are fixed in each specifier's iconImage at construction time.
    // Do not touch imageView/accessoryView here: PSSwitchCell owns its layout.
    return cell;
}

@end
