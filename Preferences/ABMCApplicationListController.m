#import "ABMCApplicationListController.h"
#import "ABMCUIHelpers.h"

#define ABMCDomain CFSTR("com.huynguyen.actionbuttonmulticlick")
#define ABMCChanged CFSTR("com.huynguyen.actionbuttonmulticlick/prefsChanged")

@interface ABMCApplicationListController () <UISearchBarDelegate>
@end

@implementation ABMCApplicationListController {
    NSString *_preferenceKey;
    NSArray *_apps;
    NSString *_query;
}

- (instancetype)initWithPreferenceKey:(NSString *)key { if ((self=[super initWithStyle:UITableViewStyleInsetGrouped])) { _preferenceKey=[key copy]; self.title=@"应用列表"; } return self; }
- (void)viewDidLoad {
    [super viewDidLoad]; _query=@"";
    UIView *header=[[UIView alloc]initWithFrame:CGRectMake(0,0,UIScreen.mainScreen.bounds.size.width,72)];
    UISearchBar *search=[[UISearchBar alloc]initWithFrame:CGRectInset(header.bounds,10,8)]; search.placeholder=@"搜索应用"; search.delegate=self; [header addSubview:search]; self.tableView.tableHeaderView=header;
    [self reloadApplications];
}

- (void)reloadApplications {
    NSArray *identifiers=nil;
    NSDictionary *catalog=ABMCAppListApplications(&identifiers);
    NSMutableArray *apps=[NSMutableArray array];
    for (NSString *bundleID in identifiers) {
        // AppList 的 onlyVisible 已排除扩展/服务；只保留用户或 TrollStore 应用。
        if (![bundleID isKindOfClass:[NSString class]] || [bundleID hasPrefix:@"com.apple."]) continue;
        NSString *name=ABMCAppListDisplayName(bundleID);
        if (!name.length) {
            id details=catalog[bundleID];
            if ([details isKindOfClass:[NSDictionary class]]) name=details[@"displayName"] ?: details[@"name"];
        }
        if (!name.length) name=ABMCApplicationName(bundleID);
        if (name.length) [apps addObject:@{ @"bundleID":bundleID, @"name":name }];
    }
    _apps=[apps sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *a,NSDictionary *b){return[a[@"name"] localizedCaseInsensitiveCompare:b[@"name"]];}];
    [self.tableView reloadData];
}
- (NSArray *)visibleApps { if(!_query.length)return _apps?:@[];NSPredicate*p=[NSPredicate predicateWithBlock:^BOOL(NSDictionary *item,NSDictionary *bindings){return[item[@"name"] localizedCaseInsensitiveContainsString:self->_query]||[item[@"bundleID"] localizedCaseInsensitiveContainsString:self->_query];}];return[_apps filteredArrayUsingPredicate:p]; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section{return self.visibleApps.count;}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)path {
    UITableViewCell *cell=[tableView dequeueReusableCellWithIdentifier:@"AppCell"]?:[[UITableViewCell alloc]initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"AppCell"];
    NSDictionary *item=self.visibleApps[path.row];NSString *bundleID=item[@"bundleID"];
    cell.imageView.image=ABMCTintedIcon(@"app.fill",UIColor.systemBlueColor);
    UIImage *icon=ABMCAppListIcon(bundleID,59); if(icon) cell.imageView.image=icon;
    cell.textLabel.font=[UIFont systemFontOfSize:17];cell.detailTextLabel.font=[UIFont systemFontOfSize:13];cell.textLabel.text=item[@"name"];cell.detailTextLabel.text=bundleID;
    CFStringRef current=(CFStringRef)CFPreferencesCopyAppValue((__bridge CFStringRef)_preferenceKey,ABMCDomain);cell.accessoryType=current&&[(__bridge NSString*)current isEqualToString:[@"app:" stringByAppendingString:bundleID]]?UITableViewCellAccessoryCheckmark:UITableViewCellAccessoryNone;if(current)CFRelease(current);return cell;
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)path { NSDictionary *item=self.visibleApps[path.row];NSString*action=[@"app:"stringByAppendingString:item[@"bundleID"]];CFPreferencesSetAppValue((__bridge CFStringRef)_preferenceKey,(__bridge CFPropertyListRef)action,ABMCDomain);CFPreferencesAppSynchronize(ABMCDomain);CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),ABMCChanged,NULL,NULL,YES);[self.navigationController popViewControllerAnimated:YES]; }
- (void)searchBar:(UISearchBar *)searchBar textDidChange:(NSString *)text {_query=[text copy]?:@"";[self.tableView reloadData];}
@end
