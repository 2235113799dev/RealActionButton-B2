#import "ABMCUIHelpers.h"
#import <objc/message.h>
#import <dlfcn.h>

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
    return result;
}

#define ABMCDomain CFSTR("com.huynguyen.actionbuttonmulticlick")
#define ABMCPresentationKey CFSTR("presentationOverrides")
#define ABMCUnifiedSizeKey CFSTR("unifiedIconSizing")

BOOL ABMCUnifiedIconSizingEnabled(void) {
    CFPropertyListRef value = CFPreferencesCopyAppValue(ABMCUnifiedSizeKey, ABMCDomain);
    BOOL enabled = value && CFGetTypeID(value) == CFBooleanGetTypeID() ? CFBooleanGetValue((CFBooleanRef)value) : YES;
    if (value) CFRelease(value);
    return enabled;
}
static UIImage *NormalizedIcon(UIImage *image) {
    if (!image) return nil;
    const CGFloat canvas = 34.0, maximum = 30.0;
    CGSize size = image.size;
    CGFloat scale = (size.width > 0 && size.height > 0) ? MIN(maximum / size.width, maximum / size.height) : 1.0;
    CGSize drawSize = CGSizeMake(MAX(1.0, size.width * scale), MAX(1.0, size.height * scale));
    CGRect rect = CGRectMake((canvas - drawSize.width) * .5, (canvas - drawSize.height) * .5, drawSize.width, drawSize.height);
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(canvas, canvas), NO, UIScreen.mainScreen.scale);
    [image drawInRect:rect]; UIImage *result = UIGraphicsGetImageFromCurrentImageContext(); UIGraphicsEndImageContext(); return result;
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
    [alert addTextFieldWithConfigurationHandler:^(UITextField *f) { f.placeholder=@"图标（SF Symbol / Bundle ID）"; f.text=[saved[@"icon"] isKindOfClass:NSString.class] ? saved[@"icon"] : @""; f.autocorrectionType=UITextAutocorrectionTypeNo; f.autocapitalizationType=UITextAutocapitalizationTypeNone; }];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"恢复默认" style:UIAlertActionStyleDestructive handler:^(__unused UIAlertAction *a) { ABMCClearPresentationOverride(key); if(completion)completion(); }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"保存" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *a) { NSString *title=[alert.textFields[0].text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet]; NSString *icon=[alert.textFields[1].text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet]; if(!title.length||title.length>100)return; NSMutableDictionary *all=[PresentationOverrides() mutableCopy]; all[key]=@{ @"title":title, @"icon":icon ?: @"" }; CFPreferencesSetAppValue(ABMCPresentationKey, (__bridge CFPropertyListRef)all, ABMCDomain); CFPreferencesAppSynchronize(ABMCDomain); if(completion)completion(); }]];
    [controller presentViewController:alert animated:YES completion:nil];
}
UIImage *ABMCIconImageForBundleID(NSString *identifier) {
    if (!identifier.length) return nil;
    static NSCache *cache;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ cache = [NSCache new]; cache.countLimit = 160; });
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

UIImage *ABMCAppShortcutIconImage(id shortcutItem, NSString *bundleID) {
    if (!shortcutItem || !bundleID.length) return nil;
    static NSCache *cache; static dispatch_once_t once;
    dispatch_once(&once, ^{ cache=[NSCache new]; cache.countLimit=300; });
    SEL type=NSSelectorFromString(@"type"); NSString *kind=[shortcutItem respondsToSelector:type]?((id(*)(id,SEL))objc_msgSend)(shortcutItem,type):@"";
    NSString *key=[NSString stringWithFormat:@"%@|%@",bundleID,kind?:@""]; UIImage *saved=[cache objectForKey:key]; if(saved)return saved;
    @try {
        dlopen("/System/Library/PrivateFrameworks/SpringBoardHome.framework/SpringBoardHome", RTLD_LAZY|RTLD_LOCAL);
        Class proxyClass=NSClassFromString(@"LSApplicationProxy"); SEL proxy=NSSelectorFromString(@"applicationProxyForIdentifier:");
        id app=[proxyClass respondsToSelector:proxy]?((id(*)(id,SEL,id))objc_msgSend)(proxyClass,proxy,bundleID):nil;
        NSURL *url=ObjectCall(app,@"bundleURL"); UIImage *image=nil; NSString *symbol=nil;
        SEL build=NSSelectorFromString(@"sb_buildIconImageWithApplicationBundleURL:image:systemImageName:");
        if(url&&[shortcutItem respondsToSelector:build]) ((void(*)(id,SEL,id,id*,id*))objc_msgSend)(shortcutItem,build,url,&image,&symbol);
        if(!image&&symbol.length) image=[UIImage systemImageNamed:symbol withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:24 weight:UIImageSymbolWeightMedium]];
        if(image)[cache setObject:image forKey:key]; return image;
    } @catch(NSException *exception) { return nil; }
}

UIImage *ABMCWorkflowIconImage(NSInteger glyph, long long backgroundColor) {
    if (glyph <= 0) return nil;
    static NSCache *cache;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ cache = [NSCache new]; cache.countLimit = 300; });
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
        UIImage *result = icon ? ((id (*)(id, SEL, id, CGSize, BOOL))objc_msgSend)(drawerClass, draw, icon, CGSizeMake(34, 34), YES) : nil;
        if (result) [cache setObject:result forKey:key];
        return result;
    } @catch (NSException *exception) { return nil; }
}

UIImage *ABMCIconImage(NSString *token) {
    UIImageSymbolConfiguration *config = [UIImageSymbolConfiguration configurationWithPointSize:24.0 weight:UIImageSymbolWeightMedium];
    UIImage *symbol = token.length ? [UIImage systemImageNamed:token withConfiguration:config] : nil;
    return symbol ?: ABMCIconImageForBundleID(token) ?: [UIImage systemImageNamed:@"app.fill" withConfiguration:config];
}
UIImage *ABMCTintedIcon(NSString *token, UIColor *color) {
    UIImage *image = ABMCIconImage(token);
    return [UIImage systemImageNamed:token] ? [image imageWithTintColor:color renderingMode:UIImageRenderingModeAlwaysOriginal] : image;
}
void ABMCApplyLargeIcon(UITableViewCell *cell, UIImage *image) {
    // Never set imageView.frame or accessoryView here. Preferences owns those
    // layouts (especially PSSwitchCell); overriding them caused icon movement
    // and switches appearing on the left after cell reuse.
    cell.imageView.hidden = NO;
    cell.imageView.image = ABMCUnifiedIconSizingEnabled() ? NormalizedIcon(image) : image;
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
