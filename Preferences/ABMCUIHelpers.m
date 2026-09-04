#import "ABMCUIHelpers.h"
#import <math.h>
#import <objc/message.h>
#import <dlfcn.h>
#import <sqlite3.h>

@interface UIImage (ABMCPrivateIcon)
+ (instancetype)_applicationIconImageForBundleIdentifier:(NSString *)identifier format:(int)format scale:(CGFloat)scale;
@end

static id ObjectCall(id object, NSString *name) {
    SEL selector = NSSelectorFromString(name);
    return object && [object respondsToSelector:selector] ? ((id (*)(id, SEL))objc_msgSend)(object, selector) : nil;
}
static BOOL BoolCall(id object, NSString *name) {
    SEL selector = NSSelectorFromString(name);
    return object && [object respondsToSelector:selector] ? ((BOOL (*)(id, SEL))objc_msgSend)(object, selector) : NO;
}

NSString *ABMCBundleIdentifierForApplication(id application) {
    id value = ObjectCall(application, @"bundleIdentifier");
    return [value isKindOfClass:[NSString class]] ? value : nil;
}
NSString *ABMCDisplayNameForApplication(id application) {
    NSString *name = ObjectCall(application, @"localizedName");
    if (name.length) return name;
    NSURL *URL = ObjectCall(application, @"bundleURL");
    NSDictionary *info = [NSBundle bundleWithURL:URL].infoDictionary;
    return info[@"CFBundleDisplayName"] ?: info[@"CFBundleName"] ?: info[@"CFBundleExecutable"];
}

static BOOL IsDisplayableApplication(id application) {
    NSString *identifier = ABMCBundleIdentifierForApplication(application);
    NSURL *URL = ObjectCall(application, @"bundleURL");
    NSString *path = URL.path;
    NSString *type = ObjectCall(application, @"applicationType");
    if (!identifier.length || !path.length || ![path.pathExtension.lowercaseString isEqualToString:@"app"]) return NO;
    if (![type isEqualToString:@"User"] && ![type isEqualToString:@"System"]) return NO;
    // Service proxies have no declared primary icon and would render UIKit's
    // generic white blueprint. Exclude them before any table cell is made.
    NSDictionary *info=[NSBundle bundleWithURL:URL].infoDictionary;
    id icons=info[@"CFBundleIcons"] ?: info[@"CFBundleIconFiles"] ?: info[@"CFBundleIconFile"];
    if (!icons) return NO;
    if (BoolCall(application, @"launchProhibited") || BoolCall(application, @"isLaunchProhibited")) return NO;
    for (NSString *part in @[@"/PlugIns/", @"/Extensions/", @".appex", @"UIService", @"Service", @"Helper", @"Widget"]) if ([path containsString:part]) return NO;
    return YES;
}

ABMCApplicationKind ABMCApplicationKindForProxy(id application) {
    NSURL *URL = ObjectCall(application, @"bundleURL");
    NSString *path = URL.path;
    NSString *container = [path stringByDeletingLastPathComponent];
    NSFileManager *files = NSFileManager.defaultManager;
    if ([files fileExistsAtPath:[container stringByAppendingPathComponent:@"_TrollStore"]] || [files fileExistsAtPath:[container stringByAppendingPathComponent:@"_TrollStoreLite"]] || [path rangeOfString:@"TrollStore" options:NSCaseInsensitiveSearch].location != NSNotFound) return ABMCApplicationKindTrollStore;
    return [[ObjectCall(application, @"applicationType") description] isEqualToString:@"System"] ? ABMCApplicationKindSystem : ABMCApplicationKindUser;
}

NSArray *ABMCInstalledApplications(void) {
    static NSArray *cached; static NSTimeInterval cacheDate=0; NSTimeInterval now=NSDate.date.timeIntervalSinceReferenceDate;
    @synchronized([NSProcessInfo processInfo]) { if(cached && now-cacheDate<30.0) return cached; }
    Class workspaceClass = NSClassFromString(@"LSApplicationWorkspace");
    SEL defaultWorkspace = NSSelectorFromString(@"defaultWorkspace");
    id workspace = workspaceClass && [workspaceClass respondsToSelector:defaultWorkspace] ? ((id (*)(id, SEL))objc_msgSend)(workspaceClass, defaultWorkspace) : nil;
    if (!workspace) return @[];
    NSMutableArray *raw = [NSMutableArray array];
    SEL enumerate = NSSelectorFromString(@"enumerateApplicationsOfType:block:");
    if ([workspace respondsToSelector:enumerate]) {
        void (^collect)(id) = ^(id app) { if (app) [raw addObject:app]; };
        ((void (*)(id, SEL, NSInteger, id))objc_msgSend)(workspace, enumerate, 0, collect);
        ((void (*)(id, SEL, NSInteger, id))objc_msgSend)(workspace, enumerate, 1, collect);
    } else {
        NSArray *all = ObjectCall(workspace, @"allInstalledApplications");
        if ([all isKindOfClass:[NSArray class]]) [raw addObjectsFromArray:all];
    }
    NSMutableArray *result = [NSMutableArray array];
    NSMutableSet *seen = [NSMutableSet set];
    for (id app in raw) {
        NSString *identifier = ABMCBundleIdentifierForApplication(app);
        if (IsDisplayableApplication(app) && identifier.length && ![seen containsObject:identifier]) { [seen addObject:identifier]; [result addObject:app]; }
    }
    NSArray *snapshot=[result copy]; @synchronized([NSProcessInfo processInfo]) { cached=snapshot; cacheDate=now; } return snapshot;
}

#define ABMCDomain CFSTR("com.huynguyen.actionbuttonmulticlick")
#define ABMCPresentationKey CFSTR("presentationOverrides")
#define ABMCUnifiedPointSizeKey CFSTR("unifiedIconSize")
#define ABMCUnifiedColorKey CFSTR("unifiedIconColor")

CGFloat ABMCUnifiedIconSize(void) {
    CFPropertyListRef value=CFPreferencesCopyAppValue(ABMCUnifiedPointSizeKey,ABMCDomain);
    CGFloat size=value&&CFGetTypeID(value)==CFNumberGetTypeID()?[(__bridge NSNumber *)value doubleValue]:30.0;
    if(value)CFRelease(value); return MIN(48.0,MAX(12.0,size));
}
static UIColor *ColorForHex(NSString *text) { NSString*s=[[text ?: @"" stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet]uppercaseString];if([s hasPrefix:@"#"])s=[s substringFromIndex:1];unsigned n=0;NSScanner*scan=[NSScanner scannerWithString:s];if(s.length!=6||![scan scanHexInt:&n]||!scan.isAtEnd)return nil;return[UIColor colorWithRed:((n>>16)&255)/255.0 green:((n>>8)&255)/255.0 blue:(n&255)/255.0 alpha:1]; }
UIColor *ABMCUnifiedIconColor(void) { CFPropertyListRef value=CFPreferencesCopyAppValue(ABMCUnifiedColorKey,ABMCDomain);UIColor*color=ColorForHex(value&&CFGetTypeID(value)==CFStringGetTypeID()?(__bridge NSString*)value:nil)?:UIColor.systemBlueColor;if(value)CFRelease(value);return color; }
NSString *ABMCUnifiedIconColorHex(void) { UIColor*c=ABMCUnifiedIconColor();CGFloat r=0,g=0,b=0,a=0;if(![c getRed:&r green:&g blue:&b alpha:&a])return @"#007AFF";return[NSString stringWithFormat:@"#%02lX%02lX%02lX",lround(r*255),lround(g*255),lround(b*255)]; }
static UIImage *NormalizedIcon(UIImage *image) {
    if (!image || ![image isKindOfClass:UIImage.class]) return nil;
    CGFloat maximum=ABMCUnifiedIconSize(),canvas=maximum+4.0; CGSize size=image.size;
    CGFloat scale=(size.width>0&&size.height>0)?MIN(maximum/size.width,maximum/size.height):1.0;
    CGSize drawSize=CGSizeMake(MAX(1.0,size.width*scale),MAX(1.0,size.height*scale)); CGRect rect=CGRectMake((canvas-drawSize.width)*.5,(canvas-drawSize.height)*.5,drawSize.width,drawSize.height);
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(canvas,canvas),NO,UIScreen.mainScreen.scale);[image drawInRect:rect];UIImage*result=UIGraphicsGetImageFromCurrentImageContext();UIGraphicsEndImageContext();return result;
}
static NSDictionary *PresentationOverrides(void) {
    CFPropertyListRef value = CFPreferencesCopyAppValue(ABMCPresentationKey, ABMCDomain);
    NSDictionary *result = value && CFGetTypeID(value) == CFDictionaryGetTypeID() ? [(__bridge NSDictionary *)value copy] : @{};
    if (value) CFRelease(value); return result;
}
NSString *ABMCDisplayTitle(NSString *key, NSString *fallback) {
    id value = PresentationOverrides()[key][@"title"];
    return [value isKindOfClass:NSString.class] && [value length] ? value : fallback;
}
NSString *ABMCDisplayIconToken(NSString *key, NSString *fallback) {
    id value = PresentationOverrides()[key][@"icon"];
    return [value isKindOfClass:NSString.class] && [value length] ? value : fallback;
}
void ABMCClearPresentationOverride(NSString *key) {
    if (!key.length) return;
    NSMutableDictionary *all = [PresentationOverrides() mutableCopy];
    [all removeObjectForKey:key];
    CFPreferencesSetAppValue(ABMCPresentationKey, (__bridge CFPropertyListRef)all, ABMCDomain);
    CFPreferencesAppSynchronize(ABMCDomain);
}
void ABMCShowPresentationEditor(UIViewController *controller, NSString *key, NSString *defaultTitle, NSString *defaultIcon, dispatch_block_t completion) {
    NSDictionary *saved = PresentationOverrides()[key];
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"修改显示外观" message:@"只修改 RealActionButton 内的名称和图标，不会修改应用或快捷指令本体。图标可填 SF Symbol 名称或 App Bundle ID；留空恢复默认图标。" preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *f) { f.placeholder=@"显示名称"; f.text=ABMCDisplayTitle(key, defaultTitle); }];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *f) { f.placeholder=@"图标（SF Symbol / Bundle ID）"; f.text=[saved[@"icon"] isKindOfClass:NSString.class] && [saved[@"icon"] length] ? saved[@"icon"] : (defaultIcon ?: @""); f.autocorrectionType=UITextAutocorrectionTypeNo; f.autocapitalizationType=UITextAutocapitalizationTypeNone; }];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"恢复默认" style:UIAlertActionStyleDestructive handler:^(__unused UIAlertAction *a) { ABMCClearPresentationOverride(key); if(completion)completion(); }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"保存" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *a) { NSString *title=[alert.textFields[0].text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet]; NSString *icon=[alert.textFields[1].text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet]; if(!title.length||title.length>100)return; NSMutableDictionary *all=[PresentationOverrides() mutableCopy]; all[key]=@{ @"title":title, @"icon":icon ?: @"" }; CFPreferencesSetAppValue(ABMCPresentationKey, (__bridge CFPropertyListRef)all, ABMCDomain); CFPreferencesAppSynchronize(ABMCDomain); if(completion)completion(); }]];
    [controller presentViewController:alert animated:YES completion:nil];
}
static void ABMCNotifyChanged(void) { CFPreferencesAppSynchronize(ABMCDomain); CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),CFSTR("com.huynguyen.actionbuttonmulticlick/prefsChanged"),NULL,NULL,YES); }
static NSMutableDictionary *ABMCActionPanels(void) { CFPropertyListRef v=CFPreferencesCopyAppValue(CFSTR("actionPanels"),ABMCDomain); NSMutableDictionary *r=v&&CFGetTypeID(v)==CFDictionaryGetTypeID()?[(__bridge NSDictionary *)v mutableCopy]:[NSMutableDictionary dictionary]; if(v)CFRelease(v); return r; }
NSArray<NSString *> *ABMCSelectedActions(NSString *preferenceKey) {
    if(!preferenceKey.length)return @[]; CFStringRef raw=(CFStringRef)CFPreferencesCopyAppValue((__bridge CFStringRef)preferenceKey,ABMCDomain); NSString *value=raw?(__bridge_transfer NSString *)raw:nil;
    if([value hasPrefix:@"actionpanel:"]){ NSArray *items=ABMCActionPanels()[[value substringFromIndex:12]]; NSMutableArray *out=[NSMutableArray array]; for(id item in items)if([item isKindOfClass:NSString.class]&&[item length])[out addObject:item]; return out; }

    return value.length&&! [value isEqualToString:@"none"] ? @[value] : @[];
}
void ABMCStoreSelectedActions(NSString *preferenceKey, NSArray<NSString *> *actions) {
    if(!preferenceKey.length)return; NSMutableOrderedSet *unique=[NSMutableOrderedSet orderedSet];for(id item in actions)if([item isKindOfClass:NSString.class]&&[item length])[unique addObject:item];NSArray *values=[unique.array subarrayWithRange:NSMakeRange(0,MIN((NSUInteger)8,unique.count))];
    CFStringRef oldRaw=(CFStringRef)CFPreferencesCopyAppValue((__bridge CFStringRef)preferenceKey,ABMCDomain);NSString *old=oldRaw?(__bridge_transfer NSString *)oldRaw:nil;NSMutableDictionary *panels=ABMCActionPanels();if([old hasPrefix:@"actionpanel:"])[panels removeObjectForKey:[old substringFromIndex:12]];
    if(!values.count){CFPreferencesSetAppValue((__bridge CFStringRef)preferenceKey,CFSTR("none"),ABMCDomain);}else if(values.count==1){CFPreferencesSetAppValue((__bridge CFStringRef)preferenceKey,(__bridge CFPropertyListRef)values.firstObject,ABMCDomain);}else{NSString *panelID=NSUUID.UUID.UUIDString;panels[panelID]=values;CFPreferencesSetAppValue((__bridge CFStringRef)preferenceKey,(__bridge CFPropertyListRef)[@"actionpanel:" stringByAppendingString:panelID],ABMCDomain);}
    CFPreferencesSetAppValue(CFSTR("actionPanels"),(__bridge CFPropertyListRef)panels,ABMCDomain);ABMCNotifyChanged();
}

static NSString *ABMCBriefActionTitle(NSString *action) {
    if([action hasPrefix:@"shortcutid:"]){NSArray *p=[[action substringFromIndex:11]componentsSeparatedByString:@"|"];return p.count>1?p[1]:@"快捷指令";}
    if([action hasPrefix:@"app:"])return ABMCApplicationName([action substringFromIndex:4]) ?: @"应用";
    if([action hasPrefix:@"link:"]){CFPropertyListRef v=CFPreferencesCopyAppValue(CFSTR("savedLinks"),ABMCDomain);NSString *title=nil;for(NSDictionary*x in (v&&CFGetTypeID(v)==CFArrayGetTypeID()?(__bridge NSArray*)v:@[]))if([x[@"id"]isEqual:[action substringFromIndex:5]]){title=x[@"title"];break;}if(v)CFRelease(v);return title ?: @"URL";}
    if([action hasPrefix:@"url:"])return [action substringFromIndex:4];
    NSDictionary *n=@{ @"default":@"系统默认",@"flashlight":@"手电筒",@"camera":@"相机",@"silent":@"静音切换",@"screenshot":@"截屏",@"lock":@"锁屏",@"controlCenter":@"控制中心",@"notificationCenter":@"通知中心",@"settings":@"设置",@"respring":@"重启",@"wechatScan":@"微信扫码",@"wechatPay":@"微信付款码",@"alipayScan":@"支付宝扫码",@"alipayPay":@"支付宝付款码"};return n[action] ?: @"动作";
}
static NSDictionary *ABMCLinkRecord(NSString *identifier);
static UIImage *ABMCBriefActionIcon(NSString *action) {
    if([action hasPrefix:@"app:"])return ABMCIconImageForBundleID([action substringFromIndex:4]) ?: ABMCTintedIcon(@"app.fill",nil);
    if([action hasPrefix:@"shortcutid:"]){NSArray*p=[[action substringFromIndex:11]componentsSeparatedByString:@"|"];return p.count>3?ABMCWorkflowIconImage([p[2]integerValue],[p[3]longLongValue]) ?: ABMCTintedIcon(@"square.stack.3d.up.fill",nil):ABMCTintedIcon(@"square.stack.3d.up.fill",nil);}
    if([action hasPrefix:@"link:"]){NSDictionary *record=ABMCLinkRecord([action substringFromIndex:5]);NSString *token=record[@"icon"];return ABMCIconImageForBundleID(token) ?: ABMCTintedIcon(token,nil) ?: ABMCTintedIcon(@"link",nil);}
    if([action hasPrefix:@"url:"])return ABMCTintedIcon(@"link",nil);
    NSDictionary *icons=@{ @"default":@"gearshape.fill",@"flashlight":@"flashlight.on.fill",@"camera":@"camera.fill",@"silent":@"bell.slash.fill",@"screenshot":@"viewfinder",@"lock":@"lock.fill",@"controlCenter":@"switch.2",@"notificationCenter":@"bell.fill",@"settings":@"gearshape.fill",@"respring":@"arrow.clockwise",@"wechatScan":@"qrcode.viewfinder",@"wechatPay":@"creditcard.fill",@"alipayScan":@"qrcode.viewfinder",@"alipayPay":@"creditcard.fill"};return ABMCTintedIcon(icons[action] ?: @"square.grid.2x2.fill",nil);
}
@interface ABMCSelectedRowTarget : NSObject
@property(nonatomic,weak) UIViewController *controller; @property(nonatomic,copy) NSString *preferenceKey,*action;
- (void)longPress:(UILongPressGestureRecognizer *)gesture; - (void)doubleTap:(UITapGestureRecognizer *)gesture;
@end
@implementation ABMCSelectedRowTarget
- (void)refresh { if([self.controller respondsToSelector:NSSelectorFromString(@"refreshHeader")]) ((void(*)(id,SEL))objc_msgSend)(self.controller,NSSelectorFromString(@"refreshHeader")); if([self.controller isKindOfClass:UITableViewController.class]) [((UITableViewController *)self.controller).tableView reloadData]; else if([self.controller respondsToSelector:@selector(reloadSpecifiers)]) ((void(*)(id,SEL))objc_msgSend)(self.controller,@selector(reloadSpecifiers)); }
- (void)longPress:(UILongPressGestureRecognizer *)gesture { if(gesture.state!=UIGestureRecognizerStateBegan)return; NSString *action=self.action ?: @"none"; NSString *key=[action hasPrefix:@"app:"]?[@"app." stringByAppendingString:[action substringFromIndex:4]]:([action hasPrefix:@"shortcutid:"]?[@"shortcut." stringByAppendingString:[[action substringFromIndex:11] componentsSeparatedByString:@"|"].firstObject ?: @""] : ([action hasPrefix:@"link:"]?[@"link." stringByAppendingString:[action substringFromIndex:5]]:[@"action." stringByAppendingString:action])); ABMCShowPresentationEditor(self.controller,key,ABMCBriefActionTitle(action),@"hand.tap.fill",^{[self refresh];}); }
- (void)doubleTap:(UITapGestureRecognizer *)gesture { if(gesture.state==UIGestureRecognizerStateRecognized){NSMutableArray *items=[ABMCSelectedActions(self.preferenceKey) mutableCopy];[items removeObject:self.action];ABMCStoreSelectedActions(self.preferenceKey,items);[self refresh];} }
@end
static NSDictionary *ABMCLinkRecord(NSString *identifier) { CFPropertyListRef raw=CFPreferencesCopyAppValue(CFSTR("savedLinks"),ABMCDomain);NSDictionary *result=nil;for(NSDictionary *item in (raw&&CFGetTypeID(raw)==CFArrayGetTypeID()?(__bridge NSArray *)raw:@[]))if([item[@"id"] isEqualToString:identifier]){result=[item copy];break;}if(raw)CFRelease(raw);return result; }
UIView *ABMCSelectedActionsBanner(NSString *preferenceKey, UIViewController *controller) {
    NSArray *items=ABMCSelectedActions(preferenceKey);NSUInteger count=MAX((NSUInteger)1,items.count);CGFloat row=44,top=26,height=top+count*row+12;
    CGFloat width=controller.view.bounds.size.width; if(width<100) width=UIScreen.mainScreen.bounds.size.width;
    UIView *box=[[UIView alloc]initWithFrame:CGRectMake(0,0,width,height)];box.autoresizingMask=UIViewAutoresizingFlexibleWidth;
    UILabel *caption=[[UILabel alloc]initWithFrame:CGRectMake(20,2,240,20)];caption.text=@"已选动作";caption.textColor=UIColor.secondaryLabelColor;caption.font=[UIFont systemFontOfSize:16];[box addSubview:caption];
    // Match the inset-grouped list card below instead of spanning wider.
    UIView *card=[[UIView alloc]initWithFrame:CGRectMake(20,top,box.bounds.size.width-40,count*row)];card.autoresizingMask=UIViewAutoresizingFlexibleWidth;card.backgroundColor=UIColor.secondarySystemGroupedBackgroundColor;card.layer.cornerRadius=15;[box addSubview:card];
    NSArray *rows=items.count?items:@[@"none"];for(NSUInteger i=0;i<rows.count;i++){NSString *action=rows[i];BOOL none=[action isEqualToString:@"none"];UIView *rowView=[[UIView alloc]initWithFrame:CGRectMake(0,i*row,card.bounds.size.width,row)];rowView.autoresizingMask=UIViewAutoresizingFlexibleWidth;rowView.userInteractionEnabled=YES;[card addSubview:rowView];UIImageView *image=[[UIImageView alloc]initWithImage:none?ABMCTintedIcon(@"nosign",UIColor.systemRedColor):ABMCBriefActionIcon(action)];image.frame=CGRectMake(18,10,24,24);image.contentMode=UIViewContentModeScaleAspectFit;[rowView addSubview:image];UILabel *label=[[UILabel alloc]initWithFrame:CGRectMake(56,0,rowView.bounds.size.width-66,row)];label.autoresizingMask=UIViewAutoresizingFlexibleWidth;label.text=none?@"无操作":ABMCBriefActionTitle(action);label.textColor=none?UIColor.systemRedColor:UIColor.systemBlueColor;label.font=[UIFont systemFontOfSize:17 weight:UIFontWeightRegular];[rowView addSubview:label];ABMCSelectedRowTarget *target=[ABMCSelectedRowTarget new];target.controller=controller;target.preferenceKey=preferenceKey;target.action=action;UILongPressGestureRecognizer *longPress=[[UILongPressGestureRecognizer alloc]initWithTarget:target action:@selector(longPress:)];longPress.minimumPressDuration=.45;[rowView addGestureRecognizer:longPress];UITapGestureRecognizer *doubleTap=[[UITapGestureRecognizer alloc]initWithTarget:target action:@selector(doubleTap:)];doubleTap.numberOfTapsRequired=2;[rowView addGestureRecognizer:doubleTap];objc_setAssociatedObject(rowView,@selector(ABMCSelectedActionsBanner),target,OBJC_ASSOCIATION_RETAIN_NONATOMIC);if(i+1<rows.count){UIView *line=[[UIView alloc]initWithFrame:CGRectMake(56,row-0.5,rowView.bounds.size.width-56,.5)];line.autoresizingMask=UIViewAutoresizingFlexibleWidth;line.backgroundColor=UIColor.separatorColor;[rowView addSubview:line];}}
    return box;
}

@interface ABMCPresentationLongPressTarget : NSObject
@property (nonatomic, weak) UIViewController *controller;
@property (nonatomic, copy) NSString *key, *title, *icon;
@property (nonatomic, copy) dispatch_block_t completion;
- (void)pressed:(UILongPressGestureRecognizer *)gesture;
@end
@implementation ABMCPresentationLongPressTarget
- (void)pressed:(UILongPressGestureRecognizer *)gesture {
    if (gesture.state != UIGestureRecognizerStateBegan || !self.controller || !self.key.length) return;
    ABMCShowPresentationEditor(self.controller,self.key,self.title,self.icon,self.completion);
}
@end
void ABMCInstallPresentationLongPress(UITableViewCell *cell, UIViewController *controller, NSString *key, NSString *title, NSString *icon, dispatch_block_t completion) {
    if (!cell || !key.length) return;
    static const void *kTargetKey=&kTargetKey;
    ABMCPresentationLongPressTarget *target=objc_getAssociatedObject(cell,kTargetKey);
    if(!target){ target=[ABMCPresentationLongPressTarget new]; UILongPressGestureRecognizer *gesture=[[UILongPressGestureRecognizer alloc]initWithTarget:target action:@selector(pressed:)]; gesture.minimumPressDuration=0.45; gesture.cancelsTouchesInView=YES; [(cell.contentView ?: cell) addGestureRecognizer:gesture]; objc_setAssociatedObject(cell,kTargetKey,target,OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
    target.controller=controller; target.key=key; target.title=title; target.icon=icon; target.completion=completion;
}

UIImage *ABMCIconImageForBundleID(NSString *identifier) {
    if (!identifier.length) return nil;
    static NSCache *cache;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ cache = [NSCache new]; cache.countLimit = 80; });
    UIImage *cached = [cache objectForKey:identifier];
    if (cached) return cached;
    @try {
        // Cache the original image. ABMCApplyLargeIcon applies the optional
        // global canvas later, so toggling the setting takes effect instantly.
        UIImage *result = [UIImage _applicationIconImageForBundleIdentifier:identifier format:0 scale:UIScreen.mainScreen.scale];
        if (result) [cache setObject:result forKey:identifier];
        return result;
    } @catch (NSException *exception) { return nil; }
}
UIImage *ABMCIconImageForProxy(id application) { return ABMCIconImageForBundleID(ABMCBundleIdentifierForApplication(application)); }
BOOL ABMCApplicationHasRealIcon(id application) {
    NSString *identifier=ABMCBundleIdentifierForApplication(application);
    if (!application || !identifier.length || BoolCall(application,@"isPlaceholder") || BoolCall(application,@"isApplicationPlaceholder") || BoolCall(application,@"isHidden") || BoolCall(application,@"launchProhibited") || BoolCall(application,@"isLaunchProhibited")) return NO;
    static NSCache *results; static dispatch_once_t once;
    dispatch_once(&once, ^{ results=[NSCache new]; results.countLimit=256; });
    NSNumber *cached=[results objectForKey:identifier]; if(cached) return cached.boolValue;
    UIImage *icon=ABMCIconImageForProxy(application); if(!icon){[results setObject:@NO forKey:identifier];return NO;}
    // LaunchServices returns the generic white blueprint for service proxies.
    // Compare only once per Bundle ID, then cache the boolean for all later opens.
    static NSData *blueprint; static dispatch_once_t blueprintOnce;
    dispatch_once(&blueprintOnce, ^{ UIImage *sample=ABMCIconImageForBundleID(@"com.apple.AccountAuthenticationDialog"); blueprint=sample?UIImagePNGRepresentation(sample):nil; });
    BOOL real=!blueprint.length || ![UIImagePNGRepresentation(icon) isEqualToData:blueprint];
    [results setObject:@(real) forKey:identifier]; return real;
}

UIImage *ABMCWorkflowIconImage(NSInteger glyph, long long backgroundColor) {
    if (glyph <= 0) return nil;
    static NSCache *cache;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ cache = [NSCache new]; cache.countLimit = 80; });
    NSString *key = [NSString stringWithFormat:@"%ld:%lld", (long)glyph, backgroundColor];
    UIImage *cached = [cache objectForKey:key];
    if (cached) return cached;
    @try {
        dlopen("/System/Library/PrivateFrameworks/VoiceShortcutClient.framework/VoiceShortcutClient", RTLD_LAZY | RTLD_LOCAL);
        Class iconClass = NSClassFromString(@"WFWorkflowIcon");
        Class drawerClass = NSClassFromString(@"WFWorkflowIconDrawer");
        SEL makeIcon = NSSelectorFromString(@"initWithBackgroundColorValue:glyphCharacter:customImageData:");
        SEL draw = NSSelectorFromString(@"imageWithIcon:size:background:");
        if (![iconClass instancesRespondToSelector:makeIcon] || ![drawerClass respondsToSelector:draw]) return nil;
        id icon = ((id (*)(id, SEL, long long, unsigned short, id))objc_msgSend)([iconClass alloc], makeIcon, backgroundColor, (unsigned short)glyph, nil);
        id rendered = icon ? ((id (*)(id, SEL, id, CGSize, BOOL))objc_msgSend)(drawerClass, draw, icon, CGSizeMake(34, 34), YES) : nil;
        // iOS 17.3 returns WFImage here, not UIImage. Convert it before any
        // UITableView sizing/rendering code touches it.
        SEL uiImage = NSSelectorFromString(@"UIImage");
        UIImage *result = [rendered isKindOfClass:UIImage.class] ? rendered : ([rendered respondsToSelector:uiImage] ? ((id (*)(id, SEL))objc_msgSend)(rendered, uiImage) : nil);
        if ([result isKindOfClass:UIImage.class]) [cache setObject:result forKey:key];
        return [result isKindOfClass:UIImage.class] ? result : nil;
    } @catch (NSException *exception) { return nil; }
}

UIImage *ABMCWorkflowIconForIdentifier(NSString *identifier) {
    if (!identifier.length) return nil;
    static NSCache *cache; static dispatch_once_t once; dispatch_once(&once, ^{ cache=[NSCache new]; cache.countLimit=80; });
    UIImage *saved=[cache objectForKey:identifier]; if(saved)return saved;
    for(NSString *path in @[@"/private/var/mobile/Library/Shortcuts/Shortcuts.sqlite",@"/var/mobile/Library/Shortcuts/Shortcuts.sqlite"]) {
        sqlite3 *db=NULL; if(sqlite3_open_v2(path.fileSystemRepresentation,&db,SQLITE_OPEN_READONLY|SQLITE_OPEN_NOMUTEX,NULL)!=SQLITE_OK){if(db)sqlite3_close(db);continue;}
        sqlite3_stmt *s=NULL;UIImage *result=nil;const char *sql="SELECT COALESCE(i.ZGLYPHNUMBER,0),COALESCE(i.ZBACKGROUNDCOLORVALUE,0) FROM ZSHORTCUT x LEFT JOIN ZSHORTCUTICON i ON i.Z_PK=x.ZICON WHERE upper(x.ZWORKFLOWID)=upper(?) LIMIT 1";
        if(sqlite3_prepare_v2(db,sql,-1,&s,NULL)==SQLITE_OK){sqlite3_bind_text(s,1,identifier.UTF8String,-1,SQLITE_TRANSIENT);if(sqlite3_step(s)==SQLITE_ROW)result=ABMCWorkflowIconImage(sqlite3_column_int64(s,0),sqlite3_column_int64(s,1));}if(s)sqlite3_finalize(s);sqlite3_close(db);if(result){[cache setObject:result forKey:identifier];return result;}
    }return nil;
}

UIImage *ABMCWorkflowIconForName(NSString *name) {
    if (!name.length) return nil;
    for(NSString *path in @[@"/private/var/mobile/Library/Shortcuts/Shortcuts.sqlite",@"/var/mobile/Library/Shortcuts/Shortcuts.sqlite"]) {
        sqlite3 *db=NULL;if(sqlite3_open_v2(path.fileSystemRepresentation,&db,SQLITE_OPEN_READONLY|SQLITE_OPEN_NOMUTEX,NULL)!=SQLITE_OK){if(db)sqlite3_close(db);continue;}sqlite3_stmt*s=NULL;UIImage*result=nil;const char*q="SELECT COALESCE(i.ZGLYPHNUMBER,0),COALESCE(i.ZBACKGROUNDCOLORVALUE,0) FROM ZSHORTCUT x LEFT JOIN ZSHORTCUTICON i ON i.Z_PK=x.ZICON WHERE x.ZNAME=? AND COALESCE(x.ZTOMBSTONED,0)=0 LIMIT 1";if(sqlite3_prepare_v2(db,q,-1,&s,NULL)==SQLITE_OK){sqlite3_bind_text(s,1,name.UTF8String,-1,SQLITE_TRANSIENT);if(sqlite3_step(s)==SQLITE_ROW)result=ABMCWorkflowIconImage(sqlite3_column_int64(s,0),sqlite3_column_int64(s,1));}if(s)sqlite3_finalize(s);sqlite3_close(db);if(result)return result;
    }return nil;
}

UIImage *ABMCIconImage(NSString *token) {
    CGFloat pointSize=ABMCUnifiedIconSize();
    UIImageSymbolConfiguration *config=[UIImageSymbolConfiguration configurationWithPointSize:pointSize weight:UIImageSymbolWeightMedium];
    // Ask for a symbol once. Looking up a non-symbol as an application icon
    // first created the generic blueprint placeholder shown in the report.
    UIImage *symbol=token.length?[UIImage systemImageNamed:token withConfiguration:config]:nil;
    return symbol ?: ABMCIconImageForBundleID(token) ?: [UIImage systemImageNamed:@"app.fill" withConfiguration:config];
}
UIImage *ABMCTintedIcon(NSString *token, UIColor *color) {
    CGFloat pointSize=ABMCUnifiedIconSize();
    UIImage *symbol=[UIImage systemImageNamed:token withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:pointSize weight:UIImageSymbolWeightMedium]];
    // Existing feature rows pass systemBlue. Treat that as the configurable
    // global accent while preserving explicit secondary/error colors.
    UIColor *effective=(!color || [color isEqual:UIColor.systemBlueColor]) ? ABMCUnifiedIconColor() : color;
    return symbol ? [symbol imageWithTintColor:effective renderingMode:UIImageRenderingModeAlwaysOriginal] : ABMCIconImageForBundleID(token);
}
void ABMCApplyLargeIcon(UITableViewCell *cell, UIImage *image) {
    // Never set imageView.frame or accessoryView here. Preferences owns those
    // layouts (especially PSSwitchCell); overriding them caused icon movement
    // and switches appearing on the left after cell reuse.
    cell.imageView.hidden = NO;
    cell.imageView.image = NormalizedIcon(image) ?: image;
    cell.imageView.contentMode = UIViewContentModeScaleAspectFit;
    cell.imageView.tintColor = UIColor.systemBlueColor;
}
NSString *ABMCInferLinkIcon(NSString *URLString) {
    NSString *scheme = [NSURL URLWithString:URLString].scheme.lowercaseString;
    if ([scheme isEqualToString:@"weixin"]) return @"com.tencent.xin";
    if ([scheme isEqualToString:@"alipay"]) return @"com.alipay.iphoneclient";
    if ([scheme isEqualToString:@"http"] || [scheme isEqualToString:@"https"]) return @"safari.fill";
    if ([scheme isEqualToString:@"mailto"]) return @"envelope.fill";
    if ([scheme isEqualToString:@"tel"] || [scheme isEqualToString:@"sms"]) return @"phone.fill";
    return @"link";
}
NSString *ABMCApplicationName(NSString *identifier) {
    for (id app in ABMCInstalledApplications()) if ([ABMCBundleIdentifierForApplication(app) isEqualToString:identifier]) return ABMCDisplayNameForApplication(app) ?: identifier;
    return identifier ?: @"未知应用";
}
