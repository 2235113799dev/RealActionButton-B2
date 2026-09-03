#import "ABMCShortcutListController.h"
#import "ABMCUIHelpers.h"
#import <objc/message.h>
#import <dlfcn.h>
#import <sqlite3.h>
#import <uuid/uuid.h>

#define ABMCDomain CFSTR("com.huynguyen.actionbuttonmulticlick")
#define ABMCChanged CFSTR("com.huynguyen.actionbuttonmulticlick/prefsChanged")

static BOOL ABMCValidWorkflowID(NSString *identifier) {
    if (![identifier isKindOfClass:[NSString class]] || !identifier.length) return NO;
    return [[NSUUID alloc] initWithUUIDString:identifier] != nil;
}

static NSString *ABMCObjectValue(id object, NSArray<NSString *> *names) {
    for (NSString *name in names) {
        SEL selector = NSSelectorFromString(name);
        if (![object respondsToSelector:selector]) continue;
        id value = ((id (*)(id, SEL))objc_msgSend)(object, selector);
        if ([value isKindOfClass:[NSString class]] && [value length]) return value;
    }
    return nil;
}

@interface ABMCShortcutListController () <UISearchBarDelegate>
- (void)loadShortcuts;
- (void)addWorkflow:(id)workflow to:(NSMutableDictionary *)results;
- (void)readWorkflowObject:(id)object into:(NSMutableDictionary *)results;
- (void)readShortcutsDatabaseInto:(NSMutableDictionary *)results;
- (NSArray *)shortcutDatabasePaths;
@end

@implementation ABMCShortcutListController {
    NSString *_preferenceKey;
    NSArray<NSDictionary *> *_shortcuts;
    NSString *_query;
}

- (instancetype)initWithPreferenceKey:(NSString *)key {
    if ((self = [super initWithStyle:UITableViewStyleInsetGrouped])) { _preferenceKey = [key copy]; self.title = @"指令列表"; }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    _query = @"";
    UIView *header = [[UIView alloc] initWithFrame:CGRectMake(0, 0, UIScreen.mainScreen.bounds.size.width, 72.0)];
    UISearchBar *search = [[UISearchBar alloc] initWithFrame:CGRectInset(header.bounds, 10.0, 8.0)];
    search.placeholder = @"搜索全部指令"; search.delegate = self; [header addSubview:search];
    self.tableView.tableHeaderView = header;
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemRefresh target:self action:@selector(loadShortcuts)];
    [self loadShortcuts];
}

- (void)addWorkflow:(id)workflow to:(NSMutableDictionary *)results {
    NSString *name = nil, *identifier = nil;
    if ([workflow isKindOfClass:[NSDictionary class]]) {
        name = workflow[@"name"] ?: workflow[@"title"] ?: workflow[@"displayName"];
        identifier = workflow[@"workflowIdentifier"] ?: workflow[@"identifier"] ?: workflow[@"persistentIdentifier"] ?: workflow[@"uuid"];
    } else {
        name = ABMCObjectValue(workflow, @[@"name", @"localizedName", @"displayName", @"title"]);
        identifier = ABMCObjectValue(workflow, @[@"workflowIdentifier", @"identifier", @"persistentIdentifier", @"recordIdentifier", @"uniqueIdentifier"]);
    }
    if (name.length && ABMCValidWorkflowID(identifier)) results[identifier.uppercaseString] = @{ @"name": name, @"identifier": identifier.uppercaseString };
}

- (void)readWorkflowObject:(id)object into:(NSMutableDictionary *)results {
    for (NSString *method in @[@"sortedVisibleWorkflowsByName", @"allWorkflows", @"allWorkflowsSortedByName", @"visibleWorkflows", @"workflows", @"shortcutsArray", @"shortcuts", @"allShortcuts"]) {
        SEL selector = NSSelectorFromString(method);
        if (![object respondsToSelector:selector]) continue;
        id value = ((id (*)(id, SEL))objc_msgSend)(object, selector);
        if ([value isKindOfClass:[NSArray class]]) for (id workflow in value) [self addWorkflow:workflow to:results];
    }
}

- (void)loadShortcuts {
    NSMutableDictionary *results = [NSMutableDictionary dictionary];
    @try {
        dlopen("/System/Library/PrivateFrameworks/WorkflowKit.framework/WorkflowKit", RTLD_LAZY | RTLD_LOCAL);
        dlopen("/System/Library/PrivateFrameworks/IntentsFoundation.framework/IntentsFoundation", RTLD_LAZY | RTLD_LOCAL);
        for (NSString *className in @[@"WFDatabase", @"WFWorkflowDatabase", @"ICDatabase", @"WFWorkflowStore", @"WFWorkflowManager", @"WFWorkflowController", @"SGShortcutsController", @"SGShortcutsGenerator"]) {
            Class klass = NSClassFromString(className); if (!klass) continue;
            NSMutableArray *targets = [NSMutableArray arrayWithObject:klass];
            for (NSString *shared in @[@"sharedDatabase", @"sharedInstance", @"defaultDatabase", @"sharedStore", @"defaultStore", @"sharedController"]) {
                SEL selector = NSSelectorFromString(shared);
                if ([klass respondsToSelector:selector]) { id target = ((id (*)(id, SEL))objc_msgSend)(klass, selector); if (target) [targets addObject:target]; }
            }
            if ([klass instancesRespondToSelector:NSSelectorFromString(@"sortedVisibleWorkflowsByName")] || [klass instancesRespondToSelector:NSSelectorFromString(@"allWorkflows")]) {
                id target = [[klass alloc] init]; if (target) [targets addObject:target];
            }
            for (id target in targets) [self readWorkflowObject:target into:results];
            if (results.count) break;
        }
    } @catch (NSException *exception) {}
    if (!results.count) [self readShortcutsDatabaseInto:results];
    _shortcuts = [[results allValues] sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) { return [a[@"name"] localizedCaseInsensitiveCompare:b[@"name"]]; }];
    [self.tableView reloadData];
}

- (NSArray *)shortcutDatabasePaths {
    NSMutableArray *paths = [@[
        @"/var/mobile/Library/Shortcuts/Shortcuts.sqlite", @"/private/var/mobile/Library/Shortcuts/Shortcuts.sqlite",
        @"/var/mobile/Library/Shortcuts/Shortcuts.db", @"/private/var/mobile/Library/Shortcuts/Shortcuts.db"
    ] mutableCopy];
    @try {
        Class workspaceClass = NSClassFromString(@"LSApplicationWorkspace");
        SEL shared = NSSelectorFromString(@"defaultWorkspace"), proxyForID = NSSelectorFromString(@"applicationProxyForBundleIdentifier:");
        id workspace = workspaceClass && [workspaceClass respondsToSelector:shared] ? ((id (*)(id, SEL))objc_msgSend)(workspaceClass, shared) : nil;
        id proxy = workspace && [workspace respondsToSelector:proxyForID] ? ((id (*)(id, SEL, id))objc_msgSend)(workspace, proxyForID, @"is.workflow.my.app") : nil;
        for (NSString *selectorName in @[@"dataContainerURL", @"dataContainerURLForSecurityApplicationGroupIdentifier:"]) {
            SEL selector = NSSelectorFromString(selectorName);
            id URL = nil;
            if ([proxy respondsToSelector:selector] && [selectorName isEqualToString:@"dataContainerURL"]) URL = ((id (*)(id, SEL))objc_msgSend)(proxy, selector);
            if ([URL isKindOfClass:[NSURL class]]) {
                NSString *base = [URL path];
                [paths addObject:[base stringByAppendingPathComponent:@"Library/Shortcuts/Shortcuts.sqlite"]];
                [paths addObject:[base stringByAppendingPathComponent:@"Library/Application Support/Shortcuts/Shortcuts.sqlite"]];
            }
        }
    } @catch (NSException *exception) {}
    return [[NSOrderedSet orderedSetWithArray:paths] array];
}

- (void)readShortcutsDatabaseInto:(NSMutableDictionary *)results {
    NSArray *paths = [self shortcutDatabasePaths];
    for (NSString *path in paths) {
        sqlite3 *db = NULL;
        if (sqlite3_open_v2(path.fileSystemRepresentation, &db, SQLITE_OPEN_READONLY, NULL) != SQLITE_OK) { if (db) sqlite3_close(db); continue; }
        sqlite3_stmt *tables = NULL;
        if (sqlite3_prepare_v2(db, "SELECT name FROM sqlite_master WHERE type='table' AND name LIKE '%WORKFLOW%'", -1, &tables, NULL) == SQLITE_OK) {
            while (sqlite3_step(tables) == SQLITE_ROW) {
                const char *tableText = (const char *)sqlite3_column_text(tables, 0); if (!tableText) continue;
                NSString *table = [NSString stringWithUTF8String:tableText];
                NSString *query = [NSString stringWithFormat:@"SELECT * FROM \"%@\"", [table stringByReplacingOccurrencesOfString:@"\"" withString:@"\"\""]];
                sqlite3_stmt *rows = NULL;
                if (sqlite3_prepare_v2(db, query.UTF8String, -1, &rows, NULL) != SQLITE_OK) continue;
                int count = sqlite3_column_count(rows);
                while (sqlite3_step(rows) == SQLITE_ROW) {
                    NSString *name = nil, *identifier = nil;
                    for (int index = 0; index < count; index++) {
                        const char *column = sqlite3_column_name(rows, index);
                        if (!column) continue;
                        NSString *field = [NSString stringWithUTF8String:column].lowercaseString;
                        int type = sqlite3_column_type(rows, index);
                        const unsigned char *text = sqlite3_column_text(rows, index);
                        NSString *value = text ? [NSString stringWithUTF8String:(const char *)text] : nil;
                        if (!name && value.length && ([field containsString:@"name"] || [field containsString:@"title"])) name = value;
                        if (!identifier && ([field containsString:@"identifier"] || [field containsString:@"uuid"])) {
                            if (value.length) identifier = value;
                            else if (type == SQLITE_BLOB && sqlite3_column_bytes(rows, index) == 16) {
                                const unsigned char *bytes = sqlite3_column_blob(rows, index);
                                uuid_t uuid; memcpy(uuid, bytes, 16);
                                identifier = [[NSUUID alloc] initWithUUIDBytes:uuid].UUIDString;
                            }
                        }
                    }
                    if (name.length && ABMCValidWorkflowID(identifier)) results[identifier.uppercaseString] = @{ @"name": name, @"identifier": identifier.uppercaseString };
                }
                sqlite3_finalize(rows);
            }
            sqlite3_finalize(tables);
        }
        sqlite3_close(db);
        if (results.count) break;
    }
}

- (NSArray *)visibleShortcuts {
    if (!_query.length) return _shortcuts ?: @[];
    NSPredicate *filter = [NSPredicate predicateWithBlock:^BOOL(NSDictionary *item, NSDictionary *bindings) { return [item[@"name"] localizedCaseInsensitiveContainsString:self->_query] || [item[@"identifier"] localizedCaseInsensitiveContainsString:self->_query]; }];
    return [_shortcuts filteredArrayUsingPredicate:filter];
}
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return self.visibleShortcuts.count ?: 1; }
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)path {
    NSArray *items = self.visibleShortcuts;
    if (!items.count) { UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"Empty"]; cell.imageView.image = ABMCTintedIcon(@"exclamationmark.circle", UIColor.secondaryLabelColor); cell.textLabel.text = @"未读取到快捷指令"; cell.detailTextLabel.text = @"请点击右上角刷新"; cell.selectionStyle = UITableViewCellSelectionStyleNone; return cell; }
    NSDictionary *item = items[path.row]; UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"ShortcutCell"] ?: [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"ShortcutCell"];
    cell.imageView.image = ABMCTintedIcon(@"square.stack.3d.up.fill", UIColor.systemBlueColor); cell.textLabel.font = [UIFont systemFontOfSize:17]; cell.detailTextLabel.font = [UIFont systemFontOfSize:13]; cell.textLabel.text = item[@"name"]; cell.detailTextLabel.text = item[@"identifier"];
    NSString *action = [NSString stringWithFormat:@"shortcutid:%@|%@", item[@"identifier"], item[@"name"]]; CFStringRef current = (CFStringRef)CFPreferencesCopyAppValue((__bridge CFStringRef)_preferenceKey, ABMCDomain); cell.accessoryType = current && [(__bridge NSString *)current isEqualToString:action] ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone; if (current) CFRelease(current); return cell;
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)path { NSArray *items = self.visibleShortcuts; if (!items.count) return; NSDictionary *item = items[path.row]; NSString *action = [NSString stringWithFormat:@"shortcutid:%@|%@", item[@"identifier"], item[@"name"]]; CFPreferencesSetAppValue((__bridge CFStringRef)_preferenceKey, (__bridge CFPropertyListRef)action, ABMCDomain); CFPreferencesAppSynchronize(ABMCDomain); CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), ABMCChanged, NULL, NULL, YES); [self.navigationController popViewControllerAnimated:YES]; }
- (void)searchBar:(UISearchBar *)searchBar textDidChange:(NSString *)text { _query = [text copy] ?: @""; [self.tableView reloadData]; }
@end
