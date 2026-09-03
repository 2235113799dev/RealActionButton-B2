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

static UIImage *NormalizedIcon(UIImage *image) {
    if (!image) return nil;
    // Every source (SF Symbol, app icon, workflow icon) gets the exact same
    // 34pt canvas. We never mutate UITableViewCell.imageView's frame.
    const CGFloat canvas = 34.0;
    const CGFloat maximum = 30.0;
    CGSize size = image.size;
    CGFloat scale = (size.width > 0 && size.height > 0) ? MIN(maximum / size.width, maximum / size.height) : 1.0;
    CGSize drawSize = CGSizeMake(MAX(1.0, size.width * scale), MAX(1.0, size.height * scale));
    CGRect rect = CGRectMake((canvas - drawSize.width) * 0.5, (canvas - drawSize.height) * 0.5, drawSize.width, drawSize.height);
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(canvas, canvas), NO, UIScreen.mainScreen.scale);
    [image drawInRect:rect];
    UIImage *result = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return result;
}
UIImage *ABMCIconImageForBundleID(NSString *identifier) {
    if (!identifier.length) return nil;
    static NSCache *cache;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ cache = [NSCache new]; cache.countLimit = 160; });
    UIImage *cached = [cache objectForKey:identifier];
    if (cached) return cached;
    @try {
        UIImage *result = NormalizedIcon([UIImage _applicationIconImageForBundleIdentifier:identifier format:0 scale:UIScreen.mainScreen.scale]);
        if (result) [cache setObject:result forKey:identifier];
        return result;
    } @catch (NSException *exception) { return nil; }
}
UIImage *ABMCIconImageForProxy(id application) { return ABMCIconImageForBundleID(ABMCBundleIdentifierForApplication(application)); }

UIImage *ABMCShortcutIconForIdentifier(NSString *identifier) {
    if (!identifier.length) return nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        dlopen("/System/Library/PrivateFrameworks/WorkflowKit.framework/WorkflowKit", RTLD_LAZY | RTLD_LOCAL);
        dlopen("/System/Library/PrivateFrameworks/VoiceShortcutClient.framework/VoiceShortcutClient", RTLD_LAZY | RTLD_LOCAL);
    });
    @try {
        Class databaseClass = NSClassFromString(@"WFDatabase");
        id database = ObjectCall(databaseClass, @"defaultDatabase");
        id reference = nil;
        SEL referenceSelector = NSSelectorFromString(@"referenceForWorkflowID:");
        if ([database respondsToSelector:referenceSelector]) reference = ((id (*)(id, SEL, id))objc_msgSend)(database, referenceSelector, identifier);
        id workflowIcon = ObjectCall(reference, @"icon");
        // WFWorkflowReference returns WFWorkflowIcon; the drawer consumes
        // its underlying WFIcon for the exact per-shortcut glyph/background.
        id icon = ObjectCall(workflowIcon, @"icon") ?: workflowIcon;
        Class drawerClass = NSClassFromString(@"WFWorkflowIconDrawer");
        SEL image = NSSelectorFromString(@"imageWithIcon:size:background:");
        if (icon && [drawerClass respondsToSelector:image]) return ((id (*)(id, SEL, id, CGSize, BOOL))objc_msgSend)(drawerClass, image, icon, CGSizeMake(34, 34), YES);
    } @catch (NSException *exception) {}
    return nil;
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
    cell.imageView.image = image;
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
