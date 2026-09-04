#import "ABMCActionExecutor.h"
#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <dlfcn.h>

#define PREFS_DOMAIN CFSTR("com.huynguyen.actionbuttonmulticlick")
@interface UIImage (ABMCMenuIcon)
+ (instancetype)_applicationIconImageForBundleIdentifier:(NSString *)identifier format:(int)format scale:(CGFloat)scale;
@end

@interface ABMCActionExecutor ()
- (void)openFullscreenURL:(NSURL *)url;
- (void)openSavedLink:(NSString *)linkID;
- (void)openApp:(NSString *)bundleID;
- (void)runShortcutIdentifier:(NSString *)identifier name:(NSString *)name;
- (void)showActionPanel:(NSArray<NSString *> *)actions;
- (void)runShortcut:(NSString *)name;
- (void)showControlCenter;
- (void)showNotificationCenter;
@end

BOOL ABMCPerformingDefaultAction = NO;

@implementation ABMCActionExecutor {
    NSString *_singleAction;
    NSString *_doubleAction;
    NSString *_longPressAction;
    BOOL _useDirectFullscreenURLs;
}

+ (instancetype)sharedExecutor {
    static ABMCActionExecutor *instance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[ABMCActionExecutor alloc] init];
    });
    return instance;
}

- (instancetype)init {
    if (self = [super init]) {
        [self reloadPreferences];
    }
    return self;
}

- (void)reloadPreferences {
    CFPreferencesAppSynchronize(PREFS_DOMAIN);

    CFStringRef single = (CFStringRef)CFPreferencesCopyAppValue(CFSTR("singleClickAction"), PREFS_DOMAIN);
    CFStringRef dbl = (CFStringRef)CFPreferencesCopyAppValue(CFSTR("doubleClickAction"), PREFS_DOMAIN);
    CFStringRef longPress = (CFStringRef)CFPreferencesCopyAppValue(CFSTR("longPressAction"), PREFS_DOMAIN);

    @synchronized (self) {
        _singleAction = single ? (__bridge_transfer NSString *)single : @"default";
        _doubleAction = dbl ? (__bridge_transfer NSString *)dbl : @"none";
        _longPressAction = longPress ? (__bridge_transfer NSString *)longPress : @"default";

        CFPropertyListRef mode = CFPreferencesCopyAppValue(CFSTR("urlOpenMode"), PREFS_DOMAIN);
        _useDirectFullscreenURLs = (mode && CFGetTypeID(mode) == CFBooleanGetTypeID()) ? CFBooleanGetValue((CFBooleanRef)mode) : YES;
        if (mode) CFRelease(mode);
    }
}

- (NSString *)actionForClickCount:(NSInteger)count {
    @synchronized (self) {
        switch (count) {
            case 1: return [_singleAction copy];
            case 2: return [_doubleAction copy];
            default: return @"none";
        }
    }
}

- (void)executeActionForClickType:(NSInteger)clickType {
    NSString *action = [self actionForClickCount:clickType];
    [self executeAction:action];
}

- (BOOL)usesNativeLongPressAction { @synchronized(self) { return !_longPressAction || [_longPressAction isEqualToString:@"default"]; } }
- (BOOL)executeConfiguredLongPressAction {
    NSString *longPressAction;
    @synchronized (self) { longPressAction = [_longPressAction copy]; }
    if (!longPressAction || [longPressAction isEqualToString:@"default"]) return NO;
    [self executeAction:longPressAction];
    return YES;
}

- (void)executeAction:(NSString *)actionID {
    if (!actionID || [actionID isEqualToString:@"none"]) return;

    if ([actionID isEqualToString:@"default"]) {
        [self performDefaultAction];
    } else if ([actionID isEqualToString:@"flashlight"]) {
        [self toggleFlashlight];
    } else if ([actionID isEqualToString:@"camera"]) {
        [self openApp:@"com.apple.camera"];
    } else if ([actionID isEqualToString:@"silent"]) {
        [self toggleSilentMode];
    } else if ([actionID isEqualToString:@"screenshot"]) {
        [self takeScreenshot];
    } else if ([actionID isEqualToString:@"lock"]) {
        [self lockDevice];
    } else if ([actionID isEqualToString:@"controlCenter"]) {
        [self showControlCenter];
    } else if ([actionID isEqualToString:@"notificationCenter"]) {
        [self showNotificationCenter];
    } else if ([actionID isEqualToString:@"settings"]) {
        [self openApp:@"com.apple.Preferences"];
    } else if ([actionID isEqualToString:@"respring"]) {
        [self respring];
    } else if ([actionID isEqualToString:@"wechatScan"]) {
        [self openURLString:@"weixin://scanqrcode"];
    } else if ([actionID isEqualToString:@"wechatPay"]) {
        [self openURLString:@"weixin://widget/pay"];
    } else if ([actionID isEqualToString:@"alipayScan"]) {
        [self openURLString:@"alipay://platformapi/startapp?appId=10000007"];
    } else if ([actionID isEqualToString:@"alipayPay"]) {
        [self openURLString:@"alipay://platformapi/startapp?appId=20000056"];
    } else if ([actionID hasPrefix:@"app:"]) {
        [self openApp:[actionID substringFromIndex:4]];
    } else if ([actionID hasPrefix:@"url:"]) {
        [self openURLString:[actionID substringFromIndex:4]];
    } else if ([actionID hasPrefix:@"link:"]) {
        [self openSavedLink:[actionID substringFromIndex:5]];
    } else if ([actionID hasPrefix:@"shortcutid:"]) {
        NSString *payload = [actionID substringFromIndex:11];
        NSArray *parts = [payload componentsSeparatedByString:@"|"];
        [self runShortcutIdentifier:parts.firstObject name:(parts.count > 1 ? parts[1] : @"")];
    } else if ([actionID hasPrefix:@"actionpanel:"]) {
        NSString *panelID=[actionID substringFromIndex:12];
        CFPropertyListRef raw=CFPreferencesCopyAppValue(CFSTR("actionPanels"),PREFS_DOMAIN);
        NSArray *actions=raw&&CFGetTypeID(raw)==CFDictionaryGetTypeID()?[(__bridge NSDictionary *)raw objectForKey:panelID]:nil;
        if(raw)CFRelease(raw); [self showActionPanel:actions];
    } else if ([actionID hasPrefix:@"shortcutpanel:"]) {
        // Read-only migration for B10/B11 selections; never show the old custom grid.
        CFPropertyListRef raw=CFPreferencesCopyAppValue(CFSTR("shortcutPanels"),PREFS_DOMAIN);
        NSArray *items=raw&&CFGetTypeID(raw)==CFDictionaryGetTypeID()?[(__bridge NSDictionary *)raw objectForKey:[actionID substringFromIndex:14]]:nil;
        if(raw)CFRelease(raw); NSMutableArray *actions=[NSMutableArray array];
        for(NSDictionary *item in items)if([item isKindOfClass:NSDictionary.class]&&[item[@"identifier"] length])[actions addObject:[NSString stringWithFormat:@"shortcutid:%@|%@|%@|%@",item[@"identifier"],item[@"name"]?:@"快捷指令",item[@"glyph"]?:@0,item[@"color"]?:@0]];
        [self showActionPanel:actions];
    } else if ([actionID hasPrefix:@"shortcut:"]) {
        [self runShortcut:[actionID substringFromIndex:9]];
    }
}

#pragma mark - Default Action (replay through original hooks)

- (void)performDefaultAction {
    id button = self.buttonInstance;
    if (!button) return;

    ABMCPerformingDefaultAction = YES;
    @try {
        // Replay full cycle: buttonDown → longPress → buttonUp
        // buttonDown sets up internal state (assertions, preview)
        // longPress performs the configured action
        // buttonUp cleans up state (invalidates assertions, dismisses Dynamic Island)
        SEL downSel = NSSelectorFromString(@"performActionsForButtonDown:");
        SEL longPressSel = NSSelectorFromString(@"performActionsForButtonLongPress:");
        SEL upSel = NSSelectorFromString(@"performActionsForButtonUp:");

        if ([button respondsToSelector:downSel]) {
            ((void (*)(id, SEL, id))objc_msgSend)(button, downSel, self.lastDownEvent);
        }
        if ([button respondsToSelector:longPressSel]) {
            ((void (*)(id, SEL, id))objc_msgSend)(button, longPressSel, self.lastDownEvent);
        }
        if ([button respondsToSelector:upSel]) {
            ((void (*)(id, SEL, id))objc_msgSend)(button, upSel, self.lastDownEvent);
        }
    } @finally {
        ABMCPerformingDefaultAction = NO;
    }
}

#pragma mark - Flashlight (AVFoundation — stable public API)

- (void)toggleFlashlight {
    AVCaptureDevice *device = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
    if (![device hasTorch]) return;

    NSError *error = nil;
    [device lockForConfiguration:&error];
    if (error) return;

    if (device.torchMode == AVCaptureTorchModeOn) {
        device.torchMode = AVCaptureTorchModeOff;
    } else {
        [device setTorchModeOnWithLevel:AVCaptureMaxAvailableTorchLevel error:nil];
    }
    [device unlockForConfiguration];
}

#pragma mark - Silent Mode

- (void)toggleSilentMode {
    @try {
        id app = [UIApplication sharedApplication];
        SEL rcSel = NSSelectorFromString(@"ringerControl");
        if (![app respondsToSelector:rcSel]) return;

        id ringerControl = ((id (*)(id, SEL))objc_msgSend)(app, rcSel);
        if (!ringerControl) return;

        // Read current muted state — try multiple APIs
        BOOL isMuted = NO;
        BOOL didRead = NO;

        // 1) isRingerMuted (iOS 17)
        SEL isMutedSel = NSSelectorFromString(@"isRingerMuted");
        if ([ringerControl respondsToSelector:isMutedSel]) {
            isMuted = ((BOOL (*)(id, SEL))objc_msgSend)(ringerControl, isMutedSel);
            didRead = YES;
        }

        // 2) _accessibilityIsRingerMuted (iOS 26)
        if (!didRead) {
            SEL accSel = NSSelectorFromString(@"_accessibilityIsRingerMuted");
            if ([ringerControl respondsToSelector:accSel]) {
                isMuted = ((BOOL (*)(id, SEL))objc_msgSend)(ringerControl, accSel);
                didRead = YES;
            }
        }

        // 3) Read _ringerMuted ivar directly as last resort
        if (!didRead) {
            Ivar ivar = class_getInstanceVariable(object_getClass(ringerControl), "_ringerMuted");
            if (ivar) {
                ptrdiff_t offset = ivar_getOffset(ivar);
                isMuted = *(BOOL *)((uint8_t *)(__bridge void *)ringerControl + offset);
                didRead = YES;
            }
        }

        if (!didRead) return;

        // Write new state
        SEL fullSetSel = NSSelectorFromString(@"setRingerMuted:withFeedback:reason:clientType:");
        if ([ringerControl respondsToSelector:fullSetSel]) {
            ((void (*)(id, SEL, BOOL, BOOL, id, unsigned))objc_msgSend)(
                ringerControl, fullSetSel, !isMuted, YES, @"RealActionButton", 0
            );
            return;
        }

        SEL simpleSetSel = NSSelectorFromString(@"setRingerMuted:");
        if ([ringerControl respondsToSelector:simpleSetSel]) {
            ((void (*)(id, SEL, BOOL))objc_msgSend)(ringerControl, simpleSetSel, !isMuted);
        }
    } @catch (NSException *e) {
        // Prevent safe mode crash
    }
}

#pragma mark - Screenshot

- (void)takeScreenshot {
    @try {
        id app = [UIApplication sharedApplication];

        SEL managerSel = NSSelectorFromString(@"screenshotManager");
        if ([app respondsToSelector:managerSel]) {
            id manager = ((id (*)(id, SEL))objc_msgSend)(app, managerSel);
            if (manager) {
                SEL saveSel = NSSelectorFromString(@"saveScreenshotsWithCompletion:");
                if ([manager respondsToSelector:saveSel]) {
                    ((void (*)(id, SEL, id))objc_msgSend)(manager, saveSel, nil);
                    return;
                }
            }
        }

        Class shotterClass = NSClassFromString(@"SBScreenShotter");
        if (shotterClass) {
            SEL sharedSel = NSSelectorFromString(@"sharedInstance");
            if ([shotterClass respondsToSelector:sharedSel]) {
                id instance = ((id (*)(id, SEL))objc_msgSend)(shotterClass, sharedSel);
                SEL saveSel = NSSelectorFromString(@"saveScreenshot");
                if (instance && [instance respondsToSelector:saveSel]) {
                    ((void (*)(id, SEL))objc_msgSend)(instance, saveSel);
                }
            }
        }
    } @catch (NSException *e) {}
}

#pragma mark - System Panels

- (void)showControlCenter {
    dispatch_async(dispatch_get_main_queue(), ^{
        @try {
            Class c = NSClassFromString(@"SBControlCenterController");
            SEL shared = NSSelectorFromString(@"sharedInstance");
            id controller = c && [c respondsToSelector:shared] ? ((id (*)(id, SEL))objc_msgSend)(c, shared) : nil;
            for (NSString *name in @[@"presentAnimated:", @"_presentAnimated:"]) {
                SEL selector = NSSelectorFromString(name);
                if ([controller respondsToSelector:selector]) { ((void (*)(id, SEL, BOOL))objc_msgSend)(controller, selector, YES); return; }
            }
        } @catch (NSException *exception) {}
    });
}

- (void)showNotificationCenter {
    dispatch_async(dispatch_get_main_queue(), ^{
        @try {
            // iOS 17's accessibility SpringBoard server owns the reliable
            // notification-center presentation path.
            dlopen("/System/Library/PrivateFrameworks/AccessibilityUtilities.framework/AccessibilityUtilities", RTLD_LAZY | RTLD_LOCAL);
            Class serverClass = NSClassFromString(@"AXSpringBoardServer");
            SEL serverSelector = NSSelectorFromString(@"server");
            id server = serverClass && [serverClass respondsToSelector:serverSelector] ? ((id (*)(id, SEL))objc_msgSend)(serverClass, serverSelector) : nil;
            SEL show = NSSelectorFromString(@"showNotificationCenter:");
            if ([server respondsToSelector:show] && ((BOOL (*)(id, SEL, BOOL))objc_msgSend)(server, show, YES)) return;
            SEL plainShow = NSSelectorFromString(@"showNotificationCenter");
            if ([server respondsToSelector:plainShow]) { ((void (*)(id, SEL))objc_msgSend)(server, plainShow); return; }
            Class workspaceClass = NSClassFromString(@"SBMainWorkspace");
            SEL sharedWorkspace = NSSelectorFromString(@"sharedInstance");
            id workspace = workspaceClass && [workspaceClass respondsToSelector:sharedWorkspace] ? ((id (*)(id, SEL))objc_msgSend)(workspaceClass, sharedWorkspace) : nil;
            SEL workspaceShow = NSSelectorFromString(@"showNotificationCenter");
            if ([workspace respondsToSelector:workspaceShow]) ((void (*)(id, SEL))objc_msgSend)(workspace, workspaceShow);
        } @catch (NSException *exception) {}
    });
}

#pragma mark - Lock Device

- (void)lockDevice {
    @try {
        id app = [UIApplication sharedApplication];
        SEL sel = NSSelectorFromString(@"_simulateLockButtonPress");
        if ([app respondsToSelector:sel]) {
            ((void (*)(id, SEL))objc_msgSend)(app, sel);
        }
    } @catch (NSException *e) {}
}

#pragma mark - Respring

- (void)respring {
    Class fbService = NSClassFromString(@"FBSystemService");
    if (fbService) {
        SEL sharedSel = NSSelectorFromString(@"sharedInstance");
        if ([fbService respondsToSelector:sharedSel]) {
            id instance = ((id (*)(id, SEL))objc_msgSend)(fbService, sharedSel);
            SEL relaunchSel = NSSelectorFromString(@"exitAndRelaunch:");
            if (instance && [instance respondsToSelector:relaunchSel]) {
                ((void (*)(id, SEL, BOOL))objc_msgSend)(instance, relaunchSel, YES);
                return;
            }
        }
    }
    exit(0);
}

#pragma mark - Open App

- (void)openApp:(NSString *)bundleID {
    // Stable B2 system application-launch route.
    if (!bundleID.length) return;
    NSString *bid=[bundleID copy];
    dispatch_async(dispatch_get_main_queue(), ^{
        @autoreleasepool { @try {
            // SQ's static implementation uses this asynchronous SpringBoard
            // UIApplication route. App launch is independent of URL actions:
            // WeChat/Alipay scan and pay continue through openURLString only.
            SEL launch=NSSelectorFromString(@"launchApplicationWithIdentifier:suspended:");
            if([UIApplication.sharedApplication respondsToSelector:launch]) ((BOOL(*)(id,SEL,id,BOOL))objc_msgSend)(UIApplication.sharedApplication,launch,bid,NO);
        } @catch(NSException *exception) {} }
    });
}

#pragma mark - Open URL

- (void)openURLString:(NSString *)urlString {
    if (!urlString.length) return;

    NSURL *url = [NSURL URLWithString:urlString];
    if (!url) return;

    BOOL useDirectFullscreenURLs;
    @synchronized (self) {
        useDirectFullscreenURLs = _useDirectFullscreenURLs;
    }
    if (useDirectFullscreenURLs) {
        [self openFullscreenURL:url];
        return;
    }

    // Keep the original UIApplication route for FV/PullOver compatibility,
    // but never block the click callback while URL routing is performed.
    dispatch_async(dispatch_get_main_queue(), ^{
        @autoreleasepool {
            @try {
                id app = [UIApplication sharedApplication];
                SEL openSel = NSSelectorFromString(@"openURL:options:completionHandler:");
                if ([app respondsToSelector:openSel]) {
                    ((void (*)(id, SEL, id, id, id))objc_msgSend)(app, openSel, url, @{}, nil);
                }
            } @catch (NSException *e) {}
        }
    });
}

// This is intentionally kept separate from the original URL path so the
// setting can switch between direct full-screen launching and FV-compatible
// URL launching without changing action identifiers or saved custom URLs.
- (void)openFullscreenURL:(NSURL *)url {
    dispatch_async(dispatch_get_main_queue(), ^{
        @autoreleasepool {
            @try {
                id app = [UIApplication sharedApplication];
                SEL openSel = NSSelectorFromString(@"applicationOpenURL:");
                if ([app respondsToSelector:openSel]) {
                    BOOL opened = ((BOOL (*)(id, SEL, NSURL *))objc_msgSend)(app, openSel, url);
                    if (!opened) return;
                }
            } @catch (NSException *e) {
                // A missing/changed private selector must not crash SpringBoard.
            }
        }
    });
}

#pragma mark - Saved Links and Shortcuts

- (void)openSavedLink:(NSString *)linkID {
    if (!linkID.length) return;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        CFPropertyListRef value = CFPreferencesCopyAppValue(CFSTR("savedLinks"), PREFS_DOMAIN);
        NSString *urlString = nil;
        if (value && CFGetTypeID(value) == CFArrayGetTypeID()) {
            for (NSDictionary *link in (__bridge NSArray *)value) {
                if ([link isKindOfClass:[NSDictionary class]] && [link[@"id"] isEqualToString:linkID]) {
                    urlString = [link[@"url"] copy];
                    break;
                }
            }
        }
        if (value) CFRelease(value);
        if (urlString.length) [self openURLString:urlString];
    });
}

- (void)runShortcutIdentifier:(NSString *)identifier name:(NSString *)name {
    if (!identifier.length && !name.length) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        BOOL submitted = NO;
        @try {
            // Apple ships this runner specifically for SpringBoard. It runs the
            // saved workflow by identifier without presenting Shortcuts first.
            dlopen("/System/Library/PrivateFrameworks/VoiceShortcutClient.framework/VoiceShortcutClient", RTLD_LAZY | RTLD_LOCAL);
            Class runnerClass = NSClassFromString(@"WFSpringBoardWorkflowRunnerClient");
            SEL initializer = NSSelectorFromString(@"initWithWorkflowIdentifier:");
            SEL start = NSSelectorFromString(@"start");
            if ([runnerClass instancesRespondToSelector:initializer]) {
                id runner = ((id (*)(id, SEL, id))objc_msgSend)([runnerClass alloc], initializer, identifier);
                if (runner && [runner respondsToSelector:start]) {
                    ((void (*)(id, SEL))objc_msgSend)(runner, start);
                    submitted = YES;
                }
            }
        } @catch (NSException *exception) {}
        // URL is intentionally only the final compatibility fallback when the
        // SpringBoard-specific system runner is unavailable on an OS build.
        if (!submitted) [self runShortcut:name];
    });
}

- (NSString *)nativePanelTitleForAction:(NSString *)action {
    if([action hasPrefix:@"shortcutid:"]){NSArray *p=[[action substringFromIndex:11]componentsSeparatedByString:@"|"];return p.count>1?p[1]:@"快捷指令";}
    if([action hasPrefix:@"app:"]){NSString *bid=[action substringFromIndex:4];Class c=NSClassFromString(@"LSApplicationWorkspace");SEL d=NSSelectorFromString(@"defaultWorkspace"),f=NSSelectorFromString(@"applicationProxyForIdentifier:");id w=[c respondsToSelector:d]?((id(*)(id,SEL))objc_msgSend)(c,d):nil;id proxy=[w respondsToSelector:f]?((id(*)(id,SEL,id))objc_msgSend)(w,f,bid):nil;SEL n=NSSelectorFromString(@"localizedName");NSString *name=[proxy respondsToSelector:n]?((id(*)(id,SEL))objc_msgSend)(proxy,n):nil;return name.length?name:bid;}
    if([action hasPrefix:@"url:"])return [action substringFromIndex:4];
    if([action hasPrefix:@"link:"]){CFPropertyListRef raw=CFPreferencesCopyAppValue(CFSTR("savedLinks"),PREFS_DOMAIN);NSString *title=nil;for(NSDictionary *x in (raw&&CFGetTypeID(raw)==CFArrayGetTypeID()?(__bridge NSArray*)raw:@[]))if([x[@"id"]isEqual:[action substringFromIndex:5]]){title=x[@"title"];break;}if(raw)CFRelease(raw);return title ?: @"URL";}
    NSDictionary *names=@{ @"default":@"系统默认",@"flashlight":@"手电筒",@"camera":@"相机",@"silent":@"静音切换",@"screenshot":@"截屏",@"lock":@"锁屏",@"controlCenter":@"控制中心",@"notificationCenter":@"通知中心",@"settings":@"打开设置",@"respring":@"重启界面",@"wechatScan":@"微信扫码",@"wechatPay":@"微信付款码",@"alipayScan":@"支付宝扫码",@"alipayPay":@"支付宝付款码"};return names[action] ?: @"动作";
}
- (UIImage *)nativePanelIconForAction:(NSString *)action {
    NSString *token=nil;if([action hasPrefix:@"app:"])token=[action substringFromIndex:4];else if([action hasPrefix:@"shortcutid:"])token=@"square.stack.3d.up.fill";else if([action hasPrefix:@"link:"]||[action hasPrefix:@"url:"])token=@"link";else { NSDictionary *icons=@{ @"default":@"gearshape.fill",@"flashlight":@"flashlight.on.fill",@"camera":@"camera.fill",@"silent":@"bell.slash.fill",@"screenshot":@"viewfinder",@"lock":@"lock.fill",@"controlCenter":@"switch.2",@"notificationCenter":@"bell.fill",@"settings":@"gearshape.fill",@"respring":@"arrow.clockwise",@"wechatScan":@"qrcode.viewfinder",@"wechatPay":@"creditcard.fill",@"alipayScan":@"qrcode.viewfinder",@"alipayPay":@"creditcard.fill"};token=icons[action] ?: @"square.grid.2x2.fill";}
    UIImage *icon=[UIImage systemImageNamed:token];if(!icon&&token.length){@try{icon=[UIImage _applicationIconImageForBundleIdentifier:token format:0 scale:UIScreen.mainScreen.scale];}@catch(NSException *e){}}return icon ?: [UIImage systemImageNamed:@"square.grid.2x2.fill"];
}
- (void)showActionPanel:(NSArray<NSString *> *)actions {
    NSMutableOrderedSet *unique=[NSMutableOrderedSet orderedSet];for(id action in actions)if([action isKindOfClass:NSString.class]&&[action length]&&![action isEqualToString:@"none"])[unique addObject:action];NSArray *limited=[unique.array subarrayWithRange:NSMakeRange(0,MIN((NSUInteger)8,unique.count))];if(!limited.count)return;if(limited.count==1){[self executeAction:limited.firstObject];return;}
    dispatch_async(dispatch_get_main_queue(), ^{ @autoreleasepool { @try {
        UIWindow *window=nil;for(UIScene *scene in UIApplication.sharedApplication.connectedScenes){if(![scene isKindOfClass:UIWindowScene.class]||scene.activationState!=UISceneActivationStateForegroundActive)continue;for(UIWindow *candidate in ((UIWindowScene *)scene).windows)if(candidate.isKeyWindow){window=candidate;break;}if(window)break;}UIViewController *host=window.rootViewController;while(host.presentedViewController)host=host.presentedViewController;if(!host)return;
        NSMutableArray *children=[NSMutableArray array];for(NSString *action in limited){UIAction *item=[UIAction actionWithTitle:[self nativePanelTitleForAction:action] image:[self nativePanelIconForAction:action] identifier:nil handler:^(__kindof UIAction *x){[self executeAction:action];}];[children addObject:item];}
        // UIKit's native menu rows are the system folder-style banner list and support image + title.
        UIMenu *menu=[UIMenu menuWithTitle:@"选择动作" children:children];UIButton *anchor=[UIButton buttonWithType:UIButtonTypeSystem];anchor.frame=CGRectMake(CGRectGetMidX(host.view.bounds)-1,CGRectGetMaxY(host.view.bounds)-2,2,2);anchor.alpha=0.01;anchor.menu=menu;anchor.showsMenuAsPrimaryAction=YES;[host.view addSubview:anchor];[anchor sendActionsForControlEvents:UIControlEventTouchUpInside];dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(1*NSEC_PER_SEC)),dispatch_get_main_queue(),^{[anchor removeFromSuperview];});
    } @catch(NSException *e){} } });
}

- (void)runShortcut:(NSString *)name {
    if (!name.length) return;
    NSString *encoded = [name stringByAddingPercentEncodingWithAllowedCharacters:NSCharacterSet.URLQueryAllowedCharacterSet];
    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"shortcuts://run-shortcut?name=%@", encoded]];
    if (!url) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        @try {
            SEL open = NSSelectorFromString(@"openURL:options:completionHandler:");
            if ([UIApplication.sharedApplication respondsToSelector:open]) ((void (*)(id, SEL, id, id, id))objc_msgSend)(UIApplication.sharedApplication, open, url, @{}, nil);
        } @catch (NSException *exception) {}
    });
}

@end
