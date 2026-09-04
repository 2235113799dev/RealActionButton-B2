#import "ABMCActionListController.h"
#import "ABMCApplicationListController.h"
#import "ABMCShortcutListController.h"
#import "ABMCLinkListController.h"
#import "ABMCBuiltinListController.h"
#import "ABMCUIHelpers.h"
#import <Preferences/PSSpecifier.h>
#import <objc/runtime.h>

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
    if ([action hasPrefix:@"shortcutid:"]) { NSArray *p = [[action substringFromIndex:11] componentsSeparatedByString:@"|"]; return p.count > 1 ? p[1] : @"快捷指令"; }
    if ([action hasPrefix:@"actionpanel:"]) return @"已选动作组合";
    if ([action hasPrefix:@"shortcut:"]) return [action substringFromIndex:9];
    if ([action hasPrefix:@"link:"]) return SavedURLTitle([action substringFromIndex:5]) ?: @"URL（未找到）";
    if ([action hasPrefix:@"url:"]) return [action substringFromIndex:4];
    return @"无操作";
}
static NSString *PresentationKeyForAction(NSString *action) {
    if ([action hasPrefix:@"app:"]) return [@"app." stringByAppendingString:[action substringFromIndex:4]];
    if ([action hasPrefix:@"shortcutid:"]) return [@"shortcut." stringByAppendingString:[[action substringFromIndex:11] componentsSeparatedByString:@"|"].firstObject ?: @""];
    if ([action hasPrefix:@"link:"]) return [@"link." stringByAppendingString:[action substringFromIndex:5]];
    return [@"action." stringByAppendingString:action ?: @"none"];
}
static NSString *DisplayedTitleForAction(NSString *action) { return ABMCDisplayTitle(PresentationKeyForAction(action), TitleForAction(action)); }
static UIImage *IconForAction(NSString *action) { return ABMCSelectedActionIcon(action); }

@interface ABMCActionListController ()
@end
@implementation ABMCActionListController { NSString *_key; NSString *_fallback; NSString *_current; }
- (void)viewDidLoad { [super viewDidLoad]; PSSpecifier *p=self.specifier; _key=[[p propertyForKey:@"key"] copy]; _fallback=[[p propertyForKey:@"default"] copy]; self.title=[p name].length?[p name]:@"选择动作"; }
- (void)viewWillAppear:(BOOL)animated { [super viewWillAppear:animated]; CFStringRef v=(CFStringRef)CFPreferencesCopyAppValue((__bridge CFStringRef)_key,Domain); _current=v?(__bridge_transfer NSString *)v:(_fallback?:@"none"); _specifiers=nil; [self reloadSpecifiers]; }
- (NSArray *)specifiers {
    if (_specifiers) return _specifiers;
    NSMutableArray *items=[NSMutableArray array];
    [items addObject:[PSSpecifier groupSpecifierWithName:@"已选动作"]];
    NSArray *selectedActions=ABMCSelectedActions(_key); if(!selectedActions.count) selectedActions=@[@"none"];
    for(NSString *action in selectedActions){ PSSpecifier *selected=[PSSpecifier preferenceSpecifierNamed:DisplayedTitleForAction(action) target:self set:NULL get:NULL detail:Nil cell:PSButtonCell edit:Nil]; [selected setProperty:@YES forKey:@"selectedAction"]; [selected setProperty:action forKey:@"actionID"]; [items addObject:selected]; }
    [items addObject:[PSSpecifier groupSpecifierWithName:@"动作测试"]];
    PSSpecifier *test=[PSSpecifier preferenceSpecifierNamed:@"开始测试" target:self set:NULL get:NULL detail:Nil cell:PSButtonCell edit:Nil];
    [test setProperty:@"play.fill" forKey:@"iconToken"]; test->action=@selector(test:); [items addObject:test];
    [items addObject:[PSSpecifier groupSpecifierWithName:@"选择动作"]];
    NSArray *entries=@[@[@"基础动作",@"builtin",@"hand.tap.fill"],@[@"应用列表",@"app",@"app.badge.checkmark"],@[@"指令列表",@"shortcut",@"square.stack.3d.up.fill"],@[@"URL",@"link",@"link"]];
    for (NSArray *entry in entries) { NSString *key=[@"group." stringByAppendingString:entry[1]]; PSSpecifier *s=[PSSpecifier preferenceSpecifierNamed:ABMCDisplayTitle(key,entry[0]) target:self set:NULL get:NULL detail:Nil cell:PSLinkCell edit:Nil]; [s setProperty:entry[1] forKey:@"category"]; [s setProperty:entry[2] forKey:@"defaultIcon"]; [s setProperty:key forKey:@"presentationKey"]; s->action=@selector(open:); [items addObject:s]; }
    _specifiers=items; return _specifiers;
}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell=[super tableView:tableView cellForRowAtIndexPath:indexPath]; PSSpecifier *s=[self specifierAtIndexPath:indexPath];
    cell.accessoryView=nil; cell.imageView.hidden=NO; cell.imageView.image=nil; ABMCApplyActionTextStyle(cell,UIColor.labelColor);
    if ([s propertyForKey:@"selectedAction"]) { NSString *action=[s propertyForKey:@"actionID"] ?: @"none"; ABMCApplyLargeIcon(cell, IconForAction(action)); cell.textLabel.textColor=ABMCActionTextColor([action isEqualToString:@"none"] ? UIColor.systemRedColor : UIColor.systemBlueColor); ABMCInstallPresentationLongPress(cell,self,PresentationKeyForAction(action),DisplayedTitleForAction(action),ABMCDisplayIconToken(PresentationKeyForAction(action),@"hand.tap.fill"),^{self->_specifiers=nil;[self reloadSpecifiers];}); if(!objc_getAssociatedObject(cell,@selector(doubleTapSelected:))){UITapGestureRecognizer *tap=[[UITapGestureRecognizer alloc]initWithTarget:self action:@selector(doubleTapSelected:)];tap.numberOfTapsRequired=2;tap.cancelsTouchesInView=YES;tap.delaysTouchesEnded=YES;objc_setAssociatedObject(tap,@selector(doubleTapSelected:),action,OBJC_ASSOCIATION_COPY_NONATOMIC);[cell.contentView addGestureRecognizer:tap];objc_setAssociatedObject(cell,@selector(doubleTapSelected:),tap,OBJC_ASSOCIATION_RETAIN_NONATOMIC);}else{UITapGestureRecognizer *tap=objc_getAssociatedObject(cell,@selector(doubleTapSelected:));objc_setAssociatedObject(tap,@selector(doubleTapSelected:),action,OBJC_ASSOCIATION_COPY_NONATOMIC);} }
    else if ([[s propertyForKey:@"iconToken"] length]) { ABMCApplyLargeIcon(cell, ABMCTintedIcon([s propertyForKey:@"iconToken"], nil)); }
    else { NSString *key=[s propertyForKey:@"presentationKey"],*fallback=[s propertyForKey:@"defaultIcon"]; if (fallback.length) { NSString *token=ABMCDisplayIconToken(key,fallback); ABMCApplyLargeIcon(cell, ABMCTintedIcon(token,nil) ?: ABMCIconImageForBundleID(token) ?: ABMCTintedIcon(@"square.grid.2x2.fill",nil)); ABMCInstallPresentationLongPress(cell,self,key,ABMCDisplayTitle(key,[s name]),token,^{self->_specifiers=nil;[self reloadSpecifiers];}); } }
    return cell;
}


- (void)doubleTapSelected:(UITapGestureRecognizer *)gesture { if(gesture.state!=UIGestureRecognizerStateRecognized)return;NSString *action=objc_getAssociatedObject(gesture,@selector(doubleTapSelected:));NSMutableArray *items=[ABMCSelectedActions(_key) mutableCopy];if(action.length)[items removeObject:action];ABMCStoreSelectedActions(_key,items);_current=items.count?@"actionpanel":@"none";_specifiers=nil;[self reloadSpecifiers]; }
- (void)clearCurrentAction { ABMCStoreSelectedActions(_key,@[]);_current=@"none";_specifiers=nil;[self reloadSpecifiers]; }

- (void)open:(PSSpecifier *)specifier { NSString *category=[specifier propertyForKey:@"category"]; UIViewController *controller=nil; if([category isEqualToString:@"builtin"])controller=[[ABMCBuiltinListController alloc]initWithPreferenceKey:_key]; else if([category isEqualToString:@"app"])controller=[[ABMCApplicationListController alloc]initWithPreferenceKey:_key]; else if([category isEqualToString:@"shortcut"])controller=[[ABMCShortcutListController alloc]initWithPreferenceKey:_key]; else if([category isEqualToString:@"link"])controller=[[ABMCLinkListController alloc]initWithPreferenceKey:_key]; if(controller)[self.navigationController pushViewController:controller animated:YES]; }
- (void)test:(PSSpecifier *)specifier { if(!_current.length||[_current isEqualToString:@"none"])return; CFPreferencesSetAppValue(CFSTR("testAction"),(__bridge CFPropertyListRef)_current,Domain); CFPreferencesAppSynchronize(Domain); CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),TestNotice,NULL,NULL,YES); }
@end
