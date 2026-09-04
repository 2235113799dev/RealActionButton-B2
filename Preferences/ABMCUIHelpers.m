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

static NSArray<NSDictionary *> *ABMCActionAppRecords; static BOOL ABMCActionAppRecordsBuilding;
NSArray<NSDictionary *> *ABMCActionApplicationRecords(void) {
    @synchronized([NSProcessInfo processInfo]) { if(ABMCActionAppRecords)return ABMCActionAppRecords; }
    NSMutableArray *out=[NSMutableArray array];NSSet *blocked=[NSSet setWithArray:@[@"AccountAuthenticationDialog",@"AirDrop",@"AirPlayReceiver",@"AskToMessagesHost",@"BacklinkIndicator",@"CarPlaySetup",@"CarPlaySplashScreen",@"CarPlayWallpaper",@"CheckerBoard",@"CheckerBoardRemoteSetup",@"ContactPhotoCarouselRemoteAlert",@"CTCarrierSpaceAuth",@"DemoApp",@"EyeReliefUI",@"ReplayKitAngel",@"ScreenTimeUnlock",@"SleepLockScreen",@"SLYahooAuth",@"SpringBoardEducation",@"TrustMe",@"Web",@"WebContentAnalysisUI",@"WebSheet"]];
    for(id proxy in ABMCInstalledApplications()){NSString *bid=ABMCBundleIdentifierForApplication(proxy),*name=ABMCDisplayNameForApplication(proxy);if(bid.length&&name.length&&ABMCApplicationHasRealIcon(proxy)&&![blocked containsObject:name])[out addObject:@{@"id":bid,@"name":name}];}
    NSArray *ordered=[out sortedArrayUsingComparator:^NSComparisonResult(NSDictionary*a,NSDictionary*b){return[a[@"name"] localizedCaseInsensitiveCompare:b[@"name"]];}];NSMutableArray *deduped=[NSMutableArray array];NSMutableSet *names=[NSMutableSet set];for(NSDictionary *item in ordered){NSString *name=[item[@"name"] lowercaseString];if(name.length&&![names containsObject:name]){[names addObject:name];[deduped addObject:item];}}
    NSArray *snapshot=[deduped copy];@synchronized([NSProcessInfo processInfo]){ABMCActionAppRecords=snapshot;ABMCActionAppRecordsBuilding=NO;}return snapshot;
}
void ABMCPrewarmActionApplicationRecords(void) { @synchronized([NSProcessInfo processInfo]){if(ABMCActionAppRecords||ABMCActionAppRecordsBuilding)return;ABMCActionAppRecordsBuilding=YES;}dispatch_async(dispatch_get_main_queue(),^{ABMCActionApplicationRecords();}); }

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
static NSDictionary *ABMCLinkRecord(NSString *identifier);
static NSDictionary *ABMCLinkRecord(NSString *identifier) { CFPropertyListRef raw=CFPreferencesCopyAppValue(CFSTR("savedLinks"),ABMCDomain);NSDictionary *result=nil;for(NSDictionary *item in (raw&&CFGetTypeID(raw)==CFArrayGetTypeID()?(__bridge NSArray *)raw:@[]))if([item[@"id"] isEqualToString:identifier]){result=[item copy];break;}if(raw)CFRelease(raw);return result; }
static NSString *ABMCBriefPresentationKey(NSString *action) {
    if([action hasPrefix:@"app:"]) return [@"app." stringByAppendingString:[action substringFromIndex:4]];
    if([action hasPrefix:@"shortcutid:"]) return [@"shortcut." stringByAppendingString:[[action substringFromIndex:11] componentsSeparatedByString:@"|"].firstObject ?: @""];
    if([action hasPrefix:@"link:"]) return [@"link." stringByAppendingString:[action substringFromIndex:5]];
    return [@"action." stringByAppendingString:action ?: @"none"];
}
UIImage *ABMCSelectedActionIcon(NSString *action) {
    NSString *key=ABMCBriefPresentationKey(action),*fallback=nil;
    if([action hasPrefix:@"app:"]) fallback=[action substringFromIndex:4];
    else if([action hasPrefix:@"shortcutid:"]) fallback=@"square.stack.3d.up.fill";
    else if([action hasPrefix:@"link:"]){NSDictionary *record=ABMCLinkRecord([action substringFromIndex:5]);fallback=record[@"icon"] ?: @"link";}
    else if([action hasPrefix:@"url:"]) fallback=@"link";
    else { NSDictionary *icons=@{ @"default":@"gearshape.fill",@"flashlight":@"flashlight.on.fill",@"camera":@"camera.fill",@"silent":@"bell.slash.fill",@"screenshot":@"viewfinder",@"lock":@"lock.fill",@"controlCenter":@"switch.2",@"notificationCenter":@"bell.fill",@"settings":@"gearshape.fill",@"respring":@"arrow.clockwise",@"wechatScan":@"qrcode.viewfinder",@"wechatPay":@"creditcard.fill",@"alipayScan":@"qrcode.viewfinder",@"alipayPay":@"creditcard.fill"};fallback=icons[action] ?: @"square.grid.2x2.fill"; }
    id saved=PresentationOverrides()[key][@"icon"]; NSString *override=[saved isKindOfClass:NSString.class] && [saved length] ? saved : nil;
    if(override.length){UIImage *image=ABMCIconImageForBundleID(override) ?: ABMCTintedIcon(override,nil);if(image)return image;}
    if([action hasPrefix:@"shortcutid:"]){NSArray *parts=[[action substringFromIndex:11]componentsSeparatedByString:@"|"];if(parts.count>3){UIImage *workflow=ABMCWorkflowIconImage([parts[2]integerValue],[parts[3]longLongValue]);if(workflow)return workflow;}}
    return ABMCTintedIcon(fallback,nil) ?: ABMCIconImageForBundleID(fallback);
}


static NSString *ABMCCategoryPresentationKey(NSString *action) { if([action hasPrefix:@"app:"])return [@"app." stringByAppendingString:[action substringFromIndex:4]];if([action hasPrefix:@"shortcutid:"])return [@"shortcut." stringByAppendingString:[[action substringFromIndex:11] componentsSeparatedByString:@"|"].firstObject ?: @""];if([action hasPrefix:@"link:"])return [@"link." stringByAppendingString:[action substringFromIndex:5]];return [@"action." stringByAppendingString:action ?: @"none"]; }
static NSString *ABMCCategoryActionTitle(NSString *action) { if([action hasPrefix:@"shortcutid:"]){NSArray *p=[[action substringFromIndex:11]componentsSeparatedByString:@"|"];return p.count>1?p[1]:@"快捷指令";}if([action hasPrefix:@"app:"])return ABMCApplicationName([action substringFromIndex:4]) ?: @"应用";if([action hasPrefix:@"link:"]){NSDictionary *record=ABMCLinkRecord([action substringFromIndex:5]);return record[@"title"] ?: @"URL";}NSDictionary *names=@{@"default":@"系统默认",@"flashlight":@"手电筒",@"camera":@"相机",@"silent":@"静音切换",@"screenshot":@"截屏",@"lock":@"锁屏",@"controlCenter":@"控制中心",@"notificationCenter":@"通知中心",@"settings":@"设置",@"respring":@"重启",@"wechatScan":@"微信扫码",@"wechatPay":@"微信付款码",@"alipayScan":@"支付宝扫码",@"alipayPay":@"支付宝付款码"};return names[action] ?: @"动作"; }
@interface ABMCCategorySelectedTarget : NSObject
@property(nonatomic,weak) UIViewController *controller;@property(nonatomic,copy) NSString *key,*action;
- (void)longPress:(UILongPressGestureRecognizer *)gesture;- (void)doubleTap:(UITapGestureRecognizer *)gesture;
@end
@implementation ABMCCategorySelectedTarget
- (void)refresh { SEL selector=NSSelectorFromString(@"refreshHeader");if([self.controller respondsToSelector:selector])((void(*)(id,SEL))objc_msgSend)(self.controller,selector);if([self.controller isKindOfClass:UITableViewController.class])[((UITableViewController *)self.controller).tableView reloadData]; }
- (void)longPress:(UILongPressGestureRecognizer *)gesture { if(gesture.state!=UIGestureRecognizerStateBegan)return;NSString *key=ABMCCategoryPresentationKey(self.action);ABMCShowPresentationEditor(self.controller,key,ABMCCategoryActionTitle(self.action),@"hand.tap.fill",^{[self refresh];}); }
- (void)doubleTap:(UITapGestureRecognizer *)gesture { if(gesture.state!=UIGestureRecognizerStateRecognized)return;NSMutableArray *items=[ABMCSelectedActions(self.key)mutableCopy];[items removeObject:self.action];ABMCStoreSelectedActions(self.key,items);[self refresh]; }
@end
UIView *ABMCCategoryActionHeader(NSString *preferenceKey, UIViewController *controller, NSString *placeholder) {
    UITableView *table=[controller isKindOfClass:UITableViewController.class]?((UITableViewController *)controller).tableView:nil;CGFloat width=table.bounds.size.width;if(width<100)width=UIScreen.mainScreen.bounds.size.width;
    NSArray *items=ABMCSelectedActions(preferenceKey);NSUInteger count=MAX((NSUInteger)1,items.count);CGFloat row=44.0,captionY=62.0,cardY=86.0,height=cardY+count*row+12.0;
    UIView *header=[[UIView alloc]initWithFrame:CGRectMake(0,0,width,height)];header.autoresizingMask=UIViewAutoresizingFlexibleWidth;header.backgroundColor=UIColor.systemGroupedBackgroundColor;
    // UITableView's fixed overlay uses full-width coordinates. Keep the same
    // 20pt grouped margin as the native cards below for search and selection.
    const CGFloat inset=20.0;
    UISearchBar *search=[[UISearchBar alloc]initWithFrame:CGRectMake(inset,0,width-inset*2,56)];search.autoresizingMask=UIViewAutoresizingFlexibleWidth;search.placeholder=placeholder;search.delegate=(id<UISearchBarDelegate>)controller;[header addSubview:search];
    UILabel *caption=[[UILabel alloc]initWithFrame:CGRectMake(inset,captionY,width-inset*2,18)];caption.autoresizingMask=UIViewAutoresizingFlexibleWidth;caption.text=@"已选动作";caption.textColor=UIColor.secondaryLabelColor;caption.font=[UIFont systemFontOfSize:16];[header addSubview:caption];
    CGFloat cardWidth=width-inset*2;UIView *card=[[UIView alloc]initWithFrame:CGRectMake(inset,cardY,cardWidth,count*row)];card.autoresizingMask=UIViewAutoresizingFlexibleWidth;card.backgroundColor=UIColor.secondarySystemGroupedBackgroundColor;card.layer.cornerRadius=15;card.clipsToBounds=YES;[header addSubview:card];
    for(NSUInteger i=0;i<count;i++){NSString *action=items.count?items[i]:@"none";BOOL none=[action isEqualToString:@"none"];UIView *line=[[UIView alloc]initWithFrame:CGRectMake(0,i*row,cardWidth,row)];line.autoresizingMask=UIViewAutoresizingFlexibleWidth;line.userInteractionEnabled=YES;[card addSubview:line];UIImage *raw=none?ABMCTintedIcon(@"nosign",UIColor.systemRedColor):ABMCSelectedActionIcon(action);UIImageView *icon=[[UIImageView alloc]initWithImage:NormalizedIcon(raw) ?: raw];icon.frame=CGRectMake(20,5,34,34);icon.contentMode=UIViewContentModeScaleAspectFit;[line addSubview:icon];UILabel *title=[[UILabel alloc]initWithFrame:CGRectMake(64,0,cardWidth-74,row)];title.autoresizingMask=UIViewAutoresizingFlexibleWidth;title.text=none?@"无操作":ABMCCategoryActionTitle(action);title.textColor=none?UIColor.systemRedColor:UIColor.systemBlueColor;title.font=[UIFont systemFontOfSize:18 weight:UIFontWeightRegular];[line addSubview:title];ABMCCategorySelectedTarget *target=[ABMCCategorySelectedTarget new];target.controller=controller;target.key=preferenceKey;target.action=action;UILongPressGestureRecognizer *hold=[[UILongPressGestureRecognizer alloc]initWithTarget:target action:@selector(longPress:)];hold.minimumPressDuration=.45;[line addGestureRecognizer:hold];UITapGestureRecognizer *doubleTap=[[UITapGestureRecognizer alloc]initWithTarget:target action:@selector(doubleTap:)];doubleTap.numberOfTapsRequired=2;[line addGestureRecognizer:doubleTap];objc_setAssociatedObject(line,@selector(ABMCCategoryActionHeader),target,OBJC_ASSOCIATION_RETAIN_NONATOMIC);if(i+1<count){UIView *separator=[[UIView alloc]initWithFrame:CGRectMake(64,row-.5,cardWidth-64,.5)];separator.autoresizingMask=UIViewAutoresizingFlexibleWidth;separator.backgroundColor=UIColor.separatorColor;[line addSubview:separator];}}
    return header;
}
static const void *kABMCStickyHeaderKey=&kABMCStickyHeaderKey;
static UIView *ABMCStickyHeaderHost(UITableViewController *controller) { return controller.navigationController.view ?: controller.view; }
static CGRect ABMCStickyHeaderFrame(UITableViewController *controller, UIView *header) {
    UITableView *table=controller.tableView;UIView *host=ABMCStickyHeaderHost(controller);UINavigationBar *bar=controller.navigationController.navigationBar;
    CGRect tableFrame=[table.superview convertRect:table.frame toView:host];
    // UITableViewController may extend its table behind the navigation bar, so
    // tableFrame.origin.y is not the visible content start. The navigation bar
    // bottom is the only stable anchor for “below the back button”.
    CGFloat top=CGRectGetMinY(tableFrame);
    if(bar.superview){CGRect navigationFrame=[bar.superview convertRect:bar.frame toView:host];top=CGRectGetMaxY(navigationFrame);}
    return CGRectMake(CGRectGetMinX(tableFrame),top,CGRectGetWidth(tableFrame),CGRectGetHeight(header.bounds));
}
void ABMCInstallStickyCategoryActionHeader(UITableViewController *controller, NSString *preferenceKey, NSString *placeholder) {
    if(!controller)return;
    UITableView *table=controller.tableView;UIView *host=ABMCStickyHeaderHost(controller);if(!host)return;
    UIView *old=objc_getAssociatedObject(controller,kABMCStickyHeaderKey);[old removeFromSuperview];
    UIView *header=ABMCCategoryActionHeader(preferenceKey,controller,placeholder);
    UIView *spacer=[[UIView alloc]initWithFrame:CGRectMake(0,0,table.bounds.size.width,CGRectGetHeight(header.bounds))];spacer.backgroundColor=UIColor.clearColor;spacer.userInteractionEnabled=NO;table.tableHeaderView=spacer;
    header.frame=ABMCStickyHeaderFrame(controller,header);header.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleBottomMargin;header.opaque=YES;header.backgroundColor=UIColor.systemGroupedBackgroundColor;
    UINavigationBar *bar=controller.navigationController.navigationBar;
    if(bar.superview==host)[host insertSubview:header belowSubview:bar];else [host addSubview:header];
    table.scrollIndicatorInsets=UIEdgeInsetsMake(CGRectGetHeight(header.bounds),0,0,0);
    objc_setAssociatedObject(controller,kABMCStickyHeaderKey,header,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
void ABMCUpdateStickyCategoryActionHeader(UITableViewController *controller) {
    UIView *header=objc_getAssociatedObject(controller,kABMCStickyHeaderKey);if(header)header.frame=ABMCStickyHeaderFrame(controller,header);
}
void ABMCRemoveStickyCategoryActionHeader(UITableViewController *controller) { UIView *header=objc_getAssociatedObject(controller,kABMCStickyHeaderKey);[header removeFromSuperview];objc_setAssociatedObject(controller,kABMCStickyHeaderKey,nil,OBJC_ASSOCIATION_ASSIGN); }
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
