#import "ABMCApplicationListController.h"
#import "ABMCUIHelpers.h"
@interface ABMCApplicationListController ()<UISearchBarDelegate>@end
@implementation ABMCApplicationListController { NSString *_key,*_query;NSArray *_apps; }
- (instancetype)initWithPreferenceKey:(NSString *)key{if((self=[super initWithStyle:UITableViewStyleInsetGrouped])){_key=[key copy];self.title=@"应用列表";}return self;}
- (void)viewDidLoad{[super viewDidLoad];_query=@"";self.tableView.rowHeight=44.0;self.tableView.estimatedRowHeight=44.0;_apps=ABMCActionApplicationRecords();self.navigationItem.rightBarButtonItem=[[UIBarButtonItem alloc]initWithTitle:@"清空" style:UIBarButtonItemStylePlain target:self action:@selector(clearSelectedActions)];[self refreshHeader];}

- (void)reloadApps { _apps=ABMCActionApplicationRecords(); [self.tableView reloadData]; }
- (NSArray *)visible{return!_query.length?_apps:[_apps filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSDictionary*x,NSDictionary*b){return[x[@"name"] localizedCaseInsensitiveContainsString:_query]||[x[@"id"] localizedCaseInsensitiveContainsString:_query];}]];}
- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section { return ABMCCategoryActionSectionHeader(@"未选动作"); }
- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section { return 24.0; }
- (NSInteger)tableView:(UITableView *)t numberOfRowsInSection:(NSInteger)s{return self.visible.count;}
- (UITableViewCell *)tableView:(UITableView *)t cellForRowAtIndexPath:(NSIndexPath *)p{NSDictionary*x=self.visible[p.row];UITableViewCell*c=[t dequeueReusableCellWithIdentifier:@"app"]?:[[UITableViewCell alloc]initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"app"];NSString*k=[@"app." stringByAppendingString:x[@"id"]],*token=ABMCDisplayIconToken(k,x[@"id"]);ABMCApplyLargeIcon(c,ABMCTintedIcon(token,nil)?:ABMCIconImageForBundleID(token)?:ABMCIconImageForBundleID(x[@"id"]));c.textLabel.font=[UIFont systemFontOfSize:18];c.textLabel.text=ABMCDisplayTitle(k,x[@"name"]);NSString*a=[@"app:" stringByAppendingString:x[@"id"]];c.accessoryType=[ABMCSelectedActions(_key)containsObject:a]?UITableViewCellAccessoryCheckmark:0;ABMCInstallPresentationLongPress(c,self,k,c.textLabel.text,token,^{[self.tableView reloadData];});return c;}
- (void)clearSelectedActions { ABMCStoreSelectedActions(_key,@[]);[self refreshHeader];[self.tableView reloadData]; }
- (void)refreshHeader { ABMCInstallStickyCategoryActionHeader(self,_key,@"搜索应用"); }

- (void)tableView:(UITableView *)t didSelectRowAtIndexPath:(NSIndexPath *)p{NSString*a=[@"app:" stringByAppendingString:self.visible[p.row][@"id"]];NSMutableArray*x=[ABMCSelectedActions(_key)mutableCopy];if([x containsObject:a])[x removeObject:a];else if(x.count<8)[x addObject:a];else return;ABMCStoreSelectedActions(_key,x);[self refreshHeader];[t reloadData];}
- (void)viewDidLayoutSubviews { [super viewDidLayoutSubviews]; ABMCUpdateStickyCategoryActionHeader(self); }
- (void)searchBar:(UISearchBar *)s textDidChange:(NSString *)text{_query=[text copy]?:@"";[self.tableView reloadData];}@end
