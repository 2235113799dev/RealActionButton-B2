#import "ABMCActionListController.h"
#import "ABMCApplicationListController.h"
#import "ABMCAppShortcutListController.h"
#import "ABMCShortcutListController.h"
#import "ABMCLinkListController.h"
#import "ABMCBuiltinListController.h"
#import "ABMCUIHelpers.h"
#import <Preferences/PSSpecifier.h>

#define Domain CFSTR("com.huynguyen.actionbuttonmulticlick")
#define TestNotice CFSTR("com.huynguyen.actionbuttonmulticlick/testCurrentAction")
#define LinksKey CFSTR("savedLinks")

typedef struct { NSString *identifier; NSString *title; NSString *icon; } ActionInfo;
static const ActionInfo kActions[] = {
    {@"default", @"系统默认", @"gearshape.fill"}, {@"flashlight", @"手电筒", @"flashlight.on.fill"},
    {@"camera", @"相机", @"camera.fill"}, {@"silent", @"静音切换", @"bell.slash.fill"},
    {@"screenshot", @"截屏", @"viewfinder"}, {@"lock", @"锁屏", @"lock.fill"},
    {@"controlCenter", @"控制中心", @"switch.2"}, {@"notificationCenter", @"通知中心", @"bell.fill"},
    {@"settings", @"打开设置", @"gearshape.fill"}, {@"respring", @"重启界面", @"arrow.clockwise"},
    {@"wechatScan", @"微信扫码", @"qrcode.viewfinder"}, {@"wechatPay", @"微信付款码", @"creditcard.fill"},
    {@"alipayScan", @"支付宝扫码", @"qrcode.viewfinder"}, {@"alipayPay", @"支付宝付款码", @"creditcard.fill"},
    {@"none", @"无操作", @"nosign"}
};

static const ActionInfo *InfoForAction(NSString *action) {
    for (NSUInteger i = 0; i < sizeof(kActions) / sizeof(kActions[0]); i++) if ([action isEqualToString:kActions[i].identifier]) return &kActions[i];
    return NULL;
}
static NSString *SavedURLTitle(NSString *identifier) {
    CFPropertyListRef value = CFPreferencesCopyAppValue(LinksKey, Domain);
    NSString *title = nil;
    if (value && CFGetTypeID(value) == CFArrayGetTypeID()) {
        for (NSDictionary *item in (__bridge NSArray *)value) if ([item isKindOfClass:[NSDictionary class]] && [item[@"id"] isEqualToString:identifier]) { title = [item[@"title"] copy]; break; }
    }
    if (value) CFRelease(value);
    return title;
}
static NSString *TitleForAction(NSString *action) {
    const ActionInfo *info = InfoForAction(action);
    if (info) return info->title;
    if ([action hasPrefix:@"app:"]) return ABMCApplicationName([action substringFromIndex:4]);
    if ([action hasPrefix:@"appshortcut:"]) { NSArray *p = [[action substringFromIndex:12] componentsSeparatedByString:@"|"]; return p.count > 2 && [p[2] length] ? p[2] : @"快捷方式"; }
    if ([action hasPrefix:@"shortcutid:"]) { NSArray *p = [[action substringFromIndex:11] componentsSeparatedByString:@"|"]; return p.count > 1 ? p[1] : @"快捷指令"; }
    if ([action hasPrefix:@"shortcut:"]) return [action substringFromIndex:9];
    if ([action hasPrefix:@"link:"]) return SavedURLTitle([action substringFromIndex:5]) ?: @"URL（未找到）";
    if ([action hasPrefix:@"url:"]) return [action substringFromIndex:4];
    return @"无操作";
}
static UIImage *IconForAction(NSString *action) {
    const ActionInfo *info = InfoForAction(action);
    if (info) return ABMCTintedIcon(info->icon, UIColor.systemBlueColor);
    if ([action hasPrefix:@"app:"]) return ABMCIconImageForBundleID([action substringFromIndex:4]);
    if ([action hasPrefix:@"appshortcut:"]) { NSArray *p = [[action substringFromIndex:12] componentsSeparatedByString:@"|"]; return p.count ? ABMCIconImageForBundleID(p[0]) : nil; }
    if ([action hasPrefix:@"shortcutid:"]) return ABMCShortcutIconForIdentifier([[[action substringFromIndex:11] componentsSeparatedByString:@"|"] firstObject]);
    if ([action hasPrefix:@"link:"] || [action hasPrefix:@"url:"]) return ABMCTintedIcon(@"link", UIColor.systemBlueColor);
    return ABMCTintedIcon(@"questionmark.circle", UIColor.systemBlueColor);
}

@interface ABMCActionListController ()
@end
@implementation ABMCActionListController { NSString *_key; NSString *_fallback; NSString *_current; }
- (void)viewDidLoad { [super viewDidLoad]; PSSpecifier *p=self.specifier; _key=[[p propertyForKey:@"key"] copy]; _fallback=[[p propertyForKey:@"default"] copy]; self.title=[p name].length?[p name]:@"选择动作"; }
- (void)viewWillAppear:(BOOL)animated { [super viewWillAppear:animated]; CFStringRef v=(CFStringRef)CFPreferencesCopyAppValue((__bridge CFStringRef)_key,Domain); _current=v?(__bridge_transfer NSString *)v:(_fallback?:@"none"); _specifiers=nil; [self reloadSpecifiers]; }
- (NSArray *)specifiers {
    if (_specifiers) return _specifiers;
    NSMutableArray *items=[NSMutableArray array];
    [items addObject:[PSSpecifier groupSpecifierWithName:@"已选动作"]];
    PSSpecifier *selected=[PSSpecifier preferenceSpecifierNamed:TitleForAction(_current) target:self set:NULL get:NULL detail:Nil cell:PSStaticTextCell edit:Nil];
    [selected setProperty:@YES forKey:@"selectedAction"]; [items addObject:selected];
    [items addObject:[PSSpecifier groupSpecifierWithName:@"动作测试"]];
    PSSpecifier *test=[PSSpecifier preferenceSpecifierNamed:@"开始测试" target:self set:NULL get:NULL detail:Nil cell:PSButtonCell edit:Nil];
    [test setProperty:@"play.fill" forKey:@"iconToken"]; test->action=@selector(test:); [items addObject:test];
    [items addObject:[PSSpecifier groupSpecifierWithName:@"选择动作"]];
    NSArray *entries=@[@[@"基础动作",@"builtin",@"hand.tap.fill"],@[@"应用列表",@"app",@"app.badge.checkmark"],@[@"快捷方式",@"appshortcut",@"square.grid.2x2.fill"],@[@"快捷指令",@"shortcut",@"square.stack.3d.up.fill"],@[@"URL",@"link",@"link"]];
    for (NSArray *entry in entries) { PSSpecifier *s=[PSSpecifier preferenceSpecifierNamed:entry[0] target:self set:NULL get:NULL detail:Nil cell:PSLinkCell edit:Nil]; [s setProperty:entry[1] forKey:@"category"]; [s setProperty:entry[2] forKey:@"iconToken"]; s->action=@selector(open:); [items addObject:s]; }
    _specifiers=items; return _specifiers;
}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell=[super tableView:tableView cellForRowAtIndexPath:indexPath]; PSSpecifier *s=[self specifierAtIndexPath:indexPath];
    cell.accessoryView=nil; cell.imageView.hidden=NO; cell.imageView.image=nil; cell.textLabel.textColor=UIColor.labelColor; cell.textLabel.font=[UIFont systemFontOfSize:18 weight:UIFontWeightRegular];
    if ([s propertyForKey:@"selectedAction"]) ABMCApplyLargeIcon(cell, IconForAction(_current));
    else { NSString *token=[s propertyForKey:@"iconToken"]; if (token.length) ABMCApplyLargeIcon(cell, ABMCTintedIcon(token, UIColor.systemBlueColor)); }
    return cell;
}
- (void)open:(PSSpecifier *)specifier { NSString *category=[specifier propertyForKey:@"category"]; UIViewController *controller=nil; if([category isEqualToString:@"builtin"])controller=[[ABMCBuiltinListController alloc]initWithPreferenceKey:_key]; else if([category isEqualToString:@"app"])controller=[[ABMCApplicationListController alloc]initWithPreferenceKey:_key]; else if([category isEqualToString:@"appshortcut"])controller=[[ABMCAppShortcutListController alloc]initWithPreferenceKey:_key]; else if([category isEqualToString:@"shortcut"])controller=[[ABMCShortcutListController alloc]initWithPreferenceKey:_key]; else if([category isEqualToString:@"link"])controller=[[ABMCLinkListController alloc]initWithPreferenceKey:_key]; if(controller)[self.navigationController pushViewController:controller animated:YES]; }
- (void)test:(PSSpecifier *)specifier { if(!_current.length||[_current isEqualToString:@"none"])return; CFPreferencesSetAppValue(CFSTR("testAction"),(__bridge CFPropertyListRef)_current,Domain); CFPreferencesAppSynchronize(Domain); CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),TestNotice,NULL,NULL,YES); }
@end
