#import "ABMCShortcutListController.h"
#import "ABMCUIHelpers.h"
#import <sqlite3.h>

#define ABMCDomain CFSTR("com.huynguyen.actionbuttonmulticlick")
#define ABMCChanged CFSTR("com.huynguyen.actionbuttonmulticlick/prefsChanged")

static BOOL ABMCValidShortcutID(NSString *value) {
    return [value isKindOfClass:[NSString class]] && [[NSUUID alloc] initWithUUIDString:value] != nil;
}

@interface ABMCShortcutListController () <UISearchBarDelegate>
@end

@implementation ABMCShortcutListController {
    NSString *_preferenceKey;
    NSArray *_shortcuts;
    NSString *_query;
}

- (instancetype)initWithPreferenceKey:(NSString *)key {
    if ((self = [super initWithStyle:UITableViewStyleInsetGrouped])) {
        _preferenceKey = [key copy];
        self.title = @"指令列表";
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    _query = @"";
    UIView *header = [[UIView alloc] initWithFrame:CGRectMake(0, 0, UIScreen.mainScreen.bounds.size.width, 72)];
    UISearchBar *search = [[UISearchBar alloc] initWithFrame:CGRectInset(header.bounds, 10, 8)];
    search.placeholder = @"搜索全部快捷指令";
    search.delegate = self;
    [header addSubview:search];
    self.tableView.tableHeaderView = header;
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemRefresh target:self action:@selector(reloadShortcuts)];
    [self reloadShortcuts];
}

- (NSArray *)databasePaths {
    return @[
        @"/private/var/mobile/Library/Shortcuts/Shortcuts.sqlite",
        @"/var/mobile/Library/Shortcuts/Shortcuts.sqlite",
        @"/private/var/mobile/Library/Shortcuts/Shortcuts.db",
        @"/var/mobile/Library/Shortcuts/Shortcuts.db"
    ];
}

- (BOOL)columnExists:(sqlite3 *)database name:(NSString *)column {
    sqlite3_stmt *statement = NULL;
    BOOL found = NO;
    if (sqlite3_prepare_v2(database, "PRAGMA table_info(ZSHORTCUT)", -1, &statement, NULL) == SQLITE_OK) {
        while (sqlite3_step(statement) == SQLITE_ROW) {
            const char *raw = (const char *)sqlite3_column_text(statement, 1);
            if (raw && [[[NSString stringWithUTF8String:raw] uppercaseString] isEqualToString:column]) { found = YES; break; }
        }
    }
    if (statement) sqlite3_finalize(statement);
    return found;
}

- (void)readDatabase:(NSString *)path into:(NSMutableDictionary *)results {
    sqlite3 *database = NULL;
    if (sqlite3_open_v2(path.fileSystemRepresentation, &database, SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX, NULL) != SQLITE_OK) {
        if (database) sqlite3_close(database);
        return;
    }
    sqlite3_busy_timeout(database, 1000);
    // 所有快捷指令的权威数据：ZSHORTCUT.ZNAME 与 ZWORKFLOWID。
    // 不查询 ZWORKFLOW、图标或关联表，避免名称/UUID 错配。
    if (![self columnExists:database name:@"ZNAME"] || ![self columnExists:database name:@"ZWORKFLOWID"]) { sqlite3_close(database); return; }
    BOOL hasTombstone = [self columnExists:database name:@"ZTOMBSTONED"];
    BOOL hasHidden = [self columnExists:database name:@"ZHIDDENFROMLIBRARYANDSYNC"];
    NSMutableString *query = [@"SELECT ZNAME,ZWORKFLOWID FROM ZSHORTCUT WHERE ZNAME IS NOT NULL AND length(trim(ZNAME)) > 0 AND ZWORKFLOWID IS NOT NULL AND length(ZWORKFLOWID) > 0 " mutableCopy];
    if (hasTombstone) [query appendString:@"AND COALESCE(ZTOMBSTONED,0) = 0 "];
    if (hasHidden) [query appendString:@"AND COALESCE(ZHIDDENFROMLIBRARYANDSYNC,0) = 0 "];
    sqlite3_stmt *statement = NULL;
    if (sqlite3_prepare_v2(database, query.UTF8String, -1, &statement, NULL) == SQLITE_OK) {
        while (sqlite3_step(statement) == SQLITE_ROW) {
            const char *rawName = (const char *)sqlite3_column_text(statement, 0);
            const char *rawID = (const char *)sqlite3_column_text(statement, 1);
            if (!rawName || !rawID) continue;
            NSString *name = [[NSString stringWithUTF8String:rawName] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
            NSString *identifier = [[NSString stringWithUTF8String:rawID] uppercaseString];
            if (name.length && ABMCValidShortcutID(identifier)) results[identifier] = @{ @"name": name, @"identifier": identifier };
        }
    }
    if (statement) sqlite3_finalize(statement);
    sqlite3_close(database);
}

- (void)reloadShortcuts {
    NSMutableDictionary *results = [NSMutableDictionary dictionary];
    for (NSString *path in self.databasePaths) [self readDatabase:path into:results];
    _shortcuts = [[results allValues] sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        return [a[@"name"] localizedCaseInsensitiveCompare:b[@"name"]];
    }];
    [self.tableView reloadData];
}

- (NSArray *)visibleShortcuts {
    if (!_query.length) return _shortcuts ?: @[];
    NSPredicate *filter = [NSPredicate predicateWithBlock:^BOOL(NSDictionary *item, NSDictionary *bindings) {
        return [item[@"name"] localizedCaseInsensitiveContainsString:self->_query] || [item[@"identifier"] localizedCaseInsensitiveContainsString:self->_query];
    }];
    return [_shortcuts filteredArrayUsingPredicate:filter];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return self.visibleShortcuts.count ?: 1; }
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)path {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"ShortcutCell"] ?: [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"ShortcutCell"];
    NSArray *items = self.visibleShortcuts;
    if (!items.count) {
        cell.imageView.image = ABMCTintedIcon(@"exclamationmark.circle", UIColor.secondaryLabelColor);
        cell.textLabel.text = @"未读取到快捷指令";
        cell.detailTextLabel.text = @"请打开一次快捷指令 App 后刷新";
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        cell.accessoryType = UITableViewCellAccessoryNone;
        return cell;
    }
    NSDictionary *item = items[path.row];
    cell.selectionStyle = UITableViewCellSelectionStyleDefault;
    cell.imageView.image = ABMCTintedIcon(@"square.stack.3d.up.fill", UIColor.systemBlueColor);
    cell.textLabel.font = [UIFont systemFontOfSize:17];
    cell.detailTextLabel.font = [UIFont systemFontOfSize:13];
    cell.textLabel.text = item[@"name"];
    cell.detailTextLabel.text = item[@"identifier"];
    NSString *action = [NSString stringWithFormat:@"shortcutid:%@|%@", item[@"identifier"], item[@"name"]];
    CFStringRef current = (CFStringRef)CFPreferencesCopyAppValue((__bridge CFStringRef)_preferenceKey, ABMCDomain);
    cell.accessoryType = current && [(__bridge NSString *)current isEqualToString:action] ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
    if (current) CFRelease(current);
    return cell;
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)path {
    NSArray *items = self.visibleShortcuts;
    if (!items.count) return;
    NSDictionary *item = items[path.row];
    NSString *action = [NSString stringWithFormat:@"shortcutid:%@|%@", item[@"identifier"], item[@"name"]];
    CFPreferencesSetAppValue((__bridge CFStringRef)_preferenceKey, (__bridge CFPropertyListRef)action, ABMCDomain);
    CFPreferencesAppSynchronize(ABMCDomain);
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), ABMCChanged, NULL, NULL, YES);
    [self.navigationController popViewControllerAnimated:YES];
}
- (void)searchBar:(UISearchBar *)searchBar textDidChange:(NSString *)text { _query = [text copy] ?: @""; [self.tableView reloadData]; }
@end
