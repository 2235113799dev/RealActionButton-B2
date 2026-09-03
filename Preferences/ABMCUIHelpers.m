#import "ABMCUIHelpers.h"
#import <objc/message.h>

static id ABMCValue(id object, NSString *selectorName) {
    SEL selector = NSSelectorFromString(selectorName);
    return object && [object respondsToSelector:selector] ? ((id (*)(id, SEL))objc_msgSend)(object, selector) : nil;
}

UIImage *ABMCIconImage(NSString *token) {
    UIImage *symbol = token.length ? [UIImage systemImageNamed:token] : nil;
    if (symbol) return symbol;
    @try {
        Class workspaceClass = NSClassFromString(@"LSApplicationWorkspace");
        id workspace = ABMCValue(workspaceClass, @"defaultWorkspace");
        SEL proxySelector = NSSelectorFromString(@"applicationProxyForBundleIdentifier:");
        id proxy = workspace && [workspace respondsToSelector:proxySelector] ? ((id (*)(id, SEL, id))objc_msgSend)(workspace, proxySelector, token) : nil;
        id image = ABMCValue(proxy, @"icon");
        if ([image isKindOfClass:[UIImage class]]) return image;
    } @catch (NSException *exception) {}
    return [UIImage systemImageNamed:@"app.fill"];
}

UIImage *ABMCTintedIcon(NSString *token, UIColor *color) {
    return [ABMCIconImage(token) imageWithTintColor:color renderingMode:UIImageRenderingModeAlwaysOriginal];
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
        Class workspaceClass = NSClassFromString(@"LSApplicationWorkspace");
        id workspace = ABMCValue(workspaceClass, @"defaultWorkspace");
        SEL proxySelector = NSSelectorFromString(@"applicationProxyForBundleIdentifier:");
        id proxy = workspace && [workspace respondsToSelector:proxySelector] ? ((id (*)(id, SEL, id))objc_msgSend)(workspace, proxySelector, bundleID) : nil;
        id name = ABMCValue(proxy, @"localizedName");
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
        NSNumber *itemID = ABMCValue(proxy, @"itemID");
        BOOL isUserContainer = [path hasPrefix:@"/var/containers/Bundle/Application/"] || [path hasPrefix:@"/private/var/containers/Bundle/Application/"];
        if (!bundleID.length || ![path.pathExtension.lowercaseString isEqualToString:@"app"]) return NO;
        if (![type isEqualToString:@"User"] || !isUserContainer || itemID.longLongValue <= 0) return NO;
        for (NSString *fragment in @[@"Service", @"service", @"UIService", @"Helper", @"Widget", @"appex", @"/PlugIns/", @"/Extensions/"]) {
            if ([path containsString:fragment]) return NO;
        }
        return YES;
    } @catch (NSException *exception) {
        return NO;
    }
}
