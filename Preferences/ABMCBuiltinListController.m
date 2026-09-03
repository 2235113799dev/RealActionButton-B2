#import "ABMCBuiltinListController.h"
#import <objc/message.h>

#define ABMCDomain CFSTR("com.huynguyen.actionbuttonmulticlick")
#define ABMCChanged CFSTR("com.huynguyen.actionbuttonmulticlick/prefsChanged")

typedef struct { NSString *identifier; NSString *title; } ABMCBuiltinAction;
static const ABMCBuiltinAction kBuiltinActions[] = {
    {@"default", @"系统默认"}, {@"flashlight", @"手电筒"}, {@"camera", @"相机"}, {@"silent", @"静音切换"},
    {@"screenshot", @"截屏"}, {@"lock", @"锁屏"}, {@"respring", @"重启界面"}, {@"wechatScan", @"微信扫码"},
    {@"wechatPay", @"微信付款码"}, {@"alipayScan", @"支付宝扫码"}, {@"alipayPay", @"支付宝付款码"}, {@"none", @"无操作"}
};

@implementation ABMCBuiltinListController {
    NSString *_preferenceKey;
    NSString *_searchText;
}
- (instancetype)initWithPreferenceKey:(NSString *)key { if ((self = [super initWithStyle:UITableViewStyleInsetGrouped])) { _preferenceKey = [key copy]; self.title = @"内置动作"; } return self; }
- (void)viewDidLoad { [super viewDidLoad]; _searchText = @""; UISearchBar *bar = [[UISearchBar alloc] initWithFrame:CGRectMake(0, 0, UIScreen.mainScreen.bounds.size.width, 56)]; bar.placeholder = @"搜索内置动作"; bar.delegate = (id)self; self.tableView.tableHeaderView = bar; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { NSInteger n = 0; for (NSUInteger i=0; i<sizeof(kBuiltinActions)/sizeof(kBuiltinActions[0]); i++) if (!_searchText.length || [kBuiltinActions[i].title localizedCaseInsensitiveContainsString:_searchText]) n++; return n; }
- (NSInteger)filteredIndex:(NSInteger)row { NSInteger n=0; for (NSUInteger i=0; i<sizeof(kBuiltinActions)/sizeof(kBuiltinActions[0]); i++) if (!_searchText.length || [kBuiltinActions[i].title localizedCaseInsensitiveContainsString:_searchText]) { if (n++ == row) return i; } return NSNotFound; }
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath { UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"BuiltinCell"] ?: [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"BuiltinCell"]; NSInteger i = [self filteredIndex:indexPath.row]; cell.textLabel.text = kBuiltinActions[i].title; CFStringRef v = (CFStringRef)CFPreferencesCopyAppValue((__bridge CFStringRef)_preferenceKey, ABMCDomain); cell.accessoryType = v && [(__bridge NSString *)v isEqualToString:kBuiltinActions[i].identifier] ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone; if (v) CFRelease(v); return cell; }
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath { NSInteger i=[self filteredIndex:indexPath.row]; NSString *a=kBuiltinActions[i].identifier; CFPreferencesSetAppValue((__bridge CFStringRef)_preferenceKey, (__bridge CFPropertyListRef)a, ABMCDomain); CFPreferencesAppSynchronize(ABMCDomain); CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), ABMCChanged, NULL, NULL, YES); [self.navigationController popViewControllerAnimated:YES]; }
- (void)searchBar:(UISearchBar *)searchBar textDidChange:(NSString *)text { _searchText = [text copy]; [self.tableView reloadData]; }
@end
