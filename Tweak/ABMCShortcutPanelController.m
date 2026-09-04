#import "ABMCShortcutPanelController.h"
#import <objc/message.h>
#import <dlfcn.h>

static NSCache *ABMCPanelIconCache(void) { static NSCache *cache; static dispatch_once_t once; dispatch_once(&once, ^{ cache=[NSCache new]; cache.countLimit=32; }); return cache; }
static UIImage *PanelIcon(NSDictionary *item) {
    NSString *key=[NSString stringWithFormat:@"%@:%@",item[@"glyph"]?:@0,item[@"color"]?:@0]; UIImage *cached=[ABMCPanelIconCache() objectForKey:key]; if(cached)return cached;
    UIImage *saved=[UIImage imageWithData:item[@"iconData"]]; if(saved){[ABMCPanelIconCache() setObject:saved forKey:key];return saved;}
    @try { dlopen("/System/Library/PrivateFrameworks/VoiceShortcutClient.framework/VoiceShortcutClient",RTLD_LAZY|RTLD_LOCAL);Class iconClass=NSClassFromString(@"WFWorkflowIcon"),drawer=NSClassFromString(@"WFWorkflowIconDrawer");SEL make=NSSelectorFromString(@"initWithBackgroundColorValue:glyphCharacter:customImageData:"),draw=NSSelectorFromString(@"imageWithIcon:size:background:"),ui=NSSelectorFromString(@"UIImage");if(![iconClass instancesRespondToSelector:make]||![drawer respondsToSelector:draw])return nil;id icon=((id(*)(id,SEL,long long,unsigned short,id))objc_msgSend)([iconClass alloc],make,[item[@"color"] longLongValue],(unsigned short)[item[@"glyph"] integerValue],nil);id rendered=icon?((id(*)(id,SEL,id,CGSize,BOOL))objc_msgSend)(drawer,draw,icon,CGSizeMake(56,56),YES):nil;UIImage *result=[rendered isKindOfClass:UIImage.class]?rendered:([rendered respondsToSelector:ui]?((id(*)(id,SEL))objc_msgSend)(rendered,ui):nil);if(result)[ABMCPanelIconCache() setObject:result forKey:key];return result;} @catch(NSException *e){return nil;}
}

@implementation ABMCShortcutPanelController { NSArray *_items; void (^_selection)(NSDictionary *); UIView *_card; }
- (instancetype)initWithItems:(NSArray *)items selection:(void (^)(NSDictionary *))selection { if((self=[super init])){_items=[items copy];_selection=[selection copy];self.modalPresentationStyle=UIModalPresentationOverFullScreen;self.modalTransitionStyle=UIModalTransitionStyleCrossDissolve;}return self; }
- (void)viewDidLoad {
    [super viewDidLoad]; self.view.backgroundColor=[[UIColor blackColor]colorWithAlphaComponent:.18];
    UITapGestureRecognizer *tap=[[UITapGestureRecognizer alloc]initWithTarget:self action:@selector(backgroundTap:)];tap.cancelsTouchesInView=NO;[self.view addGestureRecognizer:tap];
    NSUInteger count=MIN(_items.count,(NSUInteger)8),rows=(count+3)/4; CGFloat width=self.view.bounds.size.width-16.0,rowHeight=96.0,height=32.0+rows*rowHeight,top=MAX(16.0,self.view.safeAreaInsets.top+16.0);
    _card=[[UIView alloc]initWithFrame:CGRectMake(8,top,width,height)];_card.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleBottomMargin;_card.backgroundColor=UIColor.systemBackgroundColor;_card.layer.cornerRadius=34;_card.clipsToBounds=YES;[self.view addSubview:_card];
    CGFloat column=width/4.0;
    for(NSUInteger i=0;i<count;i++) { NSDictionary *item=_items[i];UIButton *button=[UIButton buttonWithType:UIButtonTypeCustom];button.frame=CGRectMake(i%4*column,16+i/4*rowHeight,column,rowHeight);button.tag=i;[button addTarget:self action:@selector(select:) forControlEvents:UIControlEventTouchUpInside];
        UIImage *image=PanelIcon(item);UIImageView *icon=[[UIImageView alloc]initWithFrame:CGRectMake((column-56)/2,0,56,56)];icon.image=image?:[UIImage systemImageNamed:@"square.stack.3d.up.fill"];icon.contentMode=UIViewContentModeScaleAspectFit;icon.backgroundColor=image?UIColor.clearColor:UIColor.systemGray5Color;icon.layer.cornerRadius=28;icon.clipsToBounds=YES;[button addSubview:icon];
        UILabel *label=[[UILabel alloc]initWithFrame:CGRectMake(3,63,column-6,23)];label.text=item[@"name"]?:@"快捷指令";label.textColor=UIColor.labelColor;label.font=[UIFont systemFontOfSize:12 weight:UIFontWeightRegular];label.textAlignment=NSTextAlignmentCenter;label.lineBreakMode=NSLineBreakByTruncatingTail;label.adjustsFontSizeToFitWidth=YES;label.minimumScaleFactor=.75;label.userInteractionEnabled=NO;[button addSubview:label];[_card addSubview:button];
    }
}
- (void)select:(UIButton *)sender { NSDictionary *item=_items[sender.tag];void(^block)(NSDictionary*)=_selection;[self dismissViewControllerAnimated:YES completion:^{if(block)block(item);}]; }
- (void)backgroundTap:(UITapGestureRecognizer *)tap { if(!CGRectContainsPoint(_card.frame,[tap locationInView:self.view]))[self dismissViewControllerAnimated:YES completion:nil]; }
@end
