#import "ABMCActionPanel.h"
#import "ABMCActionExecutor.h"
#import <UIKit/UIKit.h>
#import <objc/message.h>
#import <dlfcn.h>

#define PREFS_DOMAIN CFSTR("com.huynguyen.actionbuttonmulticlick")

@interface UIImage (ABMCActionPanelIcon)
+ (instancetype)_applicationIconImageForBundleIdentifier:(NSString *)identifier format:(int)format scale:(CGFloat)scale;
@end

@class ABMCActionPanel;
@interface ABMCActionPanel (BackdropActions)
- (void)backgroundTapped:(id)sender;
@end
@interface ABMCPanelBackdrop : UIView
@property(nonatomic,weak) ABMCActionPanel *owner;
@property(nonatomic,weak) UIView *card;
@end
@implementation ABMCPanelBackdrop
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event { UIView *hit=[super hitTest:point withEvent:event];return (self.card&&hit&&[hit isDescendantOfView:self.card])?hit:self; }
- (void)touchesEnded:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event { [self.owner backgroundTapped:nil]; }
@end

@interface ABMCActionPanel ()
@property(nonatomic,strong) UIWindow *window;
@property(nonatomic,weak) UIWindow *hostWindow;
@property(nonatomic,strong) UIView *card;
@property(nonatomic,strong) UIView *content;
@property(nonatomic,assign) CGPoint panelCenter;
@property(nonatomic,assign) BOOL darkPanel;
@property(nonatomic,copy) NSArray<NSString *> *actions;
@property(nonatomic,weak) ABMCActionExecutor *executor;
@end

@implementation ABMCActionPanel
+ (instancetype)sharedPanel { static ABMCActionPanel *p;static dispatch_once_t once;dispatch_once(&once,^{p=[self new];});return p; }

static id ABMCPanelCall(id object, NSString *name) { SEL s=NSSelectorFromString(name);return object&&[object respondsToSelector:s]?((id(*)(id,SEL))objc_msgSend)(object,s):nil; }
static id ABMCPanelApplicationProxy(NSString *bundleID) { Class proxyClass=NSClassFromString(@"LSApplicationProxy");SEL direct=NSSelectorFromString(@"applicationProxyForIdentifier:");id proxy=proxyClass&&[proxyClass respondsToSelector:direct]?((id(*)(id,SEL,id))objc_msgSend)(proxyClass,direct,bundleID):nil;Class c=NSClassFromString(@"LSApplicationWorkspace");SEL d=NSSelectorFromString(@"defaultWorkspace");id w=c&&[c respondsToSelector:d]?((id(*)(id,SEL))objc_msgSend)(c,d):nil;SEL p=NSSelectorFromString(@"applicationProxyForIdentifier:");if(!proxy&&w&&[w respondsToSelector:p])proxy=((id(*)(id,SEL,id))objc_msgSend)(w,p,bundleID);if(!proxy){SEL all=NSSelectorFromString(@"allInstalledApplications");for(id item in (w&&[w respondsToSelector:all]?((id(*)(id,SEL))objc_msgSend)(w,all):@[]))if([[ABMCPanelCall(item,@"bundleIdentifier") description] isEqualToString:bundleID]){proxy=item;break;}}return proxy; }
static NSString *ABMCPanelAppName(NSString *bundleID) { id proxy=ABMCPanelApplicationProxy(bundleID);NSString *name=ABMCPanelCall(proxy,@"localizedName");if(!name.length)name=ABMCPanelCall(proxy,@"localizedShortName");if(!name.length)name=ABMCPanelCall(proxy,@"itemName");if(!name.length){Class c=NSClassFromString(@"SBApplicationController");SEL shared=NSSelectorFromString(@"sharedInstance"),find=NSSelectorFromString(@"applicationWithBundleIdentifier:");id controller=c&&[c respondsToSelector:shared]?((id(*)(id,SEL))objc_msgSend)(c,shared):nil;id app=controller&&[controller respondsToSelector:find]?((id(*)(id,SEL,id))objc_msgSend)(controller,find,bundleID):nil;name=ABMCPanelCall(app,@"displayName");}if(!name.length){NSURL *url=ABMCPanelCall(proxy,@"bundleURL");NSDictionary *info=[NSBundle bundleWithURL:url].infoDictionary;name=info[@"CFBundleDisplayName"] ?: info[@"CFBundleName"];}return name.length?name:bundleID; }
static NSDictionary *ABMCPanelLinkRecord(NSString *identifier) { CFPropertyListRef raw=CFPreferencesCopyAppValue(CFSTR("savedLinks"),PREFS_DOMAIN);NSDictionary *record=nil;for(NSDictionary *link in (raw&&CFGetTypeID(raw)==CFArrayGetTypeID()?(__bridge NSArray *)raw:@[]))if([link[@"id"] isEqualToString:identifier]){record=[link copy];break;}if(raw)CFRelease(raw);return record ?: @{}; }
static NSString *ABMCPanelLinkTitle(NSString *identifier) { NSString *title=ABMCPanelLinkRecord(identifier)[@"title"];return title.length?title:@"链接"; }
static NSString *ABMCPanelTitle(NSString *action) {
    if([action hasPrefix:@"app:"])return ABMCPanelAppName([action substringFromIndex:4]);
    if([action hasPrefix:@"shortcutid:"]){NSArray *p=[[action substringFromIndex:11] componentsSeparatedByString:@"|"];return p.count>1?p[1]:@"快捷指令";}
    if([action hasPrefix:@"link:"])return ABMCPanelLinkTitle([action substringFromIndex:5]);
    NSDictionary *names=@{@"default":@"系统默认",@"flashlight":@"手电筒",@"camera":@"相机",@"silent":@"静音",@"screenshot":@"截屏",@"lock":@"锁屏",@"controlCenter":@"控制中心",@"notificationCenter":@"通知中心",@"settings":@"设置",@"respring":@"重启",@"wechatScan":@"微信扫码",@"wechatPay":@"微信付款码",@"alipayScan":@"支付宝扫码",@"alipayPay":@"支付宝付款码"};return names[action] ?: @"动作";
}
static NSString *ABMCPanelSymbol(NSString *action) {
    NSDictionary *icons=@{@"default":@"gearshape.fill",@"flashlight":@"flashlight.on.fill",@"camera":@"camera.fill",@"silent":@"bell.slash.fill",@"screenshot":@"viewfinder",@"lock":@"lock.fill",@"controlCenter":@"switch.2",@"notificationCenter":@"bell.fill",@"settings":@"gearshape.fill",@"respring":@"arrow.clockwise",@"wechatScan":@"qrcode.viewfinder",@"wechatPay":@"creditcard.fill",@"alipayScan":@"qrcode.viewfinder",@"alipayPay":@"creditcard.fill"};if([action hasPrefix:@"shortcutid:"])return @"square.stack.3d.up.fill";if([action hasPrefix:@"link:"]||[action hasPrefix:@"url:"])return @"link";return icons[action] ?: @"square.grid.2x2.fill";
}
static UIWindow *ABMCPanelKeyWindow(void) { for(UIScene *raw in UIApplication.sharedApplication.connectedScenes){if(![raw isKindOfClass:UIWindowScene.class]||raw.activationState!=UISceneActivationStateForegroundActive)continue;UIWindowScene *scene=(UIWindowScene *)raw;for(UIWindow *window in scene.windows)if(window.isKeyWindow)return window;for(UIWindow *window in scene.windows)if(!window.hidden&&window.alpha>.01)return window;}return nil; }
static BOOL ABMCPanelIsDark(UIWindow *host) { return host.traitCollection.userInterfaceStyle==UIUserInterfaceStyleDark; }
static UIColor *ABMCPanelBackgroundColor(BOOL dark) { return dark?[UIColor colorWithWhite:.11 alpha:1.0]:[UIColor colorWithWhite:.965 alpha:1.0]; }
static UIColor *ABMCPanelTileColor(BOOL dark, BOOL artwork) { return artwork?(dark?[UIColor colorWithWhite:.25 alpha:1]:[UIColor colorWithWhite:.92 alpha:1]):UIColor.systemIndigoColor; }
static UIColor *ABMCPanelTileBorder(BOOL dark) { return dark?[UIColor colorWithWhite:.23 alpha:1]:[UIColor colorWithWhite:.88 alpha:1]; }
static CGFloat ABMCPanelIconSize(void) { CFPropertyListRef v=CFPreferencesCopyAppValue(CFSTR("unifiedIconSize"),PREFS_DOMAIN);CGFloat size=v&&CFGetTypeID(v)==CFNumberGetTypeID()?[(__bridge NSNumber *)v doubleValue]:30.0;if(v)CFRelease(v);return MIN(48.0,MAX(12.0,size)); }
static NSString *ABMCPanelPreferredBundle(NSString *action) {
    NSDictionary *mapped=@{@"wechatScan":@"com.tencent.xin",@"wechatPay":@"com.tencent.xin",@"alipayScan":@"com.alipay.iphoneclient",@"alipayPay":@"com.alipay.iphoneclient"};
    if([action hasPrefix:@"app:"])return [action substringFromIndex:4];
    if([action hasPrefix:@"link:"])return ABMCPanelLinkRecord([action substringFromIndex:5])[@"icon"];
    return mapped[action];
}
static BOOL ABMCPanelUsesArtwork(NSString *action) { NSString *bundle=ABMCPanelPreferredBundle(action);return bundle.length||[action hasPrefix:@"shortcutid:"]; }
static UIImage *ABMCPanelAppIcon(NSString *bundleID) { UIImage *image=nil;@try{image=[UIImage _applicationIconImageForBundleIdentifier:bundleID format:2 scale:UIScreen.mainScreen.scale];}@catch(__unused NSException *e){}return image; }
static UIImage *ABMCPanelWorkflowIcon(NSString *action) { NSArray *p=[[action substringFromIndex:11] componentsSeparatedByString:@"|"];if(p.count<4)return nil;@try{dlopen("/System/Library/PrivateFrameworks/VoiceShortcutClient.framework/VoiceShortcutClient",RTLD_LAZY|RTLD_LOCAL);Class icon=NSClassFromString(@"WFWorkflowIcon"),drawer=NSClassFromString(@"WFWorkflowIconDrawer");SEL make=NSSelectorFromString(@"initWithBackgroundColorValue:glyphCharacter:customImageData:"),draw=NSSelectorFromString(@"imageWithIcon:size:background:");if(![icon instancesRespondToSelector:make]||![drawer respondsToSelector:draw])return nil;id value=((id(*)(id,SEL,long long,unsigned short,id))objc_msgSend)([icon alloc],make,[p[3] longLongValue],(unsigned short)[p[2] integerValue],nil);id rendered=value?((id(*)(id,SEL,id,CGSize,BOOL))objc_msgSend)(drawer,draw,value,CGSizeMake(48,48),YES):nil;SEL image=NSSelectorFromString(@"UIImage");return[rendered isKindOfClass:UIImage.class]?rendered:([rendered respondsToSelector:image]?((id(*)(id,SEL))objc_msgSend)(rendered,image):nil);}@catch(__unused NSException *e){return nil;} }
static UIImage *ABMCPanelIcon(NSString *action) {
    // Identifier-backed artwork is always preferred, including payment routes.
    NSString *bundle=ABMCPanelPreferredBundle(action);if(bundle.length){UIImage *image=ABMCPanelAppIcon(bundle);if(image)return image;}
    if([action hasPrefix:@"shortcutid:"]){UIImage *image=ABMCPanelWorkflowIcon(action);if(image)return image;}
    if([action hasPrefix:@"link:"]){NSString *token=ABMCPanelLinkRecord([action substringFromIndex:5])[@"icon"];if(token.length){UIImageSymbolConfiguration *config=[UIImageSymbolConfiguration configurationWithPointSize:ABMCPanelIconSize() weight:UIImageSymbolWeightMedium];UIImage *symbol=[UIImage systemImageNamed:token withConfiguration:config];if(symbol)return[symbol imageWithTintColor:UIColor.systemBlueColor renderingMode:UIImageRenderingModeAlwaysOriginal];}}
    UIImageSymbolConfiguration *config=[UIImageSymbolConfiguration configurationWithPointSize:ABMCPanelIconSize() weight:UIImageSymbolWeightMedium];UIImage *symbol=[UIImage systemImageNamed:ABMCPanelSymbol(action) withConfiguration:config];return [symbol imageWithTintColor:UIColor.whiteColor renderingMode:UIImageRenderingModeAlwaysOriginal];
}
- (void)showActions:(NSArray<NSString *> *)actions executor:(ABMCActionExecutor *)executor {
    if(!actions.count)return;dispatch_async(dispatch_get_main_queue(),^{
        [self dismissAnimated:NO completion:^{[self.executor clearHardwareContext];}];self.actions=actions;self.executor=executor;
        self.hostWindow=ABMCPanelKeyWindow();UIWindowScene *scene=self.hostWindow.windowScene;if(!scene){[self.executor clearHardwareContext];return;}UIWindow *window=[[UIWindow alloc]initWithWindowScene:scene];window.frame=scene.coordinateSpace.bounds;/* Keep the overlay below the system status/island compositor. */window.windowLevel=UIWindowLevelStatusBar-1.0;window.opaque=NO;window.backgroundColor=UIColor.clearColor;UIViewController *root=[UIViewController new];root.view.backgroundColor=UIColor.clearColor;window.rootViewController=root;self.window=window;[window makeKeyAndVisible];
        ABMCPanelBackdrop *backdrop=[[ABMCPanelBackdrop alloc]initWithFrame:root.view.bounds];backdrop.owner=self;backdrop.backgroundColor=UIColor.clearColor;backdrop.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;[root.view addSubview:backdrop];
        NSUInteger columns=MIN((NSUInteger)4,actions.count),rows=(actions.count+columns-1)/columns;
        // Native-style compact card: edge-to-edge four-column rhythm, generous
        // white space and no expensive live blur/snapshot work.
        CGFloat outerInset=8.0,padding=16.0,cellH=96.0,iconDiameter=58.0;
        CGFloat width=CGRectGetWidth(root.view.bounds)-outerInset*2,height=padding*2+rows*cellH;
        CGFloat top=MAX(68.0,window.safeAreaInsets.top+12.0);
        UIVisualEffectView *card=[[UIVisualEffectView alloc]initWithEffect:nil];
        card.frame=CGRectMake(outerInset,top,width,height);card.userInteractionEnabled=YES;card.layer.cornerRadius=34.0;card.clipsToBounds=YES;self.darkPanel=ABMCPanelIsDark(self.hostWindow);card.backgroundColor=ABMCPanelBackgroundColor(self.darkPanel);card.layer.borderWidth=1.0/UIScreen.mainScreen.scale;card.layer.borderColor=ABMCPanelTileBorder(self.darkPanel).CGColor;[root.view addSubview:card];backdrop.card=card;self.card=card;self.panelCenter=card.center;
        CGFloat cellW=(width-padding*2)/columns;UIView *content=[[UIView alloc]initWithFrame:card.bounds];content.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;[card.contentView addSubview:content];self.content=content;
        for(NSUInteger i=0;i<actions.count;i++){
            NSUInteger col=i%columns,row=i/columns;NSString *action=actions[i];
            UIView *item=[[UIView alloc]initWithFrame:CGRectMake(padding+col*cellW,padding+row*cellH,cellW,cellH)];
            UIButton *button=[UIButton buttonWithType:UIButtonTypeCustom];button.frame=CGRectMake((cellW-iconDiameter)*.5,0,iconDiameter,iconDiameter);button.layer.cornerRadius=iconDiameter*.5;button.clipsToBounds=YES;button.tag=i;
            BOOL artwork=ABMCPanelUsesArtwork(action);button.backgroundColor=ABMCPanelTileColor(self.darkPanel,artwork);button.layer.borderWidth=artwork?0:1.0/UIScreen.mainScreen.scale;button.layer.borderColor=ABMCPanelTileBorder(self.darkPanel).CGColor;
            CGFloat iconSide=MIN(iconDiameter-12.0,ABMCPanelIconSize()+2.0);UIImageView *iconView=[[UIImageView alloc]initWithImage:ABMCPanelIcon(action)];iconView.frame=CGRectMake((iconDiameter-iconSide)*.5,(iconDiameter-iconSide)*.5,iconSide,iconSide);iconView.contentMode=UIViewContentModeScaleAspectFit;iconView.userInteractionEnabled=NO;if(artwork)iconView.layer.cornerRadius=8;iconView.clipsToBounds=YES;[button addSubview:iconView];[button addTarget:self action:@selector(actionTapped:) forControlEvents:UIControlEventTouchUpInside];[item addSubview:button];
            UILabel *label=[[UILabel alloc]initWithFrame:CGRectMake(0,65,cellW,24)];label.text=ABMCPanelTitle(action);label.textAlignment=NSTextAlignmentCenter;label.font=[UIFont systemFontOfSize:14 weight:UIFontWeightRegular];label.textColor=self.darkPanel?UIColor.whiteColor:UIColor.blackColor;label.numberOfLines=2;label.lineBreakMode=NSLineBreakByWordWrapping;[item addSubview:label];[content addSubview:item];
        }
        UIPanGestureRecognizer *pan=[[UIPanGestureRecognizer alloc]initWithTarget:self action:@selector(panned:)];[card addGestureRecognizer:pan];
        // Animate composited alpha/transform only: no layout calculation occurs per frame.
        card.alpha=0;content.transform=CGAffineTransformMakeScale(.90,.90);[UIView animateWithDuration:.18 delay:0 usingSpringWithDamping:.96 initialSpringVelocity:.35 options:UIViewAnimationOptionCurveEaseOut|UIViewAnimationOptionBeginFromCurrentState animations:^{card.alpha=1;content.transform=CGAffineTransformIdentity;} completion:nil];UIImpactFeedbackGenerator *feedback=[[UIImpactFeedbackGenerator alloc]initWithStyle:UIImpactFeedbackStyleLight];[feedback prepare];[feedback impactOccurred];
    });
}
- (void)backgroundTapped:(id)sender {[self dismissAnimated:YES completion:^{[self.executor clearHardwareContext];}];}
- (void)panned:(UIPanGestureRecognizer *)gesture {CGPoint t=[gesture translationInView:self.card];if(gesture.state==UIGestureRecognizerStateChanged&&t.y<0){self.card.transform=CGAffineTransformMakeTranslation(0,t.y*.35);}if(gesture.state==UIGestureRecognizerStateEnded||gesture.state==UIGestureRecognizerStateCancelled){if(t.y<-54)[self dismissAnimated:YES completion:^{[self.executor clearHardwareContext];}];else [UIView animateWithDuration:.18 animations:^{self.card.transform=CGAffineTransformIdentity;}];}}
- (void)actionTapped:(UIButton *)button {NSString *action=button.tag<self.actions.count?self.actions[button.tag]:nil;[self dismissAnimated:YES completion:^{[self.executor executeAction:action];[self.executor clearHardwareContext];}];}
- (void)dismissAnimated:(BOOL)animated completion:(dispatch_block_t)completion {if(!self.window){if(completion)completion();return;}UIWindow *window=self.window;UIView *card=self.card;void(^done)(BOOL)=^(__unused BOOL finished){UIWindow *host=self.hostWindow;window.hidden=YES;window.rootViewController=nil;self.window=nil;self.card=nil;self.content=nil;self.actions=nil;self.hostWindow=nil;if(host&&!host.hidden)[host makeKeyWindow];if(completion)completion();};if(animated){UIView *content=self.content;[UIView animateWithDuration:.15 delay:0 options:UIViewAnimationOptionCurveEaseIn|UIViewAnimationOptionBeginFromCurrentState animations:^{content.alpha=0;content.transform=CGAffineTransformMakeScale(.90,.90);card.alpha=0;} completion:done];}else done(YES);}
@end
