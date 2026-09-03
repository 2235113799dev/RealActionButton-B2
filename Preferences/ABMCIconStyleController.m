#import "ABMCIconStyleController.h"
#import "ABMCUIHelpers.h"
#import <math.h>

#define Domain CFSTR("com.huynguyen.actionbuttonmulticlick")
#define Changed CFSTR("com.huynguyen.actionbuttonmulticlick/prefsChanged")
#define SizeKey CFSTR("unifiedIconSize")
#define ColorKey CFSTR("unifiedIconColor")

@interface ABMCIconStyleController () <UITextFieldDelegate>
@end
@implementation ABMCIconStyleController { UITextField *_sizeField,*_hexField; UIColorWell *_well; }
- (instancetype)init { if((self=[super initWithStyle:UITableViewStyleInsetGrouped])) self.title=@"图标样式"; return self; }
- (void)viewDidLoad { [super viewDidLoad]; self.navigationItem.rightBarButtonItem=[[UIBarButtonItem alloc]initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:self action:@selector(save)]; }
- (UITableViewCell *)inputCell:(NSString *)title value:(NSString *)value keyboard:(UIKeyboardType)keyboard tag:(NSInteger)tag placeholder:(NSString *)placeholder {
    UITableViewCell *cell=[[UITableViewCell alloc]initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:nil]; cell.textLabel.text=title;
    UITextField *field=[[UITextField alloc]initWithFrame:CGRectMake(0,0,118,38)]; field.textAlignment=NSTextAlignmentRight; field.keyboardType=keyboard; field.text=value; field.placeholder=placeholder; field.delegate=self; field.clearButtonMode=UITextFieldViewModeWhileEditing; field.tag=tag; cell.accessoryView=field;
    if(tag==1)_sizeField=field; else _hexField=field; return cell;
}
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return 2; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return section==0?1:2; }
- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section { return section==0?@"图标尺寸":@"图标颜色"; }
- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section { return section==0?@"当前数值以 pt 显示。可输入 12–48；开启“统一图标大小”后全局生效。":@"可输入 #RRGGBB，也可点右侧颜色块打开 iOS 原生颜色盘（网格、光谱与滑块）。"; }
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)path {
    if(path.section==0)return [self inputCell:@"图标大小（pt）" value:[NSString stringWithFormat:@"%.0f",ABMCUnifiedIconSize()] keyboard:UIKeyboardTypeDecimalPad tag:1 placeholder:@"30"];
    if(path.row==0)return [self inputCell:@"十六进制" value:ABMCUnifiedIconColorHex() keyboard:UIKeyboardTypeASCIICapable tag:2 placeholder:@"#007AFF"];
    UITableViewCell *cell=[[UITableViewCell alloc]initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:nil];cell.textLabel.text=@"颜色盘";_well=[[UIColorWell alloc]initWithFrame:CGRectMake(0,0,44,32)];_well.selectedColor=ABMCUnifiedIconColor();[_well addTarget:self action:@selector(colorChanged:) forControlEvents:UIControlEventValueChanged];cell.accessoryView=_well;return cell;
}
- (NSString *)hexForColor:(UIColor *)color { CGFloat r=0,g=0,b=0,a=0;if(![color getRed:&r green:&g blue:&b alpha:&a])return @"#007AFF";return[NSString stringWithFormat:@"#%02lX%02lX%02lX",lround(r*255),lround(g*255),lround(b*255)]; }
- (void)colorChanged:(UIColorWell *)well { _hexField.text=[self hexForColor:well.selectedColor]; }
- (UIColor *)colorForHex:(NSString *)text { NSString*s=[[text ?: @"" stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet]uppercaseString];if([s hasPrefix:@"#"])s=[s substringFromIndex:1];unsigned value=0;NSScanner *scan=[NSScanner scannerWithString:s];if(s.length!=6||![scan scanHexInt:&value]||!scan.isAtEnd)return nil;return[UIColor colorWithRed:((value>>16)&255)/255.0 green:((value>>8)&255)/255.0 blue:(value&255)/255.0 alpha:1]; }
- (void)save { CGFloat size=[_sizeField.text doubleValue];if(size<12||size>48){UIAlertController*a=[UIAlertController alertControllerWithTitle:@"尺寸无效" message:@"图标大小需介于 12 到 48 pt。" preferredStyle:UIAlertControllerStyleAlert];[a addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];[self presentViewController:a animated:YES completion:nil];return;}UIColor*color=[self colorForHex:_hexField.text]?:_well.selectedColor;if(!color){UIAlertController*a=[UIAlertController alertControllerWithTitle:@"颜色无效" message:@"请输入 #RRGGBB，或使用颜色盘选择。" preferredStyle:UIAlertControllerStyleAlert];[a addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];[self presentViewController:a animated:YES completion:nil];return;}CFPreferencesSetAppValue(SizeKey,(__bridge CFPropertyListRef)@(size),Domain);CFPreferencesSetAppValue(ColorKey,(__bridge CFPropertyListRef)[self hexForColor:color],Domain);CFPreferencesAppSynchronize(Domain);CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),Changed,NULL,NULL,YES);[self.navigationController popViewControllerAnimated:YES]; }
@end
