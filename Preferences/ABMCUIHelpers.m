#import "ABMCUIHelpers.h"
#import <objc/message.h>

static id ABMCValue(id object, NSString *name) { SEL s=NSSelectorFromString(name); return object&&[object respondsToSelector:s]?((id(*)(id,SEL))objc_msgSend)(object,s):nil; }
static id ABMCProxy(NSString *bundleID) { Class c=NSClassFromString(@"LSApplicationWorkspace");id w=ABMCValue(c,@"defaultWorkspace");SEL s=NSSelectorFromString(@"applicationProxyForBundleIdentifier:");return w&&[w respondsToSelector:s]?((id(*)(id,SEL,id))objc_msgSend)(w,s,bundleID):nil; }

static UIImage *ABMCImageFromBundle(NSURL *bundleURL) {
    if (!bundleURL) return nil;
    NSBundle *bundle = [NSBundle bundleWithURL:bundleURL];
    NSDictionary *info = bundle.infoDictionary;
    NSMutableOrderedSet *names = [NSMutableOrderedSet orderedSet];
    NSDictionary *icons = info[@"CFBundleIcons"] ?: info[@"CFBundleIcons~ipad"];
    NSDictionary *primary = [icons isKindOfClass:[NSDictionary class]] ? icons[@"CFBundlePrimaryIcon"] : nil;
    NSArray *files = [primary isKindOfClass:[NSDictionary class]] ? primary[@"CFBundleIconFiles"] : nil;
    if ([files isKindOfClass:[NSArray class]]) [names addObjectsFromArray:files];
    NSString *legacy = info[@"CFBundleIconFile"]; if (legacy.length) [names addObject:legacy];
    [names addObjectsFromArray:@[@"AppIcon", @"AppIcon60x60", @"AppIcon60x60@2x", @"AppIcon60x60@3x", @"Icon60", @"Icon"]];
    // 现代应用大多把图标编入 Assets.car；imageNamed:inBundle: 能正确解析它。
    for (NSString *name in names) {
        NSString *stem = [name stringByDeletingPathExtension];
        UIImage *asset = [UIImage imageNamed:stem inBundle:bundle compatibleWithTraitCollection:nil];
        if (asset) return asset;
        for (NSString *candidate in @[name, [stem stringByAppendingPathExtension:@"png"], [stem stringByAppendingString:@"@2x.png"], [stem stringByAppendingString:@"@3x.png"]]) {
            UIImage *image = [UIImage imageWithContentsOfFile:[bundleURL.path stringByAppendingPathComponent:candidate]];
            if (image) return image;
        }
    }
    NSDirectoryEnumerator *enumerator = [NSFileManager.defaultManager enumeratorAtURL:bundleURL includingPropertiesForKeys:nil options:NSDirectoryEnumerationSkipsHiddenFiles errorHandler:nil];
    NSUInteger count = 0;
    for (NSURL *url in enumerator) {
        if (count++ > 1200) break;
        NSString *name = url.lastPathComponent.lowercaseString;
        if (([name hasPrefix:@"appicon"] || [name hasPrefix:@"icon"]) && [name hasSuffix:@".png"]) {
            UIImage *image = [UIImage imageWithContentsOfFile:url.path]; if (image) return image;
        }
    }
    return nil;
}

UIImage *ABMCIconImageForProxy(id proxy) {
    if(!proxy)return nil;
    @try {
        for(NSString *name in @[@"icon",@"applicationIcon",@"primaryIcon"]) { id v=ABMCValue(proxy,name);if([v isKindOfClass:[UIImage class]])return v; }
        for(NSString *name in @[@"iconData",@"primaryIconData",@"smallIconData"]) { NSData *d=ABMCValue(proxy,name);UIImage *i=[d isKindOfClass:[NSData class]]?[UIImage imageWithData:d]:nil;if(i)return i; }
        SEL dataSelector=NSSelectorFromString(@"iconDataForVariant:");
        for(NSInteger variant=0; variant<16; variant++) if([proxy respondsToSelector:dataSelector]) { NSData *d=((id(*)(id,SEL,NSInteger))objc_msgSend)(proxy,dataSelector,variant);UIImage *i=[d isKindOfClass:[NSData class]]?[UIImage imageWithData:d]:nil;if(i)return i; }
        SEL optionsSelector=NSSelectorFromString(@"iconDataForVariant:withOptions:");
        for(NSInteger variant=0; variant<16; variant++) if([proxy respondsToSelector:optionsSelector]) { NSData *d=((id(*)(id,SEL,NSInteger,NSUInteger))objc_msgSend)(proxy,optionsSelector,variant,0);UIImage *i=[d isKindOfClass:[NSData class]]?[UIImage imageWithData:d]:nil;if(i)return i; }
        NSURL *url=ABMCValue(proxy,@"bundleURL");UIImage *i=ABMCImageFromBundle(url);if(i)return i;
    }@catch(NSException *exception){}
    return nil;
}
UIImage *ABMCIconImageForBundleID(NSString *bundleID){return ABMCIconImageForProxy(ABMCProxy(bundleID));}
UIImage *ABMCIconImage(NSString *token){UIImageSymbolConfiguration*c=[UIImageSymbolConfiguration configurationWithPointSize:22 weight:UIImageSymbolWeightMedium];UIImage*s=token.length?[UIImage systemImageNamed:token withConfiguration:c]:nil;if(s)return s;return ABMCIconImageForBundleID(token)?:[UIImage systemImageNamed:@"app.fill" withConfiguration:c];}
UIImage *ABMCTintedIcon(NSString *token,UIColor *color){UIImage*i=ABMCIconImage(token);return[UIImage systemImageNamed:token]?[i imageWithTintColor:color renderingMode:UIImageRenderingModeAlwaysOriginal]:i;}
NSString *ABMCInferLinkIcon(NSString *url){NSString*s=[NSURL URLWithString:url].scheme.lowercaseString;if([s isEqualToString:@"http"]||[s isEqualToString:@"https"])return @"safari.fill";if([s isEqualToString:@"weixin"])return @"com.tencent.xin";if([s isEqualToString:@"alipay"])return @"com.alipay.iphoneclient";if([s isEqualToString:@"mailto"])return @"envelope.fill";if([s isEqualToString:@"tel"]||[s isEqualToString:@"sms"])return @"phone.fill";return @"link";}
NSString *ABMCApplicationName(NSString *bundleID){NSString*n=ABMCValue(ABMCProxy(bundleID),@"localizedName");return n.length?n:(bundleID?:@"未知应用");}
BOOL ABMCIsAllowedStoreApplicationProxy(id proxy){if(!proxy)return NO;@try{NSString*bid=ABMCValue(proxy,@"bundleIdentifier");NSURL*url=ABMCValue(proxy,@"bundleURL");NSString*p=url.path;NSString*t=ABMCValue(proxy,@"applicationType");BOOL user=[p hasPrefix:@"/var/containers/Bundle/Application/"]||[p hasPrefix:@"/private/var/containers/Bundle/Application/"]||[p containsString:@"/TrollStore/"];if(!bid.length||![t isEqualToString:@"User"]||![p.pathExtension.lowercaseString isEqualToString:@"app"]||!user)return NO;for(NSString*x in @[@"Service",@"service",@"UIService",@"Helper",@"Widget",@"appex",@"/PlugIns/",@"/Extensions/"])if([p containsString:x])return NO;return YES;}@catch(NSException*e){return NO;}}
