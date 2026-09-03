#import "ABMCUIHelpers.h"
#import <objc/message.h>

static id ABMCValue(id object, NSString *name) {
    SEL selector = NSSelectorFromString(name);
    return object && [object respondsToSelector:selector] ? ((id (*)(id, SEL))objc_msgSend)(object, selector) : nil;
}

static id ABMCProxy(NSString *bundleID) {
    Class workspaceClass = NSClassFromString(@"LSApplicationWorkspace");
    id workspace = ABMCValue(workspaceClass, @"defaultWorkspace");
    SEL selector = NSSelectorFromString(@"applicationProxyForBundleIdentifier:");
    return workspace && [workspace respondsToSelector:selector] ? ((id (*)(id, SEL, id))objc_msgSend)(workspace, selector, bundleID) : nil;
}

UIImage *ABMCIconImageForProxy(id proxy) {
    if (!proxy) return nil;
    @try {
        for (NSString *name in @[@"icon", @"applicationIcon", @"primaryIcon"]) {
            id icon = ABMCValue(proxy, name);
            if ([icon isKindOfClass:[UIImage class]]) return icon;
        }
        for (NSString *name in @[@"iconData", @"primaryIconData", @"smallIconData"]) {
            NSData *data = ABMCValue(proxy, name);
            if ([data isKindOfClass:[NSData class]] && data.length) {
                UIImage *icon = [UIImage imageWithData:data];
                if (icon) return icon;
            }
        }
        for (NSNumber *format in @[@0, @1, @2, @10]) {
            SEL selector = NSSelectorFromString(@"iconDataForVariant:");
            if ([proxy respondsToSelector:selector]) {
                NSData *data = ((id (*)(id, SEL, NSInteger))objc_msgSend)(proxy, selector, format.integerValue);
                UIImage *icon = [data isKindOfClass:[NSData class]] ? [UIImage imageWithData:data] : nil;
                if (icon) return icon;
            }
        }
    } @catch (NSException *exception) {}
    return nil;
}

UIImage *ABMCIconImage(NSString *token) {
    UIImageSymbolConfiguration *config = [UIImageSymbolConfiguration configurationWithPointSize:22 weight:UIImageSymbolWeightMedium];
    UIImage *symbol = token.length ? [UIImage systemImageNamed:token withConfiguration:config] : nil;
    if (symbol) return symbol;
    UIImage *icon = ABMCIconImageForProxy(ABMCProxy(token));
    return icon ?: [UIImage systemImageNamed:@"app.fill" withConfiguration:config];
}

UIImage *ABMCTintedIcon(NSString *token, UIColor *color) {
    UIImage *image = ABMCIconImage(token);
    return [UIImage systemImageNamed:token] ? [image imageWithTintColor:color renderingMode:UIImageRenderingModeAlwaysOriginal] : image;
}

NSString *ABMCInferLinkIcon(NSString *URLString) {
    NSString *scheme = [NSURL URLWithString:URLString].scheme.lowercaseString;
    if ([scheme isEqualToString:@"http"] || [scheme isEqualToString:@"https"]) return @"safari.fill";
    if ([scheme isEqualToString:@"weixin"]) return @"com.tencent.xin";
    if ([scheme isEqualToString:@"mailto"]) return @"envelope.fill";
    if ([scheme isEqualToString:@"tel"] || [scheme isEqualToString:@"sms"]) return @"phone.fill";
    return @"link";
}

NSString *ABMCApplicationName(NSString *bundleID) {
    NSString *name = ABMCValue(ABMCProxy(bundleID), @"localizedName");
    return name.length ? name : (bundleID ?: @"未知应用");
}

BOOL ABMCIsAllowedStoreApplicationProxy(id proxy) {
    if (!proxy) return NO;
    @try {
        NSString *bundleID = ABMCValue(proxy, @"bundleIdentifier");
        NSURL *bundleURL = ABMCValue(proxy, @"bundleURL");
        NSString *path = bundleURL.path;
        NSString *type = ABMCValue(proxy, @"applicationType");
        BOOL userPath = [path hasPrefix:@"/var/containers/Bundle/Application/"] || [path hasPrefix:@"/private/var/containers/Bundle/Application/"] || [path containsString:@"/TrollStore/"];
        if (!bundleID.length || ![type isEqualToString:@"User"] || ![path.pathExtension.lowercaseString isEqualToString:@"app"] || !userPath) return NO;
        for (NSString *part in @[@"Service", @"service", @"UIService", @"Helper", @"Widget", @"appex", @"/PlugIns/", @"/Extensions/"]) if ([path containsString:part]) return NO;
        return YES;
    } @catch (NSException *exception) { return NO; }
}
