#import "ABMCPanelStyleController.h"

#define Domain CFSTR("com.huynguyen.actionbuttonmulticlick")
#define Changed CFSTR("com.huynguyen.actionbuttonmulticlick/prefsChanged")
#define StyleKey CFSTR("panelStyle")

@implementation ABMCPanelStyleController
- (instancetype)init { if((self=[super initWithStyle:UITableViewStyleInsetGrouped]))self.title=@"面板样式";return self; }
- (NSArray<NSString *> *)styles { return @[@"白色面板",@"液态玻璃白",@"液态玻璃黑"]; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return self.styles.count; }
- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section { return @"白色面板使用纯白背景，保证任何外观模式下清晰可读。液态玻璃白/黑使用 iOS 17 可用的毛玻璃、高光描边与阴影制作兼容视觉效果。"; }
- (NSInteger)selectedIndex { CFPropertyListRef v=CFPreferencesCopyAppValue(StyleKey,Domain);NSInteger i=v&&CFGetTypeID(v)==CFNumberGetTypeID()?[(__bridge NSNumber *)v integerValue]:0;if(v)CFRelease(v);return MIN(2,MAX(0,i)); }
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)path { UITableViewCell *cell=[[UITableViewCell alloc]initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];cell.textLabel.text=self.styles[path.row];cell.detailTextLabel.text=path.row==0?@"纯白高对比背景":(path.row==1?@"浅色液态玻璃":@"深色液态玻璃");cell.accessoryType=path.row==self.selectedIndex?UITableViewCellAccessoryCheckmark:UITableViewCellAccessoryNone;return cell; }
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)path { CFPreferencesSetAppValue(StyleKey,(__bridge CFPropertyListRef)@(path.row),Domain);CFPreferencesAppSynchronize(Domain);CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),Changed,NULL,NULL,YES);[tableView reloadData];[tableView deselectRowAtIndexPath:path animated:YES]; }
@end
