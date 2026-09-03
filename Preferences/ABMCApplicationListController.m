#import "ABMCApplicationListController.h"
#import "ABMCUIHelpers.h"
#import <objc/message.h>

#define ABMCDomain CFSTR("com.huynguyen.actionbuttonmulticlick")
#define ABMCChanged CFSTR("com.huynguyen.actionbuttonmulticlick/prefsChanged")

@interface ABMCApplicationListController () <UISearchBarDelegate>
@end

@implementation ABMCApplicationListController {
    NSString *_preferenceKey;
    NSArray *_apps;
    NSString *_query;
}

- (instancetype)initWithPreferenceKey:(NSString *)key {
    if ((self = [super initWithStyle:UITableViewStyleInsetGrouped])) { _preferenceKey = [key copy]; self.title = @"应用列表"; }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    _query = @"";
    UIView *header = [[UIView alloc] initWithFrame:CGRectMake(0, 0, UIScreen.mainScreen.bounds.size.width, 72)];
    UISearchBar *bar = [[UISearchBar alloc] initWithFrame:CGRectInset(header.bounds, 10, 8)];
    bar.placeholder = @"搜索应用"; bar.delegate = self; [header addSubview:bar]; self.tableView.tableHeaderView = header;
    [self reloadApplications];
}

- (void)reloadApplications {
    NSMutableDictionary *unique = [NSMutableDictionary dictionary];
    @try {
        Class workspaceClass = NSClassFromString(@"LSApplicationWorkspace");
        SEL shared = NSSelectorFromString(@"defaultWorkspace"), all = NSSelectorFromString(@"allInstalledApplications");
        id workspace = workspaceClass && [workspaceClass respondsToSelector:shared] ? ((id (*)(id, SEL))objc_msgSend)(workspaceClass, shared) : nil;
        NSArray *proxies = workspace && [workspace respondsToSelector:all] ? ((id (*)(id, SEL))objc_msgSend)(workspace, all) : nil;
        for (id proxy in proxies) {
            if (!ABMCIsAllowedStoreApplicationProxy(proxy)) continue;
            NSString *bundleID = [proxy respondsToSelector:@selector(bundleIdentifier)] ? [proxy bundleIdentifier] : nil;
            NSString *name = [proxy respondsToSelector:@selector(localizedName)] ? [proxy localizedName] : nil;
            if (!bundleID.length) continue;
            UIImage *icon = ABMCIconImageForProxy(proxy);
            unique[bundleID] = @{ @"bundleID": bundleID, @"name": name.length ? name : bundleID, @"icon": icon ?: [NSNull null] };
        }
    } @catch (NSException *exception) {}
    _apps = [[unique allValues] sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) { return [a[@"name"] localizedCaseInsensitiveCompare:b[@"name"]]; }];
    [self.tableView reloadData];
}

- (NSArray *)visibleApps {
    if (!_query.length) return _apps ?: @[];
    NSPredicate *filter = [NSPredicate predicateWithBlock:^BOOL(NSDictionary *item, NSDictionary *bindings) {
        return [item[@"name"] localizedCaseInsensitiveContainsString:self->_query] || [item[@"bundleID"] localizedCaseInsensitiveContainsString:self->_query];
    }];
    return [_apps filteredArrayUsingPredicate:filter];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return self.visibleApps.count; }
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)path {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"AppCell"] ?: [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"AppCell"];
    NSDictionary *item = self.visibleApps[path.row]; id icon = item[@"icon"];
    cell.imageView.image = [icon isKindOfClass:[UIImage class]] ? icon : ABMCTintedIcon(@"app.fill", UIColor.systemBlueColor);
    cell.textLabel.font = [UIFont systemFontOfSize:17]; cell.detailTextLabel.font = [UIFont systemFontOfSize:13];
    cell.textLabel.text = item[@"name"]; cell.detailTextLabel.text = item[@"bundleID"];
    CFStringRef value = (CFStringRef)CFPreferencesCopyAppValue((__bridge CFStringRef)_preferenceKey, ABMCDomain);
    cell.accessoryType = value && [(__bridge NSString *)value isEqualToString:[@"app:" stringByAppendingString:item[@"bundleID"]]] ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
    if (value) CFRelease(value); return cell;
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)path {
    NSDictionary *item = self.visibleApps[path.row]; NSString *action = [@"app:" stringByAppendingString:item[@"bundleID"]];
    CFPreferencesSetAppValue((__bridge CFStringRef)_preferenceKey, (__bridge CFPropertyListRef)action, ABMCDomain); CFPreferencesAppSynchronize(ABMCDomain);
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), ABMCChanged, NULL, NULL, YES); [self.navigationController popViewControllerAnimated:YES];
}
- (void)searchBar:(UISearchBar *)searchBar textDidChange:(NSString *)text { _query = [text copy] ?: @""; [self.tableView reloadData]; }
@end
