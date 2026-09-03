#import "ABMCUIHelpers.h"
#import <objc/message.h>

static id ABMCValue(id object, NSString *selectorName) {
    SEL selector = NSSelectorFromString(selectorName);
    return object && [object respondsToSelector:selector] ? ((id (*)(id, SEL))objc_msgSend)(object, selector) : nil;
}

static id ABMCProxyForBundleID(NSString *bundleID) {
    Class workspaceClass = NSClassFromString(@"LSApplicationWorkspace");
    id workspace = ABMCValue(workspaceClass, @"defaultWorkspace");
    SEL selector = NSSelectorFromString(@"applicationProxyForBundleIdentifier:");
    return workspace && [workspace respondsToSelector:selector] ? ((id (*)(id, SEL, id))objc_msgSend)(workspace, selector, bundleID) : nil;
}

static UIImage *ABMCProxyIcon(id proxy) {
    if (!proxy) return nil;
    for (NSString *method in @[@"icon", @"primaryIcon", @"applicationIcon"]) {
        id image = ABMCValue(proxy, method);
        if ([image isKindOfClass:[UIImage class]]) return image;
    }
    for (NSString *method in @[@"iconData", @"primaryIconData"]) {
        id data = ABMCValue(proxy, method);
        if ([data isKindOfClass:[NSData class]] && [data length]) {
            UIImage *image = [UIImage imageWithData:data];
            if (image) return image;
        }
    }
    SEL variant = NSSelectorFromString(@"iconDataForVariant:");
    if ([proxy respondsToSelector:variant]) {
        NSData *data = ((id (*)(id, SEL, NSInteger))objc_msgSend)(proxy, variant, 0);
        UIImage *image = [data isKindOfClass:[NSData class]] ? [UIImage imageWithData:data] : nil;
        if (image) return image;
    }
    return nil;
}

UIImage *ABMCIconImage(NSString *token) {
    UIImageSymbolConfiguration *config = [UIImageSymbolConfiguration configurationWithPointSize:22.0 weight:UIImageSymbolWeightMedium];
    UIImage *symbol = token.length ? [UIImage systemImageNamed:token withConfiguration:config] : nil;
    if (symbol) return symbol;
    @try {
        id proxy = ABMCProxyForBundleID(token);
        UIImage *icon = ABMCProxyIcon(proxy);
        if (icon) return icon;
        Class applicationClass = NSClassFromString(@"UIApplication");
        id app = [applicationClass respondsToSelector:@selector(sharedApplication)] ? [applicationClass sharedApplication] : nil;
        SEL imageSelector = NSSelectorFromString(@"_applicationIconImageForBundleIdentifier:format:scale:");
        if (app && [app respondsToSelector:imageSelector]) {
            icon = ((id (*)(id, SEL, id, NSInteger, CGFloat))objc_msgSend)(app, imageSelector, token, 2, UIScreen.mainScreen.scale);
            if ([icon isKindOfClass:[UIImage class]]) return icon;
        }
    } @catch (NSException *exception) {}
    return [UIImage systemImageNamed:@"app.fill" withConfiguration:config];
}

UIImage *ABMCTintedIcon(NSString *token, UIColor *color) {
    UIImage *image = ABMCIconImage(token);
    // SF Symbol 使用统一蓝色；真实应用图标保持原始彩色。
    return [UIImage systemImageNamed:token] ? [image imageWithTintColor:color renderingMode:UIImageRenderingModeAlwaysOriginal] : image;
}

NSString *ABMCInferLinkIcon(NSString *URLString) {
    NSString *scheme = [NSURL URLWithString:URLString].scheme.lowercaseString;
    if ([scheme isEqualToString:@"http"] || [scheme isEqualToString:@"https"]) return @"safari.fill";
    if ([scheme isEqualToString:@"weixin"]) return @"message.fill";
    if ([scheme isEqualToString:@"mailto"]) return @"envelope.fill";
    if ([scheme isEqualToString:@"tel"] || [scheme isEqualToString:@"sms"]) return @"phone.fill";
    if ([scheme isEqualToString:@"shortcuts"]) return @"square.stack.3d.up.fill";
    return @"link";
}

NSString *ABMCApplicationName(NSString *bundleID) {
    if (!bundleID.length) return @"未知应用";
    @try {
        id name = ABMCValue(ABMCProxyForBundleID(bundleID), @"localizedName");
        if ([name isKindOfClass:[NSString class]] && [name length]) return name;
    } @catch (NSException *exception) {}
    return bundleID;
}

BOOL ABMCIsAllowedStoreApplicationProxy(id proxy) {
    if (!proxy) return NO;
    @try {
        NSString *bundleID = ABMCValue(proxy, @"bundleIdentifier");
        NSURL *bundleURL = ABMCValue(proxy, @"bundleURL");
        NSString *path = bundleURL.path;
        NSString *type = ABMCValue(proxy, @"applicationType");
        BOOL userContainer = [path hasPrefix:@"/var/containers/Bundle/Application/"] || [path hasPrefix:@"/private/var/containers/Bundle/Application/"];
        if (!bundleID.length || ![path.pathExtension.lowercaseString isEqualToString:@"app"] || ![type isEqualToString:@"User"] || !userContainer) return NO;
        for (NSString *fragment in @[@"Service", @"service", @"UIService", @"Helper", @"Widget", @"appex", @"/PlugIns/", @"/Extensions/"]) if ([path containsString:fragment]) return NO;
        return YES; // User 容器包含 App Store 与 TrollStore 安装的可启动应用。
    } @catch (NSException *exception) { return NO; }
}
