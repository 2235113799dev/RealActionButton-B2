#import "ABMCApplicationListController.h"
#import "ABMCUIHelpers.h"
#import <objc/message.h>

#define ABMCDomain CFSTR("com.huynguyen.actionbuttonmulticlick")
#define ABMCChanged CFSTR("com.huynguyen.actionbuttonmulticlick/prefsChanged")

@interface ABMCApplicationListController () <UISearchBarDelegate>
- (NSArray *)visibleApplications;
- (void)loadApplications;
@end

@implementation ABMCApplicationListController {
    NSString *_preferenceKey;
    NSArray *_applications;
    NSString *_query;
}

- (instancetype)initWithPreferenceKey:(NSString *)key {
    if ((self = [super initWithStyle:UITableViewStyleInsetGrouped])) {
        _preferenceKey = [key copy];
        self.title = @"应用列表";
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    _query = @"";
    UIView *header = [[UIView alloc] initWithFrame:CGRectMake(0, 0, UIScreen.mainScreen.bounds.size.width, 72.0)];
    UISearchBar *search = [[UISearchBar alloc] initWithFrame:CGRectInset(header.bounds, 10.0, 8.0)];
    search.placeholder = @"搜索商店应用";
    search.delegate = self;
    [header addSubview:search];
    self.tableView.tableHeaderView = header;
    [self loadApplications];
}

- (void)loadApplications {
    NSMutableDictionary *unique = [NSMutableDictionary dictionary];
    @try {
        Class workspaceClass = NSClassFromString(@"LSApplicationWorkspace");
        SEL workspaceSelector = NSSelectorFromString(@"defaultWorkspace");
        SEL applicationsSelector = NSSelectorFromString(@"allInstalledApplications");
        id workspace = workspaceClass && [workspaceClass respondsToSelector:workspaceSelector] ? ((id (*)(id, SEL))objc_msgSend)(workspaceClass, workspaceSelector) : nil;
        NSArray *proxies = workspace && [workspace respondsToSelector:applicationsSelector] ? ((id (*)(id, SEL))objc_msgSend)(workspace, applicationsSelector) : nil;
        for (id proxy in proxies) {
            if (!ABMCIsAllowedStoreApplicationProxy(proxy)) continue;
            NSString *bundleID = [proxy respondsToSelector:@selector(bundleIdentifier)] ? [proxy bundleIdentifier] : nil;
            NSString *name = [proxy respondsToSelector:@selector(localizedName)] ? [proxy localizedName] : nil;
            if (bundleID.length) unique[bundleID] = @{ @"bundleID": bundleID, @"name": name.length ? name : bundleID };
        }
    } @catch (NSException *exception) {}
    _applications = [[unique allValues] sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *left, NSDictionary *right) {
        return [left[@"name"] localizedCaseInsensitiveCompare:right[@"name"]];
    }];
    [self.tableView reloadData];
}

- (NSArray *)visibleApplications {
    if (!_query.length) return _applications ?: @[];
    NSPredicate *filter = [NSPredicate predicateWithBlock:^BOOL(NSDictionary *item, NSDictionary *bindings) {
        return [item[@"name"] localizedCaseInsensitiveContainsString:self->_query] || [item[@"bundleID"] localizedCaseInsensitiveContainsString:self->_query];
    }];
    return [_applications filteredArrayUsingPredicate:filter];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return self.visibleApplications.count; }

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"ABMCAppCell"];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"ABMCAppCell"];
    NSDictionary *item = self.visibleApplications[indexPath.row];
    cell.imageView.image = ABMCTintedIcon(@"app.fill", UIColor.systemBlueColor);
    cell.textLabel.font = [UIFont systemFontOfSize:17.0];
    cell.detailTextLabel.font = [UIFont systemFontOfSize:13.0];
    cell.textLabel.text = item[@"name"];
    cell.detailTextLabel.text = item[@"bundleID"];
    CFStringRef current = (CFStringRef)CFPreferencesCopyAppValue((__bridge CFStringRef)_preferenceKey, ABMCDomain);
    cell.accessoryType = current && [(__bridge NSString *)current isEqualToString:[@"app:" stringByAppendingString:item[@"bundleID"]]] ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
    if (current) CFRelease(current);
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    NSDictionary *item = self.visibleApplications[indexPath.row];
    NSString *action = [@"app:" stringByAppendingString:item[@"bundleID"]];
    CFPreferencesSetAppValue((__bridge CFStringRef)_preferenceKey, (__bridge CFPropertyListRef)action, ABMCDomain);
    CFPreferencesAppSynchronize(ABMCDomain);
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), ABMCChanged, NULL, NULL, YES);
    [self.navigationController popViewControllerAnimated:YES];
}

- (void)searchBar:(UISearchBar *)searchBar textDidChange:(NSString *)searchText { _query = [searchText copy] ?: @""; [self.tableView reloadData]; }
@end
