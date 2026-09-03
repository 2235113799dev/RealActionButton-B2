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
    if ([actionID isEqualToString:@"respring"]) return @"重启界面";
    if ([actionID isEqualToString:@"wechatScan"]) return @"微信扫码";
    if ([actionID isEqualToString:@"wechatPay"]) return @"微信付款码";
    if ([actionID isEqualToString:@"alipayScan"]) return @"支付宝扫码";
    if ([actionID isEqualToString:@"alipayPay"]) return @"支付宝付款码";
    if ([actionID hasPrefix:@"app:"]) return [NSString stringWithFormat:@"应用：%@", [actionID substringFromIndex:4]];
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
        return title.length ? title : @"链接（未找到）";
    }
    if ([actionID hasPrefix:@"url:"]) return [NSString stringWithFormat:@"链接：%@", [actionID substringFromIndex:4]];
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
        [specs addObject:longPress];

        PSSpecifier *urlModeGroup = [PSSpecifier groupSpecifierWithName:@"链接打开方式"];
        [urlModeGroup setProperty:@"开启时，所有内置和自定义 URL 使用异步全屏直达；关闭时恢复原始 URL 打开方式，可由 FV 等插件接管。" forKey:@"footerText"];
        [specs addObject:urlModeGroup];

        PSSpecifier *urlMode = [PSSpecifier preferenceSpecifierNamed:@"URL 全屏直达"
                                                               target:self
                                                                  set:@selector(setURLOpenMode:specifier:)
                                                                  get:@selector(urlOpenModeForSpecifier:)
                                                               detail:Nil
                                                                 cell:PSSwitchCell
                                                                 edit:Nil];
        [urlMode setProperty:@"urlOpenMode" forKey:@"key"];
        [urlMode setProperty:PREFS_DOMAIN forKey:@"defaults"];
        [urlMode setProperty:@YES forKey:@"default"];
        [urlMode setProperty:@"link.circle.fill" forKey:@"iconToken"];
        [specs addObject:urlMode];

        _specifiers = specs;
    }
    return _specifiers;
}

- (NSNumber *)urlOpenModeForSpecifier:(PSSpecifier *)specifier {
    CFPreferencesAppSynchronize((__bridge CFStringRef)PREFS_DOMAIN);
    CFPropertyListRef value = CFPreferencesCopyAppValue(CFSTR("urlOpenMode"), (__bridge CFStringRef)PREFS_DOMAIN);
    NSNumber *result = @YES;
    if (value && CFGetTypeID(value) == CFBooleanGetTypeID()) {
        result = @(CFBooleanGetValue((CFBooleanRef)value));
    }
    if (value) CFRelease(value);
    return result;
}

- (void)setURLOpenMode:(id)value specifier:(PSSpecifier *)specifier {
    BOOL enabled = [value respondsToSelector:@selector(boolValue)] ? [value boolValue] : YES;
    CFPreferencesSetAppValue(CFSTR("urlOpenMode"),
                             enabled ? kCFBooleanTrue : kCFBooleanFalse,
                             (__bridge CFStringRef)PREFS_DOMAIN);
    CFPreferencesAppSynchronize((__bridge CFStringRef)PREFS_DOMAIN);

    // Update the already-running SpringBoard tweak immediately.
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                         (__bridge CFStringRef)PREFS_NOTIFICATION,
                                         NULL, NULL, YES);
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
    [self reloadSpecifierID:@"urlOpenMode"];
}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [super tableView:tableView cellForRowAtIndexPath:indexPath];
    PSSpecifier *specifier = [self specifierAtIndexPath:indexPath];
    NSString *icon = [specifier propertyForKey:@"iconToken"];
    if (icon.length) {
        UIImage *image = ABMCTintedIcon(icon, UIColor.systemBlueColor);
        UIImageView *view = [[UIImageView alloc] initWithImage:image];
        view.frame = CGRectMake(0, 0, 30, 30);
        view.contentMode = UIViewContentModeScaleAspectFit;
        cell.imageView.image = image;
    }
    return cell;
}

@end
