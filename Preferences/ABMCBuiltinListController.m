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
- (void)viewDidLoad { [super viewDidLoad]; _query=@""; UIView *header=[[UIView alloc] initWithFrame:CGRectMake(0,0,UIScreen.mainScreen.bounds.size.width,68)]; UISearchBar *search=[[UISearchBar alloc] initWithFrame:CGRectInset(header.bounds,8,6)]; search.placeholder=@"搜索基础动作"; search.delegate=self; [header addSubview:search]; self.tableView.tableHeaderView=header; UIButton *clear=[UIButton buttonWithType:UIButtonTypeSystem];clear.frame=CGRectMake(0,0,72,32);[clear setTitle:@"清空动作" forState:UIControlStateNormal];UITapGestureRecognizer *single=[[UITapGestureRecognizer alloc]initWithTarget:self action:@selector(clearCurrentAction:)];UITapGestureRecognizer *doubleTap=[[UITapGestureRecognizer alloc]initWithTarget:self action:@selector(clearAllBuiltinActions:)];doubleTap.numberOfTapsRequired=2;[single requireGestureRecognizerToFail:doubleTap];[clear addGestureRecognizer:single];[clear addGestureRecognizer:doubleTap];self.navigationItem.rightBarButtonItem=[[UIBarButtonItem alloc]initWithCustomView:clear]; }
- (BOOL)isBuiltin:(NSString *)action { for(NSUInteger i=0;i<sizeof(kActions)/sizeof(kActions[0]);i++) if([action isEqualToString:kActions[i].identifier]) return YES; return NO; }
- (void)clearCurrentAction:(UITapGestureRecognizer *)gesture { ABMCStoreSelectedActions(_preferenceKey,@[]);[self.tableView reloadData]; }
- (void)clearAllBuiltinActions:(UITapGestureRecognizer *)gesture { for(NSString *key in @[@"singleClickAction",@"doubleClickAction",@"longPressAction"]){NSMutableArray *items=[ABMCSelectedActions(key) mutableCopy];[items filterUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSString *a,NSDictionary *b){return ![self isBuiltin:a];}]];ABMCStoreSelectedActions(key,items);}[self.tableView reloadData]; }
- (NSInteger)indexForFilteredRow:(NSInteger)row { NSInteger matched=0; for(NSUInteger i=0;i<sizeof(kActions)/sizeof(kActions[0]);i++){ if(!_query.length || [kActions[i].title localizedCaseInsensitiveContainsString:_query]) { if(matched++==row) return i; } } return NSNotFound; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { NSInteger total=0; for(NSUInteger i=0;i<sizeof(kActions)/sizeof(kActions[0]);i++) if(!_query.length||[kActions[i].title localizedCaseInsensitiveContainsString:_query]) total++; return total; }
- (NSString *)presentationKey:(NSInteger)index { return [@"action." stringByAppendingString:kActions[index].identifier]; }
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath { UITableViewCell *cell=[tableView dequeueReusableCellWithIdentifier:@"BuiltinCell"] ?: [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"BuiltinCell"]; NSInteger index=[self indexForFilteredRow:indexPath.row]; NSString *key=[self presentationKey:index]; NSString *token=ABMCDisplayIconToken(key,kActions[index].icon); ABMCApplyLargeIcon(cell,ABMCTintedIcon(token,nil)?:ABMCIconImageForBundleID(token)?:ABMCTintedIcon(@"hand.tap.fill",nil)); cell.textLabel.font=[UIFont systemFontOfSize:18]; cell.textLabel.text=ABMCDisplayTitle(key,kActions[index].title); cell.accessoryType=[ABMCSelectedActions(_preferenceKey) containsObject:kActions[index].identifier]?UITableViewCellAccessoryCheckmark:UITableViewCellAccessoryNone; ABMCInstallPresentationLongPress(cell,self,key,ABMCDisplayTitle(key,kActions[index].title),token,^{[self.tableView reloadData];}); return cell; }

- (void)showLimit { UIAlertController *a=[UIAlertController alertControllerWithTitle:@"最多 8 项" message:@"每个按键动作最多可选择 8 项。" preferredStyle:UIAlertControllerStyleAlert];[a addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];[self presentViewController:a animated:YES completion:nil]; }

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath { NSInteger index=[self indexForFilteredRow:indexPath.row]; NSString *action=kActions[index].identifier; NSMutableArray *chosen=[ABMCSelectedActions(_preferenceKey) mutableCopy]; if([chosen containsObject:action])[chosen removeObject:action];else if(chosen.count<8)[chosen addObject:action];else{[self showLimit];return;} ABMCStoreSelectedActions(_preferenceKey,chosen);[tableView reloadData]; }

- (void)searchBar:(UISearchBar *)searchBar textDidChange:(NSString *)text { _query=[text copy] ?: @""; [self.tableView reloadData]; }
@end
