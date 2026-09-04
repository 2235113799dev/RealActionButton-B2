#import "ABMCIconStyleController.h"
#import "ABMCUIHelpers.h"
#import <math.h>
#define Domain CFSTR("com.huynguyen.actionbuttonmulticlick")
#define Changed CFSTR("com.huynguyen.actionbuttonmulticlick/prefsChanged")
#define SizeKey CFSTR("unifiedIconSize")
#define ColorKey CFSTR("unifiedIconColor")

@implementation ABMCIconStyleController { ABMCIconStyleMode _mode; UITextField *_field; UIColorWell *_well; }
- (instancetype)initWithMode:(ABMCIconStyleMode)mode { if((self=[super initWithStyle:UITableViewStyleInsetGrouped])){_mode=mode;self.title=mode==ABMCIconStyleModeSize?@"图标尺寸":@"图标颜色";}return self; }
- (instancetype)init { return [self initWithMode:ABMCIconStyleModeSize]; }
- (void)viewDidLoad {[super viewDidLoad];self.navigationItem.rightBarButtonItem=nil;}
- (NSInteger)tableView:(UITableView *)t numberOfRowsInSection:(NSInteger)s{return _mode==ABMCIconStyleModeSize?1:2;}
- (NSString *)tableView:(UITableView *)t titleForFooterInSection:(NSInteger)s{return _mode==ABMCIconStyleModeSize?@"当前大小以 pt 显示。请输入 12–48，保存后全局图标立即使用此尺寸。":@"输入 #RRGGBB，或点颜色块打开 iOS 原生颜色盘（网格、光谱与滑块）。";}
- (UITableViewCell *)tableView:(UITableView *)t cellForRowAtIndexPath:(NSIndexPath *)p {UITableViewCell*c=[[UITableViewCell alloc]initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:nil];if(_mode==ABMCIconStyleModeSize){c.textLabel.text=@"图标大小（pt）";_field=[[UITextField alloc]initWithFrame:CGRectMake(0,0,118,38)];_field.textAlignment=NSTextAlignmentRight;_field.keyboardType=UIKeyboardTypeDecimalPad;_field.text=[NSString stringWithFormat:@"%.0f",ABMCUnifiedIconSize()];_field.placeholder=@"30";_field.clearButtonMode=UITextFieldViewModeWhileEditing;[_field addTarget:self action:@selector(fieldChanged:) forControlEvents:UIControlEventEditingChanged];c.accessoryView=_field;return c;}if(p.row==0){c.textLabel.text=@"十六进制";_field=[[UITextField alloc]initWithFrame:CGRectMake(0,0,118,38)];_field.textAlignment=NSTextAlignmentRight;_field.keyboardType=UIKeyboardTypeASCIICapable;_field.text=ABMCUnifiedIconColorHex();_field.placeholder=@"#007AFF";_field.autocapitalizationType=UITextAutocapitalizationTypeAllCharacters;[_field addTarget:self action:@selector(fieldChanged:) forControlEvents:UIControlEventEditingChanged];c.accessoryView=_field;return c;}c.textLabel.text=@"颜色盘";_well=[[UIColorWell alloc]initWithFrame:CGRectMake(0,0,44,32)];_well.selectedColor=ABMCUnifiedIconColor();[_well addTarget:self action:@selector(colorChanged:) forControlEvents:UIControlEventValueChanged];c.accessoryView=_well;return c;}
- (NSString *)hex:(UIColor *)c {CGFloat r=0,g=0,b=0,a=0;if(![c getRed:&r green:&g blue:&b alpha:&a])return @"#007AFF";return[NSString stringWithFormat:@"#%02lX%02lX%02lX",lround(r*255),lround(g*255),lround(b*255)];}
- (void)colorChanged:(UIColorWell *)well {_field.text=[self hex:well.selectedColor];[self save];}
- (UIColor *)color:(NSString *)s {s=[[[s?:@"" stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet]uppercaseString]stringByReplacingOccurrencesOfString:@"#" withString:@""];unsigned v=0;NSScanner*scan=[NSScanner scannerWithString:s];if(s.length!=6||![scan scanHexInt:&v]||!scan.isAtEnd)return nil;return[UIColor colorWithRed:((v>>16)&255)/255.0 green:((v>>8)&255)/255.0 blue:(v&255)/255.0 alpha:1];}
- (void)fieldChanged:(UITextField *)field { [self save]; }
- (void)viewWillDisappear:(BOOL)animated {[super viewWillDisappear:animated];[self save];}
- (void)save {if(_mode==ABMCIconStyleModeSize){CGFloat size=[_field.text doubleValue];if(size<12||size>48)return;CFPreferencesSetAppValue(SizeKey,(__bridge CFPropertyListRef)@(size),Domain);}else{UIColor*c=[self color:_field.text]?:_well.selectedColor;if(!c)return;CFPreferencesSetAppValue(ColorKey,(__bridge CFPropertyListRef)[self hex:c],Domain);}CFPreferencesAppSynchronize(Domain);CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),Changed,NULL,NULL,YES);}
@end
