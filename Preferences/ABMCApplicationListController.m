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

- (instancetype)initWithPreferenceKey:(NSString *)key {
    if ((self = [super initWithStyle:UITableViewStyleInsetGrouped])) { _preferenceKey = [key copy]; self.title = @"应用列表"; }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    _query = @"";
    UIView *header = [[UIView alloc] initWithFrame:CGRectMake(0, 0, UIScreen.mainScreen.bounds.size.width, 72)];
    UISearchBar *search = [[UISearchBar alloc] initWithFrame:CGRectInset(header.bounds, 10, 8)];
    search.placeholder = @"搜索应用"; search.delegate = self; [header addSubview:search]; self.tableView.tableHeaderView = header;
    [self reloadApplications];
}

- (void)reloadApplications {
    NSMutableArray *items = [NSMutableArray array];
    for (id application in ABMCAltListUserApplications()) {
        NSString *bundleID = ABMCBundleIdentifierForApplication(application);
        NSString *name = ABMCDisplayNameForApplication(application);
        if (bundleID.length && name.length) [items addObject:@{ @"id": bundleID, @"name": name }];
    }
    _apps = [items sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) { return [a[@"name"] localizedCaseInsensitiveCompare:b[@"name"]]; }];
    [self.tableView reloadData];
}

- (NSArray *)visibleApps {
    if (!_query.length) return _apps ?: @[];
    NSPredicate *filter = [NSPredicate predicateWithBlock:^BOOL(NSDictionary *item, NSDictionary *bindings) {
        return [item[@"name"] localizedCaseInsensitiveContainsString:self->_query] || [item[@"id"] localizedCaseInsensitiveContainsString:self->_query];
    }];
    return [_apps filteredArrayUsingPredicate:filter];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return self.visibleApps.count; }
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)path {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"AppCell"] ?: [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"AppCell"];
    NSDictionary *item = self.visibleApps[path.row]; NSString *bundleID = item[@"id"];
    cell.imageView.image = ABMCTintedIcon(@"app.fill", UIColor.systemBlueColor);
    cell.textLabel.font = [UIFont systemFontOfSize:17]; cell.detailTextLabel.font = [UIFont systemFontOfSize:13];
    cell.textLabel.text = item[@"name"]; cell.detailTextLabel.text = bundleID;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        UIImage *icon = ABMCIconImageForBundleID(bundleID);
        if (!icon) return;
        dispatch_async(dispatch_get_main_queue(), ^{
            NSIndexPath *current = [tableView indexPathForCell:cell];
            if (current && current.row < self.visibleApps.count && [self.visibleApps[current.row][@"id"] isEqualToString:bundleID]) cell.imageView.image = icon;
        });
    });
    CFStringRef current = (CFStringRef)CFPreferencesCopyAppValue((__bridge CFStringRef)_preferenceKey, ABMCDomain);
    cell.accessoryType = current && [(__bridge NSString *)current isEqualToString:[@"app:" stringByAppendingString:bundleID]] ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
    if (current) CFRelease(current);
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)path {
    NSString *action = [@"app:" stringByAppendingString:self.visibleApps[path.row][@"id"]];
    CFPreferencesSetAppValue((__bridge CFStringRef)_preferenceKey, (__bridge CFPropertyListRef)action, ABMCDomain);
    CFPreferencesAppSynchronize(ABMCDomain);
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), ABMCChanged, NULL, NULL, YES);
    [self.navigationController popViewControllerAnimated:YES];
}
- (void)searchBar:(UISearchBar *)searchBar textDidChange:(NSString *)text { _query = [text copy] ?: @""; [self.tableView reloadData]; }
@end
