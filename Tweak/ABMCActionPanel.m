#import "ABMCActionPanel.h"
#import "ABMCActionExecutor.h"
#import <UIKit/UIKit.h>
#import <objc/message.h>

@interface UIImage (ABMCActionPanelIcon)
+ (instancetype)_applicationIconImageForBundleIdentifier:(NSString *)identifier format:(int)format scale:(CGFloat)scale;
@end

@interface ABMCActionPanel ()
@property(nonatomic,strong) UIWindow *window;
@property(nonatomic,weak) UIWindow *previousKeyWindow;
@property(nonatomic,strong) UIView *card;
@property(nonatomic,copy) NSArray<NSString *> *actions;
@property(nonatomic,weak) ABMCActionExecutor *executor;
@end

@implementation ABMCActionPanel
+ (instancetype)sharedPanel { static ABMCActionPanel *p;static dispatch_once_t once;dispatch_once(&once,^{p=[self new];});return p; }

static id ABMCPanelCall(id object, NSString *name) { SEL s=NSSelectorFromString(name);return object&&[object respondsToSelector:s]?((id(*)(id,SEL))objc_msgSend)(object,s):nil; }
static NSString *ABMCPanelAppName(NSString *bundleID) { Class c=NSClassFromString(@"LSApplicationWorkspace");SEL d=NSSelectorFromString(@"defaultWorkspace");id w=c&&[c respondsToSelector:d]?((id(*)(id,SEL))objc_msgSend)(c,d):nil;SEL p=NSSelectorFromString(@"applicationProxyForIdentifier:");id proxy=w&&[w respondsToSelector:p]?((id(*)(id,SEL,id))objc_msgSend)(w,p,bundleID):nil;NSString *name=ABMCPanelCall(proxy,@"localizedName");return name.length?name:bundleID; }
static NSString *ABMCPanelLinkTitle(NSString *identifier) { CFPropertyListRef raw=CFPreferencesCopyAppValue(CFSTR("savedLinks"),PREFS_DOMAIN);NSString *title=nil;for(NSDictionary *link in (raw&&CFGetTypeID(raw)==CFArrayGetTypeID()?(__bridge NSArray *)raw:@[]))if([link[@"id"] isEqualToString:identifier]){title=[link[@"title"] copy];break;}if(raw)CFRelease(raw);return title.length?title:@"链接"; }
static NSString *ABMCPanelTitle(NSString *action) {
    if([action hasPrefix:@"app:"])return ABMCPanelAppName([action substringFromIndex:4]);
    if([action hasPrefix:@"shortcutid:"]){NSArray *p=[[action substringFromIndex:11] componentsSeparatedByString:@"|"];return p.count>1?p[1]:@"快捷指令";}
    if([action hasPrefix:@"link:"])return ABMCPanelLinkTitle([action substringFromIndex:5]);
    NSDictionary *names=@{@"default":@"系统默认",@"flashlight":@"手电筒",@"camera":@"相机",@"silent":@"静音",@"screenshot":@"截屏",@"lock":@"锁屏",@"controlCenter":@"控制中心",@"notificationCenter":@"通知中心",@"settings":@"设置",@"respring":@"重启",@"wechatScan":@"微信扫码",@"wechatPay":@"微信付款码",@"alipayScan":@"支付宝扫码",@"alipayPay":@"支付宝付款码"};return names[action] ?: @"动作";
}
static NSString *ABMCPanelSymbol(NSString *action) {
    NSDictionary *icons=@{@"default":@"gearshape.fill",@"flashlight":@"flashlight.on.fill",@"camera":@"camera.fill",@"silent":@"bell.slash.fill",@"screenshot":@"viewfinder",@"lock":@"lock.fill",@"controlCenter":@"switch.2",@"notificationCenter":@"bell.fill",@"settings":@"gearshape.fill",@"respring":@"arrow.clockwise",@"wechatScan":@"qrcode.viewfinder",@"wechatPay":@"creditcard.fill",@"alipayScan":@"qrcode.viewfinder",@"alipayPay":@"creditcard.fill"};if([action hasPrefix:@"shortcutid:"])return @"square.stack.3d.up.fill";if([action hasPrefix:@"link:"]||[action hasPrefix:@"url:"])return @"link";return icons[action] ?: @"square.grid.2x2.fill";
}
static CGFloat ABMCPanelIconSize(void) { CFPropertyListRef v=CFPreferencesCopyAppValue(CFSTR("unifiedIconSize"),PREFS_DOMAIN);CGFloat size=v&&CFGetTypeID(v)==CFNumberGetTypeID()?[(__bridge NSNumber *)v doubleValue]:30.0;if(v)CFRelease(v);return MIN(48.0,MAX(12.0,size)); }
static UIImage *ABMCPanelIcon(NSString *action) {
    if([action hasPrefix:@"app:"]){NSString *bid=[action substringFromIndex:4];UIImage *image=nil;@try{image=[UIImage _applicationIconImageForBundleIdentifier:bid format:2 scale:UIScreen.mainScreen.scale];}@catch(__unused NSException *e){}if(image)return image;}
    UIImageSymbolConfiguration *config=[UIImageSymbolConfiguration configurationWithPointSize:ABMCPanelIconSize() weight:UIImageSymbolWeightMedium];UIImage *symbol=[UIImage systemImageNamed:ABMCPanelSymbol(action) withConfiguration:config];return [symbol imageWithTintColor:UIColor.systemBlueColor renderingMode:UIImageRenderingModeAlwaysOriginal];
}
- (void)showActions:(NSArray<NSString *> *)actions executor:(ABMCActionExecutor *)executor {
    if(!actions.count)return;dispatch_async(dispatch_get_main_queue(),^{
        [self dismissAnimated:NO completion:^{[self.executor clearHardwareContext];}];self.actions=actions;self.executor=executor;
        self.previousKeyWindow=UIApplication.sharedApplication.keyWindow;UIWindow *window=[[UIWindow alloc]initWithFrame:UIScreen.mainScreen.bounds];window.windowLevel=UIWindowLevelAlert+2;UIViewController *root=[UIViewController new];root.view.backgroundColor=UIColor.clearColor;window.rootViewController=root;self.window=window;[window makeKeyAndVisible];
        UIVisualEffectView *backdrop=[[UIVisualEffectView alloc]initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemChromeMaterialDark]];backdrop.frame=root.view.bounds;backdrop.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;backdrop.alpha=.42;[root.view addSubview:backdrop];
        UIControl *dismiss=[UIControl new];dismiss.frame=root.view.bounds;dismiss.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;[dismiss addTarget:self action:@selector(backgroundTapped:) forControlEvents:UIControlEventTouchUpInside];[root.view addSubview:dismiss];
        NSUInteger columns=MIN((NSUInteger)4,actions.count),rows=(actions.count+columns-1)/columns;CGFloat cellW=76,cellH=98,padding=22,width=MAX(220,columns*cellW+padding*2),height=rows*cellH+padding*2;UIVisualEffectView *card=[[UIVisualEffectView alloc]initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemMaterial]];card.frame=CGRectMake((CGRectGetWidth(root.view.bounds)-width)*.5,(CGRectGetHeight(root.view.bounds)-height)*.5,width,height);card.autoresizingMask=UIViewAutoresizingFlexibleTopMargin|UIViewAutoresizingFlexibleBottomMargin|UIViewAutoresizingFlexibleLeftMargin|UIViewAutoresizingFlexibleRightMargin;card.layer.cornerRadius=28;card.clipsToBounds=YES;[root.view addSubview:card];self.card=card;
        for(NSUInteger i=0;i<actions.count;i++){NSUInteger col=i%columns,row=i/columns;UIView *item=[[UIView alloc]initWithFrame:CGRectMake(padding+col*cellW,padding+row*cellH,cellW,cellH)];UIButton *button=[UIButton buttonWithType:UIButtonTypeCustom];button.frame=CGRectMake((cellW-58)*.5,0,58,58);button.layer.cornerRadius=29;button.clipsToBounds=YES;UIImage *icon=ABMCPanelIcon(actions[i]);[button setImage:icon forState:UIControlStateNormal];button.imageView.contentMode=UIViewContentModeScaleAspectFit;CGFloat iconSide=MIN(48.0,MAX(12.0,ABMCPanelIconSize()))+4.0,iconInset=(58.0-iconSide)*.5;button.imageEdgeInsets=UIEdgeInsetsMake(iconInset,iconInset,iconInset,iconInset);button.backgroundColor=[UIColor.secondarySystemFillColor colorWithAlphaComponent:.72];button.tag=i;[button addTarget:self action:@selector(actionTapped:) forControlEvents:UIControlEventTouchUpInside];[item addSubview:button];UILabel *label=[[UILabel alloc]initWithFrame:CGRectMake(0,64,cellW,32)];label.text=ABMCPanelTitle(actions[i]);label.textAlignment=NSTextAlignmentCenter;label.font=[UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];label.textColor=UIColor.labelColor;label.numberOfLines=2;label.lineBreakMode=NSLineBreakByTruncatingTail;[item addSubview:label];[card.contentView addSubview:item];}
        UIPanGestureRecognizer *pan=[[UIPanGestureRecognizer alloc]initWithTarget:self action:@selector(panned:)];[card addGestureRecognizer:pan];card.transform=CGAffineTransformMakeScale(.72,.72);card.alpha=0;[UIView animateWithDuration:.42 delay:0 usingSpringWithDamping:.78 initialSpringVelocity:.5 options:UIViewAnimationOptionCurveEaseOut animations:^{card.transform=CGAffineTransformIdentity;card.alpha=1;backdrop.alpha=1;} completion:nil];UIImpactFeedbackGenerator *feedback=[[UIImpactFeedbackGenerator alloc]initWithStyle:UIImpactFeedbackStyleLight];[feedback prepare];[feedback impactOccurred];
    });
}
- (void)backgroundTapped:(id)sender {[self dismissAnimated:YES completion:^{[self.executor clearHardwareContext];}];}
- (void)panned:(UIPanGestureRecognizer *)gesture {CGPoint t=[gesture translationInView:self.card];if(gesture.state==UIGestureRecognizerStateChanged&&t.y<0){self.card.transform=CGAffineTransformMakeTranslation(0,t.y*.35);}if(gesture.state==UIGestureRecognizerStateEnded||gesture.state==UIGestureRecognizerStateCancelled){if(t.y<-54)[self dismissAnimated:YES completion:^{[self.executor clearHardwareContext];}];else [UIView animateWithDuration:.18 animations:^{self.card.transform=CGAffineTransformIdentity;}];}}
- (void)actionTapped:(UIButton *)button {NSString *action=button.tag<self.actions.count?self.actions[button.tag]:nil;[self dismissAnimated:YES completion:^{[self.executor executeAction:action];[self.executor clearHardwareContext];}];}
- (void)dismissAnimated:(BOOL)animated completion:(dispatch_block_t)completion {if(!self.window){if(completion)completion();return;}UIWindow *window=self.window;UIView *card=self.card;void(^done)(BOOL)=^(__unused BOOL finished){window.hidden=YES;UIWindow *previous=self.previousKeyWindow;self.window=nil;self.card=nil;self.actions=nil;self.previousKeyWindow=nil;if(previous)[previous makeKeyWindow];if(completion)completion();};if(animated)[UIView animateWithDuration:.18 animations:^{card.transform=CGAffineTransformMakeScale(.78,.78);card.alpha=0;window.rootViewController.view.subviews.firstObject.alpha=0;} completion:done];else done(YES);}
@end
