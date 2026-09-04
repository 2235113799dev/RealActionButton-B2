#import "ABMCApplicationListController.h"
#import "ABMCUIHelpers.h"
@interface ABMCApplicationListController ()<UISearchBarDelegate>@end
@implementation ABMCApplicationListController { NSString *_key,*_query;NSArray *_apps; }
- (instancetype)initWithPreferenceKey:(NSString *)key{if((self=[super initWithStyle:UITableViewStyleInsetGrouped])){_key=[key copy];self.title=@"应用列表";}return self;}
- (void)viewDidLoad{[super viewDidLoad];_query=@"";[self refreshHeader];self.navigationItem.rightBarButtonItem=[[UIBarButtonItem alloc]initWithTitle:@"清空" style:UIBarButtonItemStylePlain target:self action:@selector(clearAll)];dispatch_async(dispatch_get_main_queue(), ^{ [self reloadApps]; });}
- (void)clearAll{ABMCStoreSelectedActions(_key,@[]);[self refreshHeader];[self.tableView reloadData];}
- (void)reloadApps {
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY,0), ^{
        @autoreleasepool {
            NSMutableArray *out=[NSMutableArray array];
            NSSet *blocked=[NSSet setWithArray:@[@"AccountAuthenticationDialog",@"AirDrop",@"AirPlayReceiver",@"AskToMessagesHost",@"BacklinkIndicator",@"CarPlaySetup",@"CarPlaySplashScreen",@"CarPlayWallpaper",@"CheckerBoard",@"CheckerBoardRemoteSetup",@"ContactPhotoCarouselRemoteAlert",@"CTCarrierSpaceAuth",@"DemoApp",@"EyeReliefUI",@"ReplayKitAngel",@"ScreenTimeUnlock",@"SleepLockScreen",@"SLYahooAuth",@"SpringBoardEducation",@"TrustMe",@"Web",@"WebContentAnalysisUI",@"WebSheet"]];
            for(id proxy in ABMCInstalledApplications()){NSString *bid=ABMCBundleIdentifierForApplication(proxy),*name=ABMCDisplayNameForApplication(proxy);if(bid.length&&name.length&&![blocked containsObject:name])[out addObject:@{@"id":bid,@"name":name}];}
            NSArray *sorted=[out sortedArrayUsingComparator:^NSComparisonResult(NSDictionary*a,NSDictionary*b){return[a[@"name"] localizedCaseInsensitiveCompare:b[@"name"]];}];
            dispatch_async(dispatch_get_main_queue(), ^{ self->_apps=sorted; [self.tableView reloadData]; });
        }
    });
}
- (NSArray *)visible{return!_query.length?_apps:[_apps filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSDictionary*x,NSDictionary*b){return[x[@"name"] localizedCaseInsensitiveContainsString:_query]||[x[@"id"] localizedCaseInsensitiveContainsString:_query];}]];}
- (NSInteger)tableView:(UITableView *)t numberOfRowsInSection:(NSInteger)s{return self.visible.count;}
- (UITableViewCell *)tableView:(UITableView *)t cellForRowAtIndexPath:(NSIndexPath *)p{NSDictionary*x=self.visible[p.row];UITableViewCell*c=[t dequeueReusableCellWithIdentifier:@"app"]?:[[UITableViewCell alloc]initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"app"];NSString*k=[@"app." stringByAppendingString:x[@"id"]],*token=ABMCDisplayIconToken(k,x[@"id"]);ABMCApplyLargeIcon(c,ABMCTintedIcon(token,nil)?:ABMCIconImageForBundleID(token)?:ABMCIconImageForBundleID(x[@"id"]));c.textLabel.font=[UIFont systemFontOfSize:18];c.textLabel.text=ABMCDisplayTitle(k,x[@"name"]);NSString*a=[@"app:" stringByAppendingString:x[@"id"]];c.accessoryType=[ABMCSelectedActions(_key)containsObject:a]?UITableViewCellAccessoryCheckmark:0;ABMCInstallPresentationLongPress(c,self,k,c.textLabel.text,token,^{[self.tableView reloadData];});return c;}
- (void)refreshHeader{UIView*h=ABMCSelectedActionsBanner(_key,self);CGFloat bannerHeight=h.bounds.size.height;for(UIView*subview in h.subviews){CGRect frame=subview.frame;frame.origin.y+=60;subview.frame=frame;}UISearchBar*search=[[UISearchBar alloc]initWithFrame:CGRectMake(8,0,h.bounds.size.width-16,56)];search.placeholder=@"搜索应用";search.delegate=self;CGRect frame=h.frame;frame.size.height=bannerHeight+60;h.frame=frame;[h addSubview:search];self.tableView.tableHeaderView=h;}

- (void)tableView:(UITableView *)t didSelectRowAtIndexPath:(NSIndexPath *)p{NSString*a=[@"app:" stringByAppendingString:self.visible[p.row][@"id"]];NSMutableArray*x=[ABMCSelectedActions(_key)mutableCopy];if([x containsObject:a])[x removeObject:a];else if(x.count<8)[x addObject:a];else return;ABMCStoreSelectedActions(_key,x);[self refreshHeader];[t reloadData];}
- (void)searchBar:(UISearchBar *)s textDidChange:(NSString *)text{_query=[text copy]?:@"";[self.tableView reloadData];}@end
