#import "ABMCPreferences.h"
#import "ABMCIconStyleController.h"
#import "ABMCUIHelpers.h"
#import <Preferences/PSSpecifier.h>

#define PREFS_DOMAIN @"com.huynguyen.actionbuttonmulticlick"
#define PREFS_NOTIFICATION @"com.huynguyen.actionbuttonmulticlick/prefsChanged"

static NSString *presentationKeyForActionID(NSString *actionID) {
    if ([actionID hasPrefix:@"app:"]) return [@"app." stringByAppendingString:[actionID substringFromIndex:4]];
    if ([actionID hasPrefix:@"shortcutid:"]) return [@"shortcut." stringByAppendingString:[[actionID substringFromIndex:11] componentsSeparatedByString:@"|"].firstObject ?: @""];
    return [@"action." stringByAppendingString:actionID ?: @"none"];
}

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
        [single setProperty:@"root.single" forKey:@"presentationKey"]; [single setProperty:@"单击动作" forKey:@"defaultTitle"]; [single setProperty:@"hand.tap.fill" forKey:@"defaultIcon"];
        [single setProperty:ABMCTintedIcon(@"hand.tap.fill", ABMCUnifiedIconColor()) forKey:@"iconImage"];
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
        [dbl setProperty:@"root.double" forKey:@"presentationKey"]; [dbl setProperty:@"双击动作" forKey:@"defaultTitle"]; [dbl setProperty:@"hand.tap.fill" forKey:@"defaultIcon"];
        [dbl setProperty:ABMCTintedIcon(@"hand.tap.fill", ABMCUnifiedIconColor()) forKey:@"iconImage"];
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
        [longPress setProperty:@"root.long" forKey:@"presentationKey"]; [longPress setProperty:@"长按动作" forKey:@"defaultTitle"]; [longPress setProperty:@"hand.tap.fill" forKey:@"defaultIcon"];
        [longPress setProperty:ABMCTintedIcon(@"hand.tap.fill", ABMCUnifiedIconColor()) forKey:@"iconImage"];
        [specs addObject:longPress];

        PSSpecifier *appearanceGroup = [PSSpecifier groupSpecifierWithName:@"全局外观"];
        [appearanceGroup setProperty:@"图标尺寸和颜色全局生效。所有动作、分组、应用、指令和 URL 均可左滑修改或清空；清空只恢复本插件中的默认显示。" forKey:@"footerText"];
        [specs addObject:appearanceGroup];
        PSSpecifier *size = [PSSpecifier preferenceSpecifierNamed:@"图标尺寸" target:self set:NULL get:NULL detail:Nil cell:PSLinkCell edit:Nil];
        [size setProperty:@"iconStyleSize" forKey:@"styleMode"]; [size setProperty:@"root.iconSize" forKey:@"presentationKey"]; [size setProperty:@"图标尺寸" forKey:@"defaultTitle"]; [size setProperty:@"arrow.up.left.and.arrow.down.right" forKey:@"defaultIcon"]; [size setProperty:ABMCTintedIcon(@"arrow.up.left.and.arrow.down.right", ABMCUnifiedIconColor()) forKey:@"iconImage"]; size->action=@selector(openIconStyle:); [specs addObject:size];
        PSSpecifier *color = [PSSpecifier preferenceSpecifierNamed:@"图标颜色" target:self set:NULL get:NULL detail:Nil cell:PSLinkCell edit:Nil];
        [color setProperty:@"iconStyleColor" forKey:@"styleMode"]; [color setProperty:@"root.iconColor" forKey:@"presentationKey"]; [color setProperty:@"图标颜色" forKey:@"defaultTitle"]; [color setProperty:@"paintpalette.fill" forKey:@"defaultIcon"]; [color setProperty:ABMCTintedIcon(@"paintpalette.fill", ABMCUnifiedIconColor()) forKey:@"iconImage"]; color->action=@selector(openIconStyle:); [specs addObject:color];

        PSSpecifier *launchGroup = [PSSpecifier groupSpecifierWithName:@"启动方式"];
        [launchGroup setProperty:@"应用启动统一使用 SpringBoard 正常激活链；关闭“应用全屏”时改走真实桌面图标路径，供分屏插件接管。快捷指令通过系统后台运行器执行。" forKey:@"footerText"];
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
        [urlMode setProperty:@"root.urlMode" forKey:@"presentationKey"]; [urlMode setProperty:@"URL全屏" forKey:@"defaultTitle"]; [urlMode setProperty:@"link" forKey:@"defaultIcon"];
        [urlMode setProperty:ABMCTintedIcon(@"link", ABMCUnifiedIconColor()) forKey:@"iconImage"];
        [specs addObject:urlMode];

        NSArray *launchModes = @[
            @[@"应用全屏", @"appOpenMode", @"app.badge.checkmark"]
        ];
        for (NSArray *item in launchModes) {
            PSSpecifier *mode = [PSSpecifier preferenceSpecifierNamed:item[0] target:self set:@selector(setOpenMode:specifier:) get:@selector(openModeForSpecifier:) detail:Nil cell:PSSwitchCell edit:Nil];
            [mode setProperty:item[1] forKey:@"key"];
            [mode setProperty:item[1] forKey:@"id"];
            [mode setProperty:PREFS_DOMAIN forKey:@"defaults"];
            [mode setProperty:@YES forKey:@"default"];
            [mode setProperty:item[2] forKey:@"iconToken"];
            [mode setProperty:[@"root." stringByAppendingString:item[1]] forKey:@"presentationKey"]; [mode setProperty:item[0] forKey:@"defaultTitle"]; [mode setProperty:item[2] forKey:@"defaultIcon"];
            [mode setProperty:ABMCTintedIcon(item[2], ABMCUnifiedIconColor()) forKey:@"iconImage"];
            [specs addObject:mode];
        }

        _specifiers = specs;
    }
    return _specifiers;
}

- (void)openIconStyle:(PSSpecifier *)specifier {
    ABMCIconStyleMode mode=[[specifier propertyForKey:@"styleMode"] isEqualToString:@"iconStyleColor"] ? ABMCIconStyleModeColor : ABMCIconStyleModeSize;
    [self.navigationController pushViewController:[[ABMCIconStyleController alloc] initWithMode:mode] animated:YES];
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
    // Rebuild fixed specifier icons after the pt/color editor changes.
    _specifiers = nil;
    [self reloadSpecifiers];
}

- (void)reloadSpecifiers {
    [super reloadSpecifiers];
    for (PSSpecifier *spec in _specifiers) {
        NSString *key = [spec propertyForKey:@"key"];
        if ([key hasSuffix:@"Action"]) {
            CFPreferencesAppSynchronize((__bridge CFStringRef)PREFS_DOMAIN);
            CFStringRef val = (CFStringRef)CFPreferencesCopyAppValue((__bridge CFStringRef)key, (__bridge CFStringRef)PREFS_DOMAIN);
            NSString *actionID = val ? (__bridge_transfer NSString *)val : [spec propertyForKey:@"default"];
            NSString *title = titleForActionID(actionID);
            [spec setProperty:ABMCDisplayTitle(presentationKeyForActionID(actionID), title) forKey:@"cellValue"];
        }
    }
    for (NSString *identifier in @[@"urlOpenMode", @"appOpenMode"]) [self reloadSpecifierID:identifier];
}
- (UISwipeActionsConfiguration *)tableView:(UITableView *)tableView trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath {
    PSSpecifier *spec=[self specifierAtIndexPath:indexPath]; NSString *actionKey=[spec propertyForKey:@"key"];
    NSString *key=[spec propertyForKey:@"presentationKey"],*title=[spec propertyForKey:@"defaultTitle"],*icon=[spec propertyForKey:@"defaultIcon"];
    if(!key.length && [actionKey hasSuffix:@"Action"]){CFPreferencesAppSynchronize((__bridge CFStringRef)PREFS_DOMAIN);CFStringRef raw=(CFStringRef)CFPreferencesCopyAppValue((__bridge CFStringRef)actionKey,(__bridge CFStringRef)PREFS_DOMAIN);NSString *action=raw?(__bridge_transfer NSString *)raw:[spec propertyForKey:@"default"];title=titleForActionID(action);icon=[action hasPrefix:@"app:"]?[action substringFromIndex:4]:([action hasPrefix:@"shortcutid:"]?@"square.stack.3d.up.fill":@"hand.tap.fill");key=[action hasPrefix:@"app:"]?[@"app." stringByAppendingString:[action substringFromIndex:4]]:([action hasPrefix:@"shortcutid:"]?[@"shortcut." stringByAppendingString:[[action substringFromIndex:11] componentsSeparatedByString:@"|"].firstObject?:@""]:[@"action." stringByAppendingString:action?:@"none"]);}
    if(!key.length)return nil;
    title=ABMCDisplayTitle(key,title ?: [spec name]);icon=ABMCDisplayIconToken(key,icon ?: @"hand.tap.fill");
    UIContextualAction *edit=[UIContextualAction contextualActionWithStyle:UIContextualActionStyleNormal title:@"修改" handler:^(__unused UIContextualAction*a,__unused UIView*v,void(^done)(BOOL)){ABMCShowPresentationEditor(self,key,title,icon,^{[self->_specifiers removeAllObjects];self->_specifiers=nil;[self reloadSpecifiers];done(YES);});}];edit.backgroundColor=UIColor.systemBlueColor;
    UIContextualAction *clear=[UIContextualAction contextualActionWithStyle:UIContextualActionStyleDestructive title:@"清空" handler:^(__unused UIContextualAction*a,__unused UIView*v,void(^done)(BOOL)){ABMCClearPresentationOverride(key);self->_specifiers=nil;[self reloadSpecifiers];done(YES);}];clear.backgroundColor=UIColor.systemGrayColor;return[UISwipeActionsConfiguration configurationWithActions:@[clear,edit]];
}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [super tableView:tableView cellForRowAtIndexPath:indexPath];
    // Re-apply the single global canvas for root PSLinkCell and PSSwitchCell
    // icons. Specifier construction otherwise leaves root rows at UIKit's
    // default image metrics while subpages use ABMCApplyLargeIcon.
    PSSpecifier *specifier=[self specifierAtIndexPath:indexPath];
    NSString *token=[specifier propertyForKey:@"iconToken"];
    NSString *presentationKey=[specifier propertyForKey:@"presentationKey"];
    NSString *defaultTitle=[specifier propertyForKey:@"defaultTitle"];
    NSString *defaultIcon=[specifier propertyForKey:@"defaultIcon"];
    if(presentationKey.length) { cell.textLabel.text=ABMCDisplayTitle(presentationKey,defaultTitle ?: [specifier name]); token=ABMCDisplayIconToken(presentationKey,defaultIcon ?: token); }
    UIImage *fixed=[specifier propertyForKey:@"iconImage"];
    if(token.length) ABMCApplyLargeIcon(cell,ABMCTintedIcon(token,nil) ?: ABMCIconImageForBundleID(token));
    else if([fixed isKindOfClass:UIImage.class]) ABMCApplyLargeIcon(cell,fixed);
    return cell;
}

@end
