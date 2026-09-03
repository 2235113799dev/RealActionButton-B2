#import "ABMCUIHelpers.h"
#import <objc/message.h>

static NSCache *ABMCIconCache;
static id ABMCValue(id object, NSString *name) { SEL s=NSSelectorFromString(name); return object&&[object respondsToSelector:s]?((id(*)(id,SEL))objc_msgSend)(object,s):nil; }
static id ABMCProxy(NSString *bundleID) { Class c=NSClassFromString(@"LSApplicationWorkspace");id w=ABMCValue(c,@"defaultWorkspace");SEL s=NSSelectorFromString(@"applicationProxyForBundleIdentifier:");return w&&[w respondsToSelector:s]?((id(*)(id,SEL,id))objc_msgSend)(w,s,bundleID):nil; }

static UIImage *ABMCResizeIcon(UIImage *image) {
    if (!image) return nil;
    CGFloat side=30.0, scale=UIScreen.mainScreen.scale;
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(side,side),NO,scale);
    [image drawInRect:CGRectMake(0,0,side,side)];
    UIImage *result=UIGraphicsGetImageFromCurrentImageContext(); UIGraphicsEndImageContext();
    return result;
}

static UIImage *ABMCImageFromBundle(NSURL *url) {
    if(!url)return nil;
    NSBundle *bundle=[NSBundle bundleWithURL:url]; NSDictionary *info=bundle.infoDictionary;
    NSMutableOrderedSet *names=[NSMutableOrderedSet orderedSet];
    NSDictionary *icons=info[@"CFBundleIcons"]?:info[@"CFBundleIcons~ipad"]; NSDictionary *primary=[icons isKindOfClass:[NSDictionary class]]?icons[@"CFBundlePrimaryIcon"]:nil;
    NSArray *files=[primary isKindOfClass:[NSDictionary class]]?primary[@"CFBundleIconFiles"]:nil;
    if([files isKindOfClass:[NSArray class]])[names addObjectsFromArray:files];
    NSString *legacy=info[@"CFBundleIconFile"];if(legacy.length)[names addObject:legacy];
    [names addObjectsFromArray:@[@"AppIcon",@"AppIcon60x60",@"Icon60",@"Icon"]];
    for(NSString *name in names){
        NSString *stem=[name stringByDeletingPathExtension];
        UIImage *image=[UIImage imageNamed:stem inBundle:bundle compatibleWithTraitCollection:nil];
        if(image)return image;
        // 已编译的 AppIcon 位于 Assets.car，不能用普通文件路径读取。
        Class catalogClass=NSClassFromString(@"CUICatalog"); SEL init=NSSelectorFromString(@"initWithURL:error:");
        id catalog=catalogClass?[[catalogClass alloc]init]:nil;
        if(catalog&&[catalog respondsToSelector:init]){
            NSError *error=nil; catalog=((id(*)(id,SEL,id,id*))objc_msgSend)(catalog,init,[url URLByAppendingPathComponent:@"Assets.car"],&error);
            SEL imageSelector=NSSelectorFromString(@"imageWithName:scaleFactor:deviceIdiom:");
            if(catalog&&[catalog respondsToSelector:imageSelector]){
                image=((id(*)(id,SEL,id,CGFloat,NSInteger))objc_msgSend)(catalog,imageSelector,stem,UIScreen.mainScreen.scale,0);
                if([image isKindOfClass:[UIImage class]])return image;
            }
        }
        for(NSString *candidate in @[[stem stringByAppendingPathExtension:@"png"],[stem stringByAppendingString:@"@2x.png"],[stem stringByAppendingString:@"@3x.png"]]){image=[UIImage imageWithContentsOfFile:[url.path stringByAppendingPathComponent:candidate]];if(image)return image;}
    }
    return nil;
}

UIImage *ABMCIconImageForProxy(id proxy) {
    if(!proxy)return nil;
    @try {
        for(NSString *name in @[@"icon",@"applicationIcon",@"primaryIcon"]) { id v=ABMCValue(proxy,name);if([v isKindOfClass:[UIImage class]])return ABMCResizeIcon(v); }
        for(NSString *name in @[@"iconData",@"primaryIconData",@"smallIconData"]) { NSData *d=ABMCValue(proxy,name);UIImage *i=[d isKindOfClass:[NSData class]]?[UIImage imageWithData:d]:nil;if(i)return ABMCResizeIcon(i); }
        SEL primary=NSSelectorFromString(@"primaryIconDataForVariant:"), data=NSSelectorFromString(@"iconDataForVariant:"), option=NSSelectorFromString(@"iconDataForVariant:withOptions:");
        for(NSInteger v=0;v<32;v++){
            NSData*d=nil;
            if([proxy respondsToSelector:primary]) d=((id(*)(id,SEL,NSInteger))objc_msgSend)(proxy,primary,v);
            if(!d&&[proxy respondsToSelector:data]) d=((id(*)(id,SEL,NSInteger))objc_msgSend)(proxy,data,v);
            if(!d&&[proxy respondsToSelector:option]) d=((id(*)(id,SEL,NSInteger,NSUInteger))objc_msgSend)(proxy,option,v,0);
            UIImage*i=[d isKindOfClass:[NSData class]]?[UIImage imageWithData:d]:nil;if(i)return ABMCResizeIcon(i);
        }
        UIImage *bundleIcon = ABMCImageFromBundle(ABMCValue(proxy,@"bundleURL"));
        if (bundleIcon) return ABMCResizeIcon(bundleIcon);
        NSString *bundleID = ABMCValue(proxy, @"bundleIdentifier");
        id application = [UIApplication respondsToSelector:@selector(sharedApplication)] ? UIApplication.sharedApplication : nil;
        for (NSString *name in @[@"_applicationIconImageForBundleIdentifier:format:scale:", @"applicationIconImageForBundleIdentifier:format:scale:"]) {
            SEL selector = NSSelectorFromString(name);
            if ([application respondsToSelector:selector]) {
                UIImage *icon = ((id (*)(id, SEL, id, NSInteger, CGFloat))objc_msgSend)(application, selector, bundleID, 2, UIScreen.mainScreen.scale);
                if ([icon isKindOfClass:[UIImage class]]) return ABMCResizeIcon(icon);
            }
        }
        return nil;
    }@catch(NSException *exception){return nil;}
}

UIImage *ABMCIconImageForBundleID(NSString *bundleID){
    if(!bundleID.length)return nil;
    static dispatch_once_t once;dispatch_once(&once,^{ABMCIconCache=[NSCache new];ABMCIconCache.countLimit=300;});
    UIImage *cached=[ABMCIconCache objectForKey:bundleID];if(cached)return cached;
    UIImage *image=ABMCIconImageForProxy(ABMCProxy(bundleID));if(image)[ABMCIconCache setObject:image forKey:bundleID];return image;
}
UIImage *ABMCIconImage(NSString *token){UIImageSymbolConfiguration*c=[UIImageSymbolConfiguration configurationWithPointSize:22 weight:UIImageSymbolWeightMedium];UIImage*s=token.length?[UIImage systemImageNamed:token withConfiguration:c]:nil;if(s)return s;return ABMCIconImageForBundleID(token)?:[UIImage systemImageNamed:@"app.fill" withConfiguration:c];}
UIImage *ABMCTintedIcon(NSString *token,UIColor *color){UIImage*i=ABMCIconImage(token);return[UIImage systemImageNamed:token]?[i imageWithTintColor:color renderingMode:UIImageRenderingModeAlwaysOriginal]:i;}
NSString *ABMCInferLinkIcon(NSString *url){NSString*s=[NSURL URLWithString:url].scheme.lowercaseString;if([s isEqualToString:@"http"]||[s isEqualToString:@"https"])return @"safari.fill";if([s isEqualToString:@"weixin"])return @"com.tencent.xin";if([s isEqualToString:@"alipay"])return @"com.alipay.iphoneclient";if([s isEqualToString:@"mailto"])return @"envelope.fill";if([s isEqualToString:@"tel"]||[s isEqualToString:@"sms"])return @"phone.fill";return @"link";}
NSString *ABMCApplicationName(NSString *bundleID){NSString*n=ABMCValue(ABMCProxy(bundleID),@"localizedName");return n.length?n:(bundleID?:@"未知应用");}
BOOL ABMCIsAllowedStoreApplicationProxy(id proxy){if(!proxy)return NO;@try{NSString*bid=ABMCValue(proxy,@"bundleIdentifier");NSURL*url=ABMCValue(proxy,@"bundleURL");NSString*p=url.path;NSString*t=ABMCValue(proxy,@"applicationType");BOOL user=[p hasPrefix:@"/var/containers/Bundle/Application/"]||[p hasPrefix:@"/private/var/containers/Bundle/Application/"]||[p containsString:@"/TrollStore/"];if(!bid.length||![t isEqualToString:@"User"]||![p.pathExtension.lowercaseString isEqualToString:@"app"]||!user)return NO;for(NSString*x in @[@"Service",@"service",@"UIService",@"Helper",@"Widget",@"appex",@"/PlugIns/",@"/Extensions/"])if([p containsString:x])return NO;return YES;}@catch(NSException*e){return NO;}}
