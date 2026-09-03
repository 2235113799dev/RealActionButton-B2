#import "ABMCApplicationListController.h"
#import <objc/message.h>

#define ABMCDomain CFSTR("com.huynguyen.actionbuttonmulticlick")
#define ABMCChanged CFSTR("com.huynguyen.actionbuttonmulticlick/prefsChanged")

@implementation ABMCApplicationListController {
    NSString *_preferenceKey;
    NSArray *_applications;
    NSString *_searchText;
}
- (instancetype)initWithPreferenceKey:(NSString *)key { if ((self=[super initWithStyle:UITableViewStyleInsetGrouped])) { _preferenceKey=[key copy]; self.title=@"应用"; } return self; }
- (void)viewDidLoad { [super viewDidLoad]; _searchText=@""; UISearchBar *bar=[[UISearchBar alloc] initWithFrame:CGRectMake(0,0,UIScreen.mainScreen.bounds.size.width,56)]; bar.placeholder=@"搜索应用"; bar.delegate=(id)self; self.tableView.tableHeaderView=bar; [self loadApplications]; }
- (void)loadApplications {
    NSMutableDictionary *unique=[NSMutableDictionary dictionary];
    @try {
        Class c=NSClassFromString(@"LSApplicationWorkspace"); SEL d=NSSelectorFromString(@"defaultWorkspace"); SEL a=NSSelectorFromString(@"allInstalledApplications");
        id w=(c&&[c respondsToSelector:d])?((id(*)(id,SEL))objc_msgSend)(c,d):nil; NSArray *apps=(w&&[w respondsToSelector:a])?((id(*)(id,SEL))objc_msgSend)(w,a):nil;
        for(id app in apps) {
            NSString *bid=[app respondsToSelector:@selector(bundleIdentifier)]?[app bundleIdentifier]:nil; NSURL *url=[app respondsToSelector:@selector(bundleURL)]?[app bundleURL]:nil;
            NSString *path=url.path; if(!bid.length || ![path.pathExtension.lowercaseString isEqualToString:@"app"]) continue;
            NSString *type=[app respondsToSelector:NSSelectorFromString(@"applicationType")]?((id(*)(id,SEL))objc_msgSend)(app,NSSelectorFromString(@"applicationType")):nil;
            if(type.length && ![type isEqualToString:@"User"] && ![type isEqualToString:@"System"]) continue;
            NSString *name=[app respondsToSelector:@selector(localizedName)]?[app localizedName]:nil; unique[bid]=@{ @"name":name.length?name:bid, @"bundleID":bid };
        }
    } @catch(NSException *e) {}
    _applications=[[unique allValues] sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *x,NSDictionary *y){return [x[@"name"] localizedCaseInsensitiveCompare:y[@"name"]];}]; [self.tableView reloadData];
}
- (NSArray *)filtered { NSMutableArray *r=[NSMutableArray array]; for(NSDictionary *x in _applications) if(!_searchText.length || [x[@"name"] localizedCaseInsensitiveContainsString:_searchText] || [x[@"bundleID"] localizedCaseInsensitiveContainsString:_searchText]) [r addObject:x]; return r; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return self.filtered.count; }
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath { UITableViewCell *cell=[tableView dequeueReusableCellWithIdentifier:@"AppCell"]?:[[UITableViewCell alloc]initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"AppCell"]; NSDictionary *x=self.filtered[indexPath.row]; cell.textLabel.text=x[@"name"]; cell.detailTextLabel.text=x[@"bundleID"]; CFStringRef v=(CFStringRef)CFPreferencesCopyAppValue((__bridge CFStringRef)_preferenceKey,ABMCDomain); cell.accessoryType=v&&[(__bridge NSString*)v isEqualToString:[@"app:" stringByAppendingString:x[@"bundleID"]]]?UITableViewCellAccessoryCheckmark:UITableViewCellAccessoryNone; if(v)CFRelease(v); return cell; }
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath { NSDictionary *x=self.filtered[indexPath.row]; NSString *a=[@"app:" stringByAppendingString:x[@"bundleID"]]; CFPreferencesSetAppValue((__bridge CFStringRef)_preferenceKey,(__bridge CFPropertyListRef)a,ABMCDomain); CFPreferencesAppSynchronize(ABMCDomain); CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),ABMCChanged,NULL,NULL,YES); [self.navigationController popViewControllerAnimated:YES]; }
- (void)searchBar:(UISearchBar *)bar textDidChange:(NSString *)text { _searchText=[text copy]; [self.tableView reloadData]; }
@end
