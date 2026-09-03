#import "ABMCApplicationListController.h"
#import <objc/message.h>

#define ABMCDomain CFSTR("com.huynguyen.actionbuttonmulticlick")
#define ABMCChanged CFSTR("com.huynguyen.actionbuttonmulticlick/prefsChanged")

@implementation ABMCApplicationListController {
    NSString *_preferenceKey;
    NSArray<NSDictionary *> *_applications;
}

- (instancetype)initWithPreferenceKey:(NSString *)key {
    if ((self = [super initWithStyle:UITableViewStyleInsetGrouped])) {
        _preferenceKey = [key copy];
        self.title = @"选择应用";
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.tableView.rowHeight = 52.0;
    [self loadApplications];
}

- (void)loadApplications {
    NSMutableArray *items = [NSMutableArray array];
    @try {
        Class workspaceClass = NSClassFromString(@"LSApplicationWorkspace");
        SEL defaultSel = NSSelectorFromString(@"defaultWorkspace");
        SEL allSel = NSSelectorFromString(@"allInstalledApplications");
        if (workspaceClass && [workspaceClass respondsToSelector:defaultSel]) {
            id workspace = ((id (*)(id, SEL))objc_msgSend)(workspaceClass, defaultSel);
            if (workspace && [workspace respondsToSelector:allSel]) {
                NSArray *apps = ((id (*)(id, SEL))objc_msgSend)(workspace, allSel);
                for (id app in apps) {
                    NSString *bundleID = [app respondsToSelector:@selector(bundleIdentifier)] ? [app bundleIdentifier] : nil;
                    if (!bundleID.length) continue;
                    NSString *name = [app respondsToSelector:@selector(localizedName)] ? [app localizedName] : nil;
                    [items addObject:@{ @"name": name.length ? name : bundleID, @"bundleID": bundleID }];
                }
            }
        }
    } @catch (NSException *exception) {}
    [items sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) { return [a[@"name"] localizedCaseInsensitiveCompare:b[@"name"]]; }];
    _applications = [items copy];
    [self.tableView reloadData];
}

- (NSString *)selectedAction {
    CFStringRef value = CFPreferencesCopyAppValue((__bridge CFStringRef)_preferenceKey, ABMCDomain);
    NSString *result = value ? [(__bridge NSString *)value copy] : nil;
    if (value) CFRelease(value);
    return result;
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return 1; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return _applications.count; }

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"ABMCAppCell"];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"ABMCAppCell"];
    NSDictionary *item = _applications[indexPath.row];
    cell.textLabel.text = item[@"name"];
    cell.detailTextLabel.text = item[@"bundleID"];
    NSString *action = [@"app:" stringByAppendingString:item[@"bundleID"]];
    cell.accessoryType = [[self selectedAction] isEqualToString:action] ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    NSString *action = [@"app:" stringByAppendingString:_applications[indexPath.row][@"bundleID"]];
    CFPreferencesSetAppValue((__bridge CFStringRef)_preferenceKey, (__bridge CFPropertyListRef)action, ABMCDomain);
    CFPreferencesAppSynchronize(ABMCDomain);
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), ABMCChanged, NULL, NULL, YES);
    [self.navigationController popViewControllerAnimated:YES];
}

@end
