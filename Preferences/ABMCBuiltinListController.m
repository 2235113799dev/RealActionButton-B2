#import "ABMCBuiltinListController.h"
#import "ABMCUIHelpers.h"
typedef struct { NSString *identifier; NSString *title; NSString *icon; } ABMCBuiltinAction;
static const ABMCBuiltinAction kActions[]={ {@"default",@"系统默认",@"gearshape.fill"},{@"flashlight",@"手电筒",@"flashlight.on.fill"},{@"camera",@"相机",@"camera.fill"},{@"silent",@"静音切换",@"bell.slash.fill"},{@"screenshot",@"截屏",@"viewfinder"},{@"lock",@"锁屏",@"lock.fill"},{@"controlCenter",@"控制中心",@"switch.2"},{@"notificationCenter",@"通知中心",@"bell.fill"},{@"settings",@"设置",@"gearshape.fill"},{@"respring",@"重启",@"arrow.clockwise"},{@"wechatScan",@"微信扫码",@"qrcode.viewfinder"},{@"wechatPay",@"微信付款码",@"creditcard.fill"},{@"alipayScan",@"支付宝扫码",@"qrcode.viewfinder"},{@"alipayPay",@"支付宝付款码",@"creditcard.fill"},{@"none",@"无操作",@"nosign"} };
@interface ABMCBuiltinListController ()<UISearchBarDelegate>@end
@implementation ABMCBuiltinListController { NSString *_key,*_query; }
- (instancetype)initWithPreferenceKey:(NSString *)key { if((self=[super initWithStyle:UITableViewStyleInsetGrouped])){_key=[key copy];self.title=@"基础动作";}return self; }
- (void)viewDidLoad {[super viewDidLoad];_query=@"";self.tableView.rowHeight=44.0;self.tableView.estimatedRowHeight=44.0;[self refreshHeader];}

- (NSInteger)raw:(NSInteger)row {NSInteger n=0;for(NSUInteger i=0;i<sizeof(kActions)/sizeof(kActions[0]);i++)if(!_query.length||[kActions[i].title localizedCaseInsensitiveContainsString:_query])if(n++==row)return i;return NSNotFound;}
- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section { return ABMCCategoryActionSectionHeader(@"未选动作"); }
- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section { return 24.0; }
- (NSInteger)tableView:(UITableView *)t numberOfRowsInSection:(NSInteger)s{NSInteger n=0;for(NSUInteger i=0;i<sizeof(kActions)/sizeof(kActions[0]);i++)if(!_query.length||[kActions[i].title localizedCaseInsensitiveContainsString:_query])n++;return n;}
- (UITableViewCell *)tableView:(UITableView *)t cellForRowAtIndexPath:(NSIndexPath *)p{NSInteger i=[self raw:p.row];UITableViewCell*c=[t dequeueReusableCellWithIdentifier:@"cell"]?:[[UITableViewCell alloc]initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"cell"];NSString*k=[@"action." stringByAppendingString:kActions[i].identifier],*token=ABMCDisplayIconToken(k,kActions[i].icon);ABMCApplyLargeIcon(c,ABMCTintedIcon(token,nil));c.textLabel.font=[UIFont systemFontOfSize:18];c.textLabel.text=ABMCDisplayTitle(k,kActions[i].title);c.accessoryType=[ABMCSelectedActions(_key)containsObject:kActions[i].identifier]?UITableViewCellAccessoryCheckmark:0;ABMCInstallPresentationLongPress(c,self,k,c.textLabel.text,token,^{[self.tableView reloadData];});return c;}
- (void)refreshHeader { ABMCInstallStickyCategoryActionHeader(self,_key,@"搜索基础动作"); }

- (void)tableView:(UITableView *)t didSelectRowAtIndexPath:(NSIndexPath *)p{NSInteger i=[self raw:p.row];NSString*a=kActions[i].identifier;NSMutableArray*x=[ABMCSelectedActions(_key)mutableCopy];if([x containsObject:a])[x removeObject:a];else if(x.count<8)[x addObject:a];else return;ABMCStoreSelectedActions(_key,x);[self refreshHeader];[t reloadData];}
- (void)viewDidLayoutSubviews { [super viewDidLayoutSubviews]; ABMCUpdateStickyCategoryActionHeader(self); }
- (void)searchBar:(UISearchBar *)s textDidChange:(NSString *)text{_query=[text copy]?:@"";[self.tableView reloadData];}@end
