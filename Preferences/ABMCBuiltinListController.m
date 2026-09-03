#import "ABMCBuiltinListController.h"
#import "ABMCUIHelpers.h"

#define ABMCDomain CFSTR("com.huynguyen.actionbuttonmulticlick")
#define ABMCChanged CFSTR("com.huynguyen.actionbuttonmulticlick/prefsChanged")

typedef struct { NSString *identifier; NSString *title; NSString *icon; } ABMCBuiltinAction;
static const ABMCBuiltinAction kActions[] = {
    {@"default", @"系统默认", @"gearshape.fill"}, {@"flashlight", @"手电筒", @"flashlight.on.fill"},
    {@"camera", @"相机", @"camera.fill"}, {@"silent", @"静音切换", @"bell.slash.fill"},
    {@"screenshot", @"截屏", @"viewfinder"}, {@"lock", @"锁屏", @"lock.fill"},
    {@"controlCenter", @"控制中心", @"switch.2"}, {@"notificationCenter", @"通知中心", @"bell.fill"},
    {@"settings", @"打开设置", @"gearshape.fill"}, {@"respring", @"重启界面", @"arrow.clockwise"},
    {@"wechatScan", @"微信扫码", @"qrcode.viewfinder"}, {@"wechatPay", @"微信付款码", @"creditcard.fill"},
    {@"alipayScan", @"支付宝扫码", @"qrcode.viewfinder"}, {@"alipayPay", @"支付宝付款码", @"creditcard.fill"},
    {@"none", @"无操作", @"nosign"}
};

@interface ABMCBuiltinListController () <UISearchBarDelegate>
@end
@implementation ABMCBuiltinListController { NSString *_preferenceKey; NSString *_query; }
- (instancetype)initWithPreferenceKey:(NSString *)key { if ((self=[super initWithStyle:UITableViewStyleInsetGrouped])) { _preferenceKey=[key copy]; self.title=@"基础动作"; } return self; }
- (void)viewDidLoad { [super viewDidLoad]; _query=@""; UIView *header=[[UIView alloc] initWithFrame:CGRectMake(0,0,UIScreen.mainScreen.bounds.size.width,68)]; UISearchBar *search=[[UISearchBar alloc] initWithFrame:CGRectInset(header.bounds,8,6)]; search.placeholder=@"搜索基础动作"; search.delegate=self; [header addSubview:search]; self.tableView.tableHeaderView=header; }
- (NSInteger)indexForFilteredRow:(NSInteger)row { NSInteger matched=0; for(NSUInteger i=0;i<sizeof(kActions)/sizeof(kActions[0]);i++){ if(!_query.length || [kActions[i].title localizedCaseInsensitiveContainsString:_query]) { if(matched++==row) return i; } } return NSNotFound; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { NSInteger total=0; for(NSUInteger i=0;i<sizeof(kActions)/sizeof(kActions[0]);i++) if(!_query.length||[kActions[i].title localizedCaseInsensitiveContainsString:_query]) total++; return total; }
- (NSString *)presentationKey:(NSInteger)index { return [@"action." stringByAppendingString:kActions[index].identifier]; }
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath { UITableViewCell *cell=[tableView dequeueReusableCellWithIdentifier:@"BuiltinCell"] ?: [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"BuiltinCell"]; NSInteger index=[self indexForFilteredRow:indexPath.row]; NSString *key=[self presentationKey:index]; NSString *token=ABMCDisplayIconToken(key,kActions[index].icon); ABMCApplyLargeIcon(cell,ABMCTintedIcon(token,nil)?:ABMCIconImageForBundleID(token)?:ABMCTintedIcon(@"hand.tap.fill",nil)); cell.textLabel.font=[UIFont systemFontOfSize:18]; cell.textLabel.text=ABMCDisplayTitle(key,kActions[index].title); CFStringRef value=(CFStringRef)CFPreferencesCopyAppValue((__bridge CFStringRef)_preferenceKey,ABMCDomain); cell.accessoryType=value&&[(__bridge NSString *)value isEqualToString:kActions[index].identifier]?UITableViewCellAccessoryCheckmark:UITableViewCellAccessoryNone; if(value) CFRelease(value); return cell; }
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath { NSInteger index=[self indexForFilteredRow:indexPath.row]; NSString *action=kActions[index].identifier; CFPreferencesSetAppValue((__bridge CFStringRef)_preferenceKey,(__bridge CFPropertyListRef)action,ABMCDomain); CFPreferencesAppSynchronize(ABMCDomain); CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),ABMCChanged,NULL,NULL,YES); [self.navigationController popViewControllerAnimated:YES]; }
- (UISwipeActionsConfiguration *)tableView:(UITableView *)tableView trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)path { NSInteger index=[self indexForFilteredRow:path.row]; NSString *key=[self presentationKey:index]; UIContextualAction *edit=[UIContextualAction contextualActionWithStyle:UIContextualActionStyleNormal title:@"修改" handler:^(__unused UIContextualAction *a,__unused UIView *v,void(^done)(BOOL)){ABMCShowPresentationEditor(self,key,kActions[index].title,kActions[index].icon,^{[self.tableView reloadData];done(YES);});}];edit.backgroundColor=UIColor.systemBlueColor;UIContextualAction *clear=[UIContextualAction contextualActionWithStyle:UIContextualActionStyleDestructive title:@"清空" handler:^(__unused UIContextualAction *a,__unused UIView *v,void(^done)(BOOL)){ABMCClearPresentationOverride(key);[self.tableView reloadData];done(YES);}];clear.backgroundColor=UIColor.systemGrayColor;return[UISwipeActionsConfiguration configurationWithActions:@[clear,edit]];}
- (void)searchBar:(UISearchBar *)searchBar textDidChange:(NSString *)text { _query=[text copy] ?: @""; [self.tableView reloadData]; }
@end
