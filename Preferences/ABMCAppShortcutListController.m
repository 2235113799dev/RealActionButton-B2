#import "ABMCAppShortcutListController.h"
#import "ABMCUIHelpers.h"
#import <objc/message.h>

#define ABMCDomain CFSTR("com.huynguyen.actionbuttonmulticlick")
#define ABMCChanged CFSTR("com.huynguyen.actionbuttonmulticlick/prefsChanged")

static id ABMCObject(id object, NSString *name) {
    SEL selector = NSSelectorFromString(name);
    return object && [object respondsToSelector:selector] ? ((id (*)(id, SEL))objc_msgSend)(object, selector) : nil;
}

@interface ABMCAppShortcutListController () <UISearchBarDelegate>
@end

@implementation ABMCAppShortcutListController {
    NSString *_preferenceKey;
    NSString *_query;
    NSArray<NSDictionary *> *_groups;
}

- (instancetype)initWithPreferenceKey:(NSString *)key {
    if ((self = [super initWithStyle:UITableViewStyleInsetGrouped])) {
        _preferenceKey = [key copy];
        self.title = @"快捷方式";
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    _query = @"";
    UIView *header = [[UIView alloc] initWithFrame:CGRectMake(0, 0, UIScreen.mainScreen.bounds.size.width, 68)];
    UISearchBar *search = [[UISearchBar alloc] initWithFrame:CGRectInset(header.bounds, 8, 6)];
    search.placeholder = @"搜索快捷方式";
    search.delegate = self;
    [header addSubview:search];
    self.tableView.tableHeaderView = header;
    [self reloadShortcuts];
}

- (void)reloadShortcuts {
    NSMutableArray *groups = [NSMutableArray array];
    for (id application in ABMCInstalledApplications()) {
        NSArray *rawItems = ABMCObject(application, @"staticShortcutItems");
        if (![rawItems isKindOfClass:[NSArray class]] || rawItems.count == 0) continue;
        NSMutableArray *items = [NSMutableArray array];
        for (id rawItem in rawItems) {
            NSString *title = ABMCObject(rawItem, @"localizedTitle") ?: ABMCObject(rawItem, @"title");
            NSString *type = ABMCObject(rawItem, @"type");
            if (title.length && type.length) {
                [items addObject:@{
                    @"title": title,
                    @"subtitle": ABMCObject(rawItem, @"localizedSubtitle") ?: @"",
                    @"type": type
                }];
            }
        }
        NSString *identifier = ABMCBundleIdentifierForApplication(application);
        NSString *name = ABMCDisplayNameForApplication(application);
        if (items.count && identifier.length && name.length) {
            [groups addObject:@{ @"name": name, @"id": identifier, @"items": items }];
        }
    }
    _groups = [groups sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        return [a[@"name"] localizedCaseInsensitiveCompare:b[@"name"]];
    }];
    [self.tableView reloadData];
}

- (NSArray<NSDictionary *> *)visibleGroups {
    if (!_query.length) return _groups ?: @[];
    NSMutableArray *result = [NSMutableArray array];
    for (NSDictionary *group in _groups) {
        NSMutableArray *matched = [NSMutableArray array];
        for (NSDictionary *item in group[@"items"]) {
            BOOL groupMatch = [group[@"name"] localizedCaseInsensitiveContainsString:_query] || [group[@"id"] localizedCaseInsensitiveContainsString:_query];
            BOOL itemMatch = [item[@"title"] localizedCaseInsensitiveContainsString:_query] || [item[@"subtitle"] localizedCaseInsensitiveContainsString:_query];
            if (groupMatch || itemMatch) [matched addObject:item];
        }
        if (matched.count) {
            NSMutableDictionary *copy = [group mutableCopy];
            copy[@"items"] = matched;
            [result addObject:copy];
        }
    }
    return result;
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return self.visibleGroups.count; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return [self.visibleGroups[section][@"items"] count]; }
- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section { return self.visibleGroups[section][@"name"]; }

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"AppShortcutCell"];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"AppShortcutCell"];
    NSDictionary *group = self.visibleGroups[indexPath.section];
    NSDictionary *item = group[@"items"][indexPath.row];
    ABMCApplyLargeIcon(cell, ABMCIconImageForBundleID(group[@"id"]) ?: ABMCTintedIcon(@"app.fill", UIColor.systemBlueColor));
    cell.textLabel.font = [UIFont systemFontOfSize:18.0];
    cell.detailTextLabel.font = [UIFont systemFontOfSize:14.0];
    cell.textLabel.text = item[@"title"];
    cell.detailTextLabel.text = item[@"subtitle"];
    NSString *action = [NSString stringWithFormat:@"appshortcut:%@|%@|%@", group[@"id"], item[@"type"], item[@"title"]];
    CFStringRef current = (CFStringRef)CFPreferencesCopyAppValue((__bridge CFStringRef)_preferenceKey, ABMCDomain);
    cell.accessoryType = current && [(__bridge NSString *)current isEqualToString:action] ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
    if (current) CFRelease(current);
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    NSDictionary *group = self.visibleGroups[indexPath.section];
    NSDictionary *item = group[@"items"][indexPath.row];
    NSString *action = [NSString stringWithFormat:@"appshortcut:%@|%@|%@", group[@"id"], item[@"type"], item[@"title"]];
    CFPreferencesSetAppValue((__bridge CFStringRef)_preferenceKey, (__bridge CFPropertyListRef)action, ABMCDomain);
    CFPreferencesAppSynchronize(ABMCDomain);
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), ABMCChanged, NULL, NULL, YES);
    [self.navigationController popViewControllerAnimated:YES];
}

- (void)searchBar:(UISearchBar *)searchBar textDidChange:(NSString *)text {
    _query = [text copy] ?: @"";
    [self.tableView reloadData];
}
@end
