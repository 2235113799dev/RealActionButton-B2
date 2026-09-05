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
@property(nonatomic,assign) CGPoint islandCenter;
@property(nonatomic,assign) CGPoint cardTargetCenter;
@property(nonatomic,assign) CGSize cardTargetBounds;
@property(nonatomic,assign) NSInteger panelStyle;
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
static NSInteger ABMCPanelStyle(void) { CFPropertyListRef v=CFPreferencesCopyAppValue(CFSTR("panelStyle"),PREFS_DOMAIN);NSInteger style=v&&CFGetTypeID(v)==CFNumberGetTypeID()?[(__bridge NSNumber *)v integerValue]:0;if(v)CFRelease(v);return MIN(2,MAX(0,style)); }
static UIImage *ABMCPanelSnapshot(UIWindow *host, CGRect rect) {
    if(!host||CGRectIsEmpty(rect))return nil;
    // One 1× snapshot per presentation: enough detail for frosted refraction
    // without allocating a full-resolution screen image on the main thread.
    UIGraphicsImageRendererFormat *format=[UIGraphicsImageRendererFormat preferredFormat];format.opaque=YES;format.scale=1.0;
    UIGraphicsImageRenderer *renderer=[[UIGraphicsImageRenderer alloc]initWithSize:rect.size format:format];
    return[renderer imageWithActions:^(UIGraphicsImageRendererContext *context){CGContextTranslateCTM(context.CGContext,-rect.origin.x,-rect.origin.y);[host.layer renderInContext:context.CGContext];}];
}
static void ABMCApplyPanelStyle(UIVisualEffectView *card, NSInteger style, UIWindow *host) {
    card.effect=nil;card.clipsToBounds=YES;card.layer.borderWidth=style==0?0:1.0/UIScreen.mainScreen.scale;
    card.layer.borderColor=(style==2?[UIColor.whiteColor colorWithAlphaComponent:.34]:[UIColor.whiteColor colorWithAlphaComponent:.78]).CGColor;
    card.backgroundColor=style==0?UIColor.whiteColor:UIColor.clearColor;
    if(style==0)return; // Deliberately opaque, high-contrast white panel.
    UIImageView *snapshot=[[UIImageView alloc]initWithImage:ABMCPanelSnapshot(host,card.frame)];snapshot.frame=card.bounds;snapshot.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;snapshot.contentMode=UIViewContentModeScaleToFill;[card.contentView addSubview:snapshot];
    UIBlurEffectStyle material=style==2?UIBlurEffectStyleSystemUltraThinMaterialDark:UIBlurEffectStyleSystemUltraThinMaterialLight;
    UIVisualEffectView *blur=[[UIVisualEffectView alloc]initWithEffect:[UIBlurEffect effectWithStyle:material]];blur.frame=snapshot.bounds;blur.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;[snapshot addSubview:blur];
    UIView *tint=[[UIView alloc]initWithFrame:snapshot.bounds];tint.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;tint.backgroundColor=style==2?[UIColor.blackColor colorWithAlphaComponent:.42]:[UIColor.whiteColor colorWithAlphaComponent:.26];[snapshot addSubview:tint];
    CAGradientLayer *shine=[CAGradientLayer layer];shine.name=@"ABMCPanelShine";shine.frame=card.bounds;shine.colors=@[(id)[UIColor.whiteColor colorWithAlphaComponent:style==2?.24:.52].CGColor,(id)[UIColor.whiteColor colorWithAlphaComponent:style==2?.04:.10].CGColor,(id)UIColor.clearColor.CGColor];shine.locations=@[@0,@.42,@1];shine.startPoint=CGPointMake(0,0);shine.endPoint=CGPointMake(.72,1);shine.cornerRadius=34;[card.contentView.layer addSublayer:shine];
}
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
        [self dismissAnimated:NO completion:^{[self.executor clearHardwareContext];}];self.actions=actions;self.executor=executor;self.panelStyle=ABMCPanelStyle();
        self.hostWindow=ABMCPanelKeyWindow();UIWindowScene *scene=self.hostWindow.windowScene;if(!scene){[self.executor clearHardwareContext];return;}UIWindow *window=[[UIWindow alloc]initWithWindowScene:scene];window.frame=scene.coordinateSpace.bounds;window.windowLevel=UIWindowLevelAlert+2;window.opaque=NO;window.backgroundColor=UIColor.clearColor;window.overrideUserInterfaceStyle=UIUserInterfaceStyleLight;UIViewController *root=[UIViewController new];root.overrideUserInterfaceStyle=UIUserInterfaceStyleLight;root.view.backgroundColor=UIColor.clearColor;window.rootViewController=root;self.window=window;[window makeKeyAndVisible];
        ABMCPanelBackdrop *backdrop=[[ABMCPanelBackdrop alloc]initWithFrame:root.view.bounds];backdrop.owner=self;backdrop.backgroundColor=UIColor.clearColor;backdrop.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;[root.view addSubview:backdrop];
        NSUInteger columns=MIN((NSUInteger)4,actions.count),rows=(actions.count+columns-1)/columns;
        CGFloat cardInset=4.0,padding=20.0,cellH=100.0,iconDiameter=66.0;
        CGFloat width=CGRectGetWidth(root.view.bounds)-cardInset*2,height=rows*cellH+padding*2;
        CGFloat top=MAX(54.0,window.safeAreaInsets.top+14.0);
        UIVisualEffectView *card=[[UIVisualEffectView alloc]initWithEffect:nil];
        card.frame=CGRectMake(cardInset,top,width,height);card.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleBottomMargin;card.layer.cornerRadius=34;ABMCApplyPanelStyle(card,self.panelStyle,self.hostWindow);[root.view addSubview:card];backdrop.card=card;self.card=card;self.cardTargetCenter=card.center;self.cardTargetBounds=card.bounds.size;self.islandCenter=CGPointMake(CGRectGetMidX(root.view.bounds),window.safeAreaInsets.top*.5);
        CGFloat cellW=(width-padding*2)/columns;UIView *content=[[UIView alloc]initWithFrame:card.bounds];content.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;[card.contentView addSubview:content];self.content=content;
        for(NSUInteger i=0;i<actions.count;i++){
            NSUInteger col=i%columns,row=i/columns;NSString *action=actions[i];
            UIView *item=[[UIView alloc]initWithFrame:CGRectMake(padding+col*cellW,padding+row*cellH,cellW,cellH)];
            UIButton *button=[UIButton buttonWithType:UIButtonTypeCustom];button.frame=CGRectMake((cellW-iconDiameter)*.5,0,iconDiameter,iconDiameter);button.layer.cornerRadius=iconDiameter*.5;button.clipsToBounds=YES;button.tag=i;
            BOOL artwork=ABMCPanelUsesArtwork(action);button.backgroundColor=artwork?[UIColor.systemGray5Color colorWithAlphaComponent:.82]:UIColor.systemBlueColor;
            CGFloat iconSide=MIN(iconDiameter-12.0,ABMCPanelIconSize()+4.0);UIImageView *iconView=[[UIImageView alloc]initWithImage:ABMCPanelIcon(action)];iconView.frame=CGRectMake((iconDiameter-iconSide)*.5,(iconDiameter-iconSide)*.5,iconSide,iconSide);iconView.contentMode=UIViewContentModeScaleAspectFit;iconView.userInteractionEnabled=NO;if(artwork)iconView.layer.cornerRadius=8;iconView.clipsToBounds=YES;[button addSubview:iconView];[button addTarget:self action:@selector(actionTapped:) forControlEvents:UIControlEventTouchUpInside];[item addSubview:button];
            UILabel *label=[[UILabel alloc]initWithFrame:CGRectMake(0,67,cellW,27)];label.text=ABMCPanelTitle(action);label.textAlignment=NSTextAlignmentCenter;label.font=[UIFont systemFontOfSize:15 weight:UIFontWeightRegular];label.textColor=self.panelStyle==2?UIColor.whiteColor:UIColor.labelColor;label.numberOfLines=2;label.lineBreakMode=NSLineBreakByWordWrapping;[item addSubview:label];[content addSubview:item];
        }
        UIPanGestureRecognizer *pan=[[UIPanGestureRecognizer alloc]initWithTarget:self action:@selector(panned:)];[card addGestureRecognizer:pan];card.center=self.islandCenter;card.bounds=CGRectMake(0,0,126,37);card.alpha=.98;content.alpha=0;card.layer.cornerRadius=18.5;CGPoint middle=CGPointMake((self.islandCenter.x+self.cardTargetCenter.x)*.5,(self.islandCenter.y+self.cardTargetCenter.y)*.5);[UIView animateWithDuration:.10 delay:0 options:UIViewAnimationOptionCurveEaseOut|UIViewAnimationOptionBeginFromCurrentState animations:^{card.center=middle;card.bounds=CGRectMake(0,0,154,44);card.layer.cornerRadius=22;} completion:^(__unused BOOL finished){[UIView animateWithDuration:.20 delay:0 usingSpringWithDamping:.82 initialSpringVelocity:.70 options:UIViewAnimationOptionCurveEaseOut|UIViewAnimationOptionBeginFromCurrentState animations:^{card.center=self.cardTargetCenter;card.bounds=CGRectMake(0,0,self.cardTargetBounds.width,self.cardTargetBounds.height);card.layer.cornerRadius=34;content.alpha=1;} completion:nil];}];UIImpactFeedbackGenerator *feedback=[[UIImpactFeedbackGenerator alloc]initWithStyle:UIImpactFeedbackStyleLight];[feedback prepare];[feedback impactOccurred];
    });
}
- (void)backgroundTapped:(id)sender {[self dismissAnimated:YES completion:^{[self.executor clearHardwareContext];}];}
- (void)panned:(UIPanGestureRecognizer *)gesture {CGPoint t=[gesture translationInView:self.card];if(gesture.state==UIGestureRecognizerStateChanged&&t.y<0){self.card.transform=CGAffineTransformMakeTranslation(0,t.y*.35);}if(gesture.state==UIGestureRecognizerStateEnded||gesture.state==UIGestureRecognizerStateCancelled){if(t.y<-54)[self dismissAnimated:YES completion:^{[self.executor clearHardwareContext];}];else [UIView animateWithDuration:.18 animations:^{self.card.transform=CGAffineTransformIdentity;}];}}
- (void)actionTapped:(UIButton *)button {NSString *action=button.tag<self.actions.count?self.actions[button.tag]:nil;[self dismissAnimated:YES completion:^{[self.executor executeAction:action];[self.executor clearHardwareContext];}];}
- (void)dismissAnimated:(BOOL)animated completion:(dispatch_block_t)completion {if(!self.window){if(completion)completion();return;}UIWindow *window=self.window;UIView *card=self.card;void(^done)(BOOL)=^(__unused BOOL finished){window.hidden=YES;UIWindow *host=self.hostWindow;self.window=nil;self.card=nil;self.content=nil;self.actions=nil;self.hostWindow=nil;if(host)[host makeKeyWindow];if(completion)completion();};if(animated){UIView *content=self.content;CGPoint middle=CGPointMake((self.islandCenter.x+self.cardTargetCenter.x)*.5,(self.islandCenter.y+self.cardTargetCenter.y)*.5);[UIView animateWithDuration:.08 delay:0 options:UIViewAnimationOptionCurveEaseIn|UIViewAnimationOptionBeginFromCurrentState animations:^{content.alpha=0;} completion:^(__unused BOOL finished){[UIView animateWithDuration:.16 delay:0 options:UIViewAnimationOptionCurveEaseIn|UIViewAnimationOptionBeginFromCurrentState animations:^{card.center=middle;card.bounds=CGRectMake(0,0,154,44);card.layer.cornerRadius=22;} completion:^(__unused BOOL finished2){[UIView animateWithDuration:.09 delay:0 options:UIViewAnimationOptionCurveEaseIn|UIViewAnimationOptionBeginFromCurrentState animations:^{card.center=self.islandCenter;card.bounds=CGRectMake(0,0,126,37);card.layer.cornerRadius=18.5;card.alpha=.98;} completion:done];}];}];}else done(YES);}
@end
