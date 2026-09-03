#import "ABMCUIHelpers.h"
#import <objc/message.h>
#import <dlfcn.h>

@interface UIImage (ABMCAltListPrivate)
+ (instancetype)_applicationIconImageForBundleIdentifier:(NSString *)bundleIdentifier format:(int)format scale:(CGFloat)scale;
@end

static id ABMCInvoke(id object, NSString *name) {
    SEL selector = NSSelectorFromString(name);
    return object && [object respondsToSelector:selector] ? ((id (*)(id, SEL))objc_msgSend)(object, selector) : nil;
}

static void ABMCLoadAltList(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        // RootHide maps /Library to its private root at runtime. This is only
        // loaded by Preferences and never copied into, or injected by, B2.
        dlopen("/var/jb/Library/Frameworks/AltList.framework/AltList", RTLD_LAZY | RTLD_LOCAL);
        dlopen("/Library/Frameworks/AltList.framework/AltList", RTLD_LAZY | RTLD_LOCAL);
    });
}

NSString *ABMCBundleIdentifierForApplication(id application) {
    ABMCLoadAltList();
    NSString *identifier = ABMCInvoke(application, @"atl_bundleIdentifier");
    if (!identifier.length) identifier = ABMCInvoke(application, @"bundleIdentifier");
    return identifier;
}

NSString *ABMCDisplayNameForApplication(id application) {
    ABMCLoadAltList();
    NSString *name = ABMCInvoke(application, @"atl_fastDisplayName");
    if (!name.length) name = ABMCInvoke(application, @"localizedName");
    return name;
}

NSArray *ABMCAltListUserApplications(void) {
    ABMCLoadAltList();
    Class workspaceClass = NSClassFromString(@"LSApplicationWorkspace");
    id workspace = ABMCInvoke(workspaceClass, @"defaultWorkspace");
    NSArray *all = ABMCInvoke(workspace, @"atl_allInstalledApplications");
    if (![all isKindOfClass:[NSArray class]]) return @[];
    NSMutableArray *result = [NSMutableArray array];
    NSMutableSet *identifiers = [NSMutableSet set];
    for (id application in all) {
        BOOL isUser = NO;
        @try {
            SEL selector = NSSelectorFromString(@"atl_isUserApplication");
            isUser = [application respondsToSelector:selector] ? ((BOOL (*)(id, SEL))objc_msgSend)(application, selector) : NO;
        } @catch (NSException *exception) { continue; }
        NSString *identifier = ABMCBundleIdentifierForApplication(application);
        if (isUser && identifier.length && ![identifiers containsObject:identifier]) {
            [identifiers addObject:identifier];
            [result addObject:application];
        }
    }
    return result;
}

static UIImage *ABMCScaleIcon(UIImage *image) {
    if (!image) return nil;
    CGFloat side = 30.0;
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(side, side), NO, UIScreen.mainScreen.scale);
    [image drawInRect:CGRectMake(0, 0, side, side)];
    UIImage *result = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return result;
}

UIImage *ABMCIconImageForBundleID(NSString *bundleID) {
    if (!bundleID.length) return nil;
    @try {
        UIImage *image = [UIImage _applicationIconImageForBundleIdentifier:bundleID format:0 scale:UIScreen.mainScreen.scale];
        if (image) return ABMCScaleIcon(image);
    } @catch (NSException *exception) {}
    return nil;
}

UIImage *ABMCIconImageForProxy(id application) { return ABMCIconImageForBundleID(ABMCBundleIdentifierForApplication(application)); }
UIImage *ABMCIconImage(NSString *token) {
    UIImageSymbolConfiguration *config = [UIImageSymbolConfiguration configurationWithPointSize:22 weight:UIImageSymbolWeightMedium];
    UIImage *symbol = token.length ? [UIImage systemImageNamed:token withConfiguration:config] : nil;
    return symbol ?: ABMCIconImageForBundleID(token) ?: [UIImage systemImageNamed:@"app.fill" withConfiguration:config];
}
UIImage *ABMCTintedIcon(NSString *token, UIColor *color) {
    UIImage *image = ABMCIconImage(token);
    return [UIImage systemImageNamed:token] ? [image imageWithTintColor:color renderingMode:UIImageRenderingModeAlwaysOriginal] : image;
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
NSString *ABMCApplicationName(NSString *bundleID) {
    if (!bundleID.length) return @"未知应用";
    for (id app in ABMCAltListUserApplications()) if ([ABMCBundleIdentifierForApplication(app) isEqualToString:bundleID]) return ABMCDisplayNameForApplication(app) ?: bundleID;
    return bundleID;
}
