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
- (CGFloat)size { return ABMCUnifiedIconSize(); }
- (UIColor *)color { return ABMCUnifiedIconColor(); }
- (UITableViewCell *)fieldCell:(NSString *)title field:(UITextField **)field keyboard:(UIKeyboardType)keyboard value:(NSString *)value placeholder:(NSString *)placeholder {
    UITableViewCell *cell=[[UITableViewCell alloc]initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:nil]; cell.textLabel.text=title;
    UITextField *f=[[UITextField alloc]initWithFrame:CGRectMake(0,0,110,38)]; f.textAlignment=NSTextAlignmentRight; f.keyboardType=keyboard; f.text=value; f.placeholder=placeholder; f.delegate=self; f.clearButtonMode=UITextFieldViewModeWhileEditing; cell.accessoryView=f; *field=f; return cell;
}
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return 2; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return section==0?1:2; }
- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section { return section==0?@"图标尺寸":@"图标颜色"; }
- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section { return section==0?@"输入 12–48 pt。开启“统一图标大小”后，此数值作用于所有插件列表的图标画布。":@"可输入 #RRGGBB，也可点右侧颜色块打开 iOS 原生颜色盘（网格、光谱与滑块）。"; }
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)path {
    if(path.section==0) return [self fieldCell:@"图标大小（pt）" field:&_sizeField keyboard:UIKeyboardTypeDecimalPad value:[NSString stringWithFormat:@"%.0f",self.size] placeholder:@"30"];
    if(path.row==0) return [self fieldCell:@"十六进制" field:&_hexField keyboard:UIKeyboardTypeASCIICapable value:ABMCUnifiedIconColorHex() placeholder:@"#007AFF"];
    UITableViewCell *cell=[[UITableViewCell alloc]initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:nil];cell.textLabel.text=@"颜色盘";_well=[[UIColorWell alloc]initWithFrame:CGRectMake(0,0,44,32)];_well.selectedColor=self.color;[_well addTarget:self action:@selector(colorChanged:) forControlEvents:UIControlEventValueChanged];cell.accessoryView=_well;return cell;
}
- (void)colorChanged:(UIColorWell *)well { _hexField.text=[self hexForColor:well.selectedColor]; }
- (NSString *)hexForColor:(UIColor *)color { CGFloat r=0,g=0,b=0,a=0;if(![color getRed:&r green:&g blue:&b alpha:&a])return @"#007AFF";return[NSString stringWithFormat:@"#%02lX%02lX%02lX",lround(r*255),lround(g*255),lround(b*255)]; }
- (UIColor *)colorForHex:(NSString *)text { NSString *s=[[text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] uppercaseString];if([s hasPrefix:@"#"])s=[s substringFromIndex:1];if(s.length!=6)return nil;unsigned n=0;NSScanner *scan=[NSScanner scannerWithString:s];if(![scan scanHexInt:&n]||!scan.isAtEnd)return nil;return[UIColor colorWithRed:((n>>16)&255)/255.0 green:((n>>8)&255)/255.0 blue:(n&255)/255.0 alpha:1]; }
- (void)save { CGFloat size=[[_sizeField.text stringByReplacingOccurrencesOfString:@"pt" withString:@""] doubleValue];if(size<12||size>48){UIAlertController*a=[UIAlertController alertControllerWithTitle:@"尺寸无效" message:@"图标大小需介于 12 到 48 pt。" preferredStyle:UIAlertControllerStyleAlert];[a addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];[self presentViewController:a animated:YES completion:nil];return;}UIColor *color=[self colorForHex:_hexField.text]?:_well.selectedColor;if(!color){UIAlertController*a=[UIAlertController alertControllerWithTitle:@"颜色无效" message:@"请输入 #RRGGBB，或使用颜色盘选择。" preferredStyle:UIAlertControllerStyleAlert];[a addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];[self presentViewController:a animated:YES completion:nil];return;}CFPreferencesSetAppValue(SizeKey,(__bridge CFPropertyListRef)@(size),Domain);CFPreferencesSetAppValue(ColorKey,(__bridge CFPropertyListRef)[self hexForColor:color],Domain);CFPreferencesAppSynchronize(Domain);CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),Changed,NULL,NULL,YES);[self.navigationController popViewControllerAnimated:YES]; }
@end
