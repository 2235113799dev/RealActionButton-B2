#import "ABMCActionListController.h"
#import <Preferences/PSSpecifier.h>
#import <UIKit/UIKit.h>
#import <objc/message.h>
#import <dlfcn.h>
#import <sqlite3.h>

#define ABMCDomain CFSTR("com.huynguyen.actionbuttonmulticlick")
#define ABMCChanged CFSTR("com.huynguyen.actionbuttonmulticlick/prefsChanged")
#define ABMCLinksKey CFSTR("savedLinks")

typedef struct { NSString *identifier; NSString *title; } ABMCBuiltinAction;
static const ABMCBuiltinAction kBuiltinActions[] = {
    {@"default", @"系统默认"}, {@"flashlight", @"手电筒"}, {@"camera", @"相机"},
    {@"silent", @"静音切换"}, {@"screenshot", @"截屏"}, {@"lock", @"锁屏"},
    {@"respring", @"重启界面"}, {@"wechatScan", @"微信扫码"},
    {@"wechatPay", @"微信付款码"}, {@"alipayScan", @"支付宝扫码"},
    {@"alipayPay", @"支付宝付款码"}, {@"none", @"无操作"}
};

static NSString *ABMCNormalizeLinkURL(NSString *value) {
    NSString *url = [value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (!url.length || url.length > 4096 || [url rangeOfCharacterFromSet:[NSCharacterSet controlCharacterSet]].location != NSNotFound) return nil;
    NSURL *parsed = [NSURL URLWithString:url];
    if (!parsed.scheme.length) {
        if ([url rangeOfString:@"."].location == NSNotFound) return nil;
        url = [@"https://" stringByAppendingString:url];
        parsed = [NSURL URLWithString:url];
    }
    if (!parsed.scheme.length) return nil;
    url = [url stringByReplacingOccurrencesOfString:@" " withString:@"%20"];
    return [NSURL URLWithString:url].scheme.length ? url : nil;
}

@interface ABMCActionListController () <UISearchBarDelegate>
- (NSString *)displayForAction:(NSString *)action;
- (void)loadDataIfNeeded;
- (void)addLink;
@end

@implementation ABMCActionListController {
    NSString *_preferenceKey;
    NSString *_defaultValue;
    NSString *_currentValue;
    NSMutableDictionary *_searches;
    NSArray *_applications;
    NSArray *_shortcuts;
    NSMutableArray *_links;
    BOOL _loaded;
}

- (instancetype)initWithPreferenceKey:(NSString *)key {
    if ((self = [super init])) {
        _preferenceKey = [key copy];
        _searches = [@{ @"builtin": @"", @"app": @"", @"shortcut": @"", @"link": @"" } mutableCopy];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    PSSpecifier *parent = [self specifier];
    if (!_preferenceKey.length) _preferenceKey = [[parent propertyForKey:@"key"] copy];
    _defaultValue = [[parent propertyForKey:@"default"] copy];
    self.title = @"选择动作";
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAdd target:self action:@selector(addLink)];
    [self loadDataIfNeeded];
    [self updateCurrentHeader];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self loadCurrentValue];
    [self loadDataIfNeeded];
    [self reloadSpecifiers];
    [self updateCurrentHeader];
}

- (void)loadCurrentValue {
    if (!_preferenceKey.length) return;
    CFStringRef value = (CFStringRef)CFPreferencesCopyAppValue((__bridge CFStringRef)_preferenceKey, ABMCDomain);
    _currentValue = value ? (__bridge_transfer NSString *)value : (_defaultValue.length ? [_defaultValue copy] : @"none");
}

- (void)updateCurrentHeader {
    if (!_currentValue.length) [self loadCurrentValue];
    NSString *text = [NSString stringWithFormat:@"正在选择的动作：%@", [self displayForAction:_currentValue]];
    UILabel *label = (UILabel *)self.table.tableHeaderView.subviews.firstObject;
    if (![label isKindOfClass:[UILabel class]]) {
        UIView *header = [[UIView alloc] initWithFrame:CGRectMake(0, 0, UIScreen.mainScreen.bounds.size.width, 52.0)];
        header.backgroundColor = [UIColor systemGroupedBackgroundColor];
        label = [[UILabel alloc] initWithFrame:CGRectInset(header.bounds, 16.0, 10.0)];
        label.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        label.font = [UIFont boldSystemFontOfSize:16.0];
        label.textColor = [UIColor labelColor];
        [header addSubview:label];
        self.table.tableHeaderView = header;
    }
    label.text = text;
}

- (void)loadDataIfNeeded {
    if (_loaded) return;
    _loaded = YES;
    [self loadApplications];
    [self loadShortcuts];
    [self loadLinks];
}

- (void)loadApplications {
    NSMutableDictionary *unique = [NSMutableDictionary dictionary];
    @try {
        Class workspaceClass = NSClassFromString(@"LSApplicationWorkspace");
        SEL defaultSel = NSSelectorFromString(@"defaultWorkspace");
        SEL allSel = NSSelectorFromString(@"allInstalledApplications");
        id workspace = (workspaceClass && [workspaceClass respondsToSelector:defaultSel]) ? ((id (*)(id, SEL))objc_msgSend)(workspaceClass, defaultSel) : nil;
        NSArray *apps = (workspace && [workspace respondsToSelector:allSel]) ? ((id (*)(id, SEL))objc_msgSend)(workspace, allSel) : nil;
        for (id app in apps) {
            NSString *bundleID = [app respondsToSelector:@selector(bundleIdentifier)] ? [app bundleIdentifier] : nil;
            NSURL *bundleURL = [app respondsToSelector:@selector(bundleURL)] ? [app bundleURL] : nil;
            NSString *path = bundleURL.path;
            NSString *type = [app respondsToSelector:NSSelectorFromString(@"applicationType")] ? ((id (*)(id, SEL))objc_msgSend)(app, NSSelectorFromString(@"applicationType")) : nil;
            // A real application bundle is the reliable boundary here. It
            // includes App Store, stock, TrollStore and Sileo .app bundles,
            // while excluding daemons, extensions and system services.
            if (!bundleID.length || ![path.pathExtension.lowercaseString isEqualToString:@"app"]) continue;
            if (type.length && ![type isEqualToString:@"User"] && ![type isEqualToString:@"System"]) continue;
            NSString *name = [app respondsToSelector:@selector(localizedName)] ? [app localizedName] : nil;
            if (!name.length) name = bundleID;
            unique[bundleID] = @{ @"name": name, @"bundleID": bundleID };
        }
    } @catch (NSException *exception) {}
    _applications = [[unique allValues] sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        return [a[@"name"] localizedCaseInsensitiveCompare:b[@"name"]];
    }];
}

static NSString *ABMCWorkflowString(id workflow, NSArray *selectors) {
    for (NSString *name in selectors) {
        SEL selector = NSSelectorFromString(name);
        if ([workflow respondsToSelector:selector]) {
            id value = ((id (*)(id, SEL))objc_msgSend)(workflow, selector);
            if ([value isKindOfClass:[NSString class]] && [value length]) return value;
        }
    }
    return nil;
}

- (void)appendWorkflow:(id)workflow to:(NSMutableDictionary *)unique {
    if ([workflow isKindOfClass:[NSDictionary class]]) {
        NSDictionary *item = (NSDictionary *)workflow;
        NSString *name = item[@"name"] ?: item[@"title"] ?: item[@"localizedName"];
        NSString *identifier = item[@"identifier"] ?: item[@"workflowIdentifier"] ?: item[@"persistentIdentifier"] ?: item[@"id"];
        if ([name isKindOfClass:[NSString class]] && [identifier isKindOfClass:[NSString class]] && name.length && identifier.length) unique[identifier] = @{ @"name": name, @"identifier": identifier };
        return;
    }
    NSString *name = ABMCWorkflowString(workflow, @[@"name", @"localizedName", @"displayName", @"title"]);
    NSString *identifier = ABMCWorkflowString(workflow, @[@"identifier", @"workflowIdentifier", @"persistentIdentifier", @"recordIdentifier", @"uniqueIdentifier"]);
    if (name.length && identifier.length) unique[identifier] = @{ @"name": name, @"identifier": identifier };
}

- (void)loadShortcutsFromPrivateFramework:(NSMutableDictionary *)unique {
    NSArray *classes = @[@"SGShortcutsController", @"SGShortcutsGenerator", @"ICDatabase", @"WFWorkflowController", @"WFWorkflowManager", @"WFWorkflowStore", @"WFDatabase", @"WFWorkflowDatabase"];
    NSArray *sharedSelectors = @[@"sharedInstance", @"sharedDatabase", @"sharedStore", @"defaultDatabase", @"defaultStore", @"sharedController"];
    NSArray *workflowSelectors = @[@"shortcutsArray", @"shortcuts", @"sortedVisibleWorkflowsByName", @"allWorkflows", @"allInstalledWorkflows", @"visibleWorkflows", @"workflows", @"sortedWorkflows", @"allWorkflowsSortedByName", @"getAllWorkflows"];
    @try {
        dlopen("/System/Library/PrivateFrameworks/WorkflowKit.framework/WorkflowKit", RTLD_LAZY | RTLD_LOCAL);
        for (NSString *className in classes) {
            Class klass = NSClassFromString(className);
            if (!klass) continue;
            NSMutableArray *targets = [NSMutableArray array];
            for (NSString *selectorName in sharedSelectors) {
                SEL selector = NSSelectorFromString(selectorName);
                if ([klass respondsToSelector:selector]) { id object = ((id (*)(id, SEL))objc_msgSend)(klass, selector); if (object) [targets addObject:object]; }
            }
            if ([klass instancesRespondToSelector:NSSelectorFromString(@"shortcutsArray")] || [klass instancesRespondToSelector:NSSelectorFromString(@"shortcuts")]) {
                id object = [[klass alloc] init]; if (object) [targets addObject:object];
            }
            if ([klass respondsToSelector:NSSelectorFromString(@"shortcutsArray")] || [klass respondsToSelector:NSSelectorFromString(@"shortcuts")]) [targets addObject:klass];
            for (id target in targets) {
                for (NSString *selectorName in @[@"load", @"reload", @"refresh", @"loadShortcuts", @"generateShortcuts", @"generate", @"fetchShortcuts"]) {
                    SEL refreshSelector = NSSelectorFromString(selectorName);
                    if ([target respondsToSelector:refreshSelector]) { @try { ((void (*)(id, SEL))objc_msgSend)(target, refreshSelector); } @catch (NSException *exception) {} }
                }
                for (NSString *methodName in workflowSelectors) {
                    SEL selector = NSSelectorFromString(methodName);
                    if (![target respondsToSelector:selector]) continue;
                    id result = ((id (*)(id, SEL))objc_msgSend)(target, selector);
                    if ([result isKindOfClass:[NSArray class]]) for (id workflow in result) [self appendWorkflow:workflow to:unique];
                    if (unique.count > 0) break;
                }
                if (unique.count > 0) break;
            }
            if (unique.count > 0) break;
        }
    } @catch (NSException *exception) {}
}

static BOOL ABMCColumnLooksLike(NSString *name, NSArray *candidates) {
    NSString *lower = name.lowercaseString;
    for (NSString *candidate in candidates) if ([lower isEqualToString:candidate.lowercaseString] || [lower hasSuffix:candidate.lowercaseString]) return YES;
    return NO;
}

- (void)loadShortcutsFromDatabase:(NSMutableDictionary *)unique {
    NSArray *paths = @[@"/var/mobile/Library/Shortcuts/Shortcuts.sqlite", @"/var/mobile/Library/Shortcuts/Shortcuts.db", @"/private/var/mobile/Library/Shortcuts/Shortcuts.sqlite"];
    for (NSString *path in paths) {
        sqlite3 *database = NULL;
        if (sqlite3_open_v2(path.fileSystemRepresentation, &database, SQLITE_OPEN_READONLY, NULL) != SQLITE_OK) { if (database) sqlite3_close(database); continue; }
        sqlite3_stmt *tables = NULL;
        if (sqlite3_prepare_v2(database, "SELECT name FROM sqlite_master WHERE type='table'", -1, &tables, NULL) == SQLITE_OK) {
            while (sqlite3_step(tables) == SQLITE_ROW) {
                const unsigned char *tableText = sqlite3_column_text(tables, 0);
                if (!tableText) continue;
                NSString *table = [NSString stringWithUTF8String:(const char *)tableText];
                if (!table.length || [table hasPrefix:@"sqlite_"]) continue;
                NSString *pragma = [NSString stringWithFormat:@"PRAGMA table_info(\"%@\")", [table stringByReplacingOccurrencesOfString:@"\"" withString:@"\"\""]];
                sqlite3_stmt *columns = NULL; NSString *nameColumn = nil; NSString *idColumn = nil;
                if (sqlite3_prepare_v2(database, pragma.UTF8String, -1, &columns, NULL) == SQLITE_OK) {
                    while (sqlite3_step(columns) == SQLITE_ROW) {
                        const unsigned char *columnText = sqlite3_column_text(columns, 1);
                        if (!columnText) continue;
                        NSString *column = [NSString stringWithUTF8String:(const char *)columnText];
                        if (!nameColumn && ABMCColumnLooksLike(column, @[@"name", @"title", @"workflowname", @"zname"])) nameColumn = column;
                        if (!idColumn && ABMCColumnLooksLike(column, @[@"identifier"])) idColumn = column;
                    }
                }
                if (columns) sqlite3_finalize(columns);
                if (!nameColumn || !idColumn) continue;
                NSString *query = [NSString stringWithFormat:@"SELECT \"%@\", \"%@\" FROM \"%@\" WHERE \"%@\" IS NOT NULL", nameColumn, idColumn, [table stringByReplacingOccurrencesOfString:@"\"" withString:@"\"\""], nameColumn];
                sqlite3_stmt *rows = NULL;
                if (sqlite3_prepare_v2(database, query.UTF8String, -1, &rows, NULL) == SQLITE_OK) {
                    while (sqlite3_step(rows) == SQLITE_ROW) {
                        const unsigned char *nameText = sqlite3_column_text(rows, 0); const unsigned char *idText = sqlite3_column_text(rows, 1);
                        if (nameText && idText) { NSString *name = [NSString stringWithUTF8String:(const char *)nameText]; NSString *identifier = [NSString stringWithUTF8String:(const char *)idText]; if (name.length && identifier.length) unique[identifier] = @{ @"name": name, @"identifier": identifier }; }
                    }
                }
                if (rows) sqlite3_finalize(rows);
            }
        }
        if (tables) sqlite3_finalize(tables);
        sqlite3_close(database);
        if (unique.count) break;
    }
}

- (void)loadShortcuts {
    NSMutableDictionary *unique = [NSMutableDictionary dictionary];
    [self loadShortcutsFromPrivateFramework:unique];
    if (!unique.count) [self loadShortcutsFromDatabase:unique];
    _shortcuts = [[unique allValues] sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) { return [a[@"name"] localizedCaseInsensitiveCompare:b[@"name"]]; }];
}

- (void)loadLinks {
    _links = [NSMutableArray array];
    CFPropertyListRef value = CFPreferencesCopyAppValue(ABMCLinksKey, ABMCDomain);
    if (value && CFGetTypeID(value) == CFArrayGetTypeID()) {
        for (id item in (__bridge NSArray *)value) {
            if ([item isKindOfClass:[NSDictionary class]] && [item[@"id"] isKindOfClass:[NSString class]] && [item[@"title"] isKindOfClass:[NSString class]] && [item[@"url"] isKindOfClass:[NSString class]]) [_links addObject:[item mutableCopy]];
        }
    }
    if (value) CFRelease(value);
}

- (BOOL)matches:(NSString *)value group:(NSString *)group {
    NSString *search = _searches[group];
    return !search.length || [value localizedCaseInsensitiveContainsString:search];
}

- (NSString *)selectedLinkTitle:(NSString *)linkID {
    for (NSDictionary *link in _links) if ([link[@"id"] isEqualToString:linkID]) return link[@"title"];
    return nil;
}

- (NSString *)displayForAction:(NSString *)action {
    if (!action.length || [action isEqualToString:@"none"]) return @"无操作";
    for (NSUInteger i = 0; i < sizeof(kBuiltinActions) / sizeof(kBuiltinActions[0]); i++) if ([action isEqualToString:kBuiltinActions[i].identifier]) return [NSString stringWithFormat:@"内置：%@", kBuiltinActions[i].title];
    if ([action hasPrefix:@"app:"]) {
        NSString *bid = [action substringFromIndex:4];
        for (NSDictionary *app in _applications) if ([app[@"bundleID"] isEqualToString:bid]) return [NSString stringWithFormat:@"应用：%@", app[@"name"]];
        return [NSString stringWithFormat:@"应用：%@", bid];
    }
    if ([action hasPrefix:@"shortcutid:"]) { NSArray *parts = [[action substringFromIndex:11] componentsSeparatedByString:@"|"]; return [NSString stringWithFormat:@"指令：%@", parts.count > 1 ? parts[1] : parts.firstObject]; }
    if ([action hasPrefix:@"shortcut:"]) return [NSString stringWithFormat:@"指令：%@", [action substringFromIndex:9]];
    if ([action hasPrefix:@"link:"]) return [NSString stringWithFormat:@"链接：%@", [self selectedLinkTitle:[action substringFromIndex:5]] ?: @"未找到"];
    if ([action hasPrefix:@"url:"]) return [NSString stringWithFormat:@"链接：%@", [action substringFromIndex:4]];
    return action;
}

- (PSSpecifier *)placeholderSpecifier:(NSString *)text {
    PSSpecifier *spec = [PSSpecifier preferenceSpecifierNamed:text target:self set:NULL get:NULL detail:Nil cell:PSStaticTextCell edit:Nil];
    [spec setProperty:@YES forKey:@"placeholder"];
    return spec;
}

- (void)saveLinks {
    CFPreferencesSetAppValue(ABMCLinksKey, (__bridge CFPropertyListRef)_links, ABMCDomain);
    CFPreferencesAppSynchronize(ABMCDomain);
}

- (void)editLink:(NSDictionary *)existing {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:existing ? @"编辑链接" : @"新增链接" message:@"支持网页、域名和自定义 URL Scheme" preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *field) { field.placeholder = @"标题"; field.text = existing[@"title"]; }];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *field) { field.placeholder = @"https://example.com 或 URL Scheme"; field.text = existing[@"url"]; field.autocapitalizationType = UITextAutocapitalizationTypeNone; field.autocorrectionType = UITextAutocorrectionTypeNo; }];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"保存" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        NSString *title = [alert.textFields[0].text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        NSString *url = ABMCNormalizeLinkURL(alert.textFields[1].text);
        if (!title.length || title.length > 100 || !url.length) return;
        NSMutableDictionary *item = [NSMutableDictionary dictionaryWithDictionary:existing ?: @{}];
        if (![item[@"id"] isKindOfClass:[NSString class]]) item[@"id"] = [NSUUID UUID].UUIDString;
        item[@"title"] = title; item[@"url"] = url;
        NSUInteger index = existing ? [self->_links indexOfObject:existing] : NSNotFound;
        if (index == NSNotFound) [self->_links addObject:item]; else self->_links[index] = item;
        [self saveLinks]; self->_specifiers = nil; [self reloadSpecifiers]; [self updateCurrentHeader];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)addLink { [self editLink:nil]; }

- (NSInteger)linkIndexForSpecifier:(PSSpecifier *)specifier {
    NSString *linkID = [specifier propertyForKey:@"linkID"];
    for (NSUInteger i = 0; i < _links.count; i++) if ([_links[i][@"id"] isEqualToString:linkID]) return (NSInteger)i;
    return NSNotFound;
}

- (UISwipeActionsConfiguration *)tableView:(UITableView *)tableView trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath {
    PSSpecifier *specifier = [self specifierAtIndexPath:indexPath];
    NSString *linkID = [specifier propertyForKey:@"linkID"];
    if (!linkID.length) return nil;
    NSInteger linkIndex = [self linkIndexForSpecifier:specifier];
    if (linkIndex == NSNotFound) return nil;
    UIContextualAction *edit = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleNormal title:@"编辑" handler:^(UIContextualAction *action, __kindof UIView *sourceView, void (^completionHandler)(BOOL)) {
        [self editLink:self->_links[linkIndex]]; completionHandler(YES);
    }];
    edit.backgroundColor = [UIColor systemBlueColor];
    UIContextualAction *remove = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleDestructive title:@"删除" handler:^(UIContextualAction *action, __kindof UIView *sourceView, void (^completionHandler)(BOOL)) {
        NSString *selected = self->_currentValue;
        if ([selected isEqualToString:[@"link:" stringByAppendingString:linkID]]) [self saveAction:@"none"];
        [self->_links removeObjectAtIndex:linkIndex]; [self saveLinks]; self->_specifiers = nil; [self reloadSpecifiers]; completionHandler(YES);
    }];
    return [UISwipeActionsConfiguration configurationWithActions:@[remove, edit]];
}

- (NSArray *)specifiers {
    if (!_searches) _searches = [@{ @"builtin": @"", @"app": @"", @"shortcut": @"", @"link": @"" }.mutableCopy];
    [self loadDataIfNeeded];
    if (!_currentValue.length) [self loadCurrentValue];
    NSMutableArray *result = [NSMutableArray array];
    [result addObject:[PSSpecifier groupSpecifierWithName:@"内置动作"]];
    [result addObject:[self searchSpecifier:@"builtin"]];
    NSUInteger count = sizeof(kBuiltinActions) / sizeof(kBuiltinActions[0]); BOOL found = NO;
    for (NSUInteger i = 0; i < count; i++) if ([self matches:kBuiltinActions[i].title group:@"builtin"]) {
        found = YES; PSSpecifier *item = [PSSpecifier preferenceSpecifierNamed:kBuiltinActions[i].title target:self set:NULL get:NULL detail:Nil cell:PSStaticTextCell edit:Nil]; [item setProperty:kBuiltinActions[i].identifier forKey:@"actionID"]; item->action = @selector(selectBuiltin:); [result addObject:item];
    }
    if (!found) [result addObject:[self placeholderSpecifier:@"无匹配的内置动作"]];

    [result addObject:[PSSpecifier groupSpecifierWithName:@"应用"]];
    [result addObject:[self searchSpecifier:@"app"]]; found = NO;
    for (NSDictionary *app in _applications) if ([self matches:app[@"name"] group:@"app"] || [self matches:app[@"bundleID"] group:@"app"]) {
        found = YES; PSSpecifier *item = [PSSpecifier preferenceSpecifierNamed:app[@"name"] target:self set:NULL get:NULL detail:Nil cell:PSStaticTextCell edit:Nil]; [item setProperty:app[@"bundleID"] forKey:@"appBundleID"]; [item setProperty:app[@"name"] forKey:@"appName"]; item->action = @selector(selectApp:); [result addObject:item];
    }
    if (!found) [result addObject:[self placeholderSpecifier:_applications.count ? @"无匹配的应用" : @"未找到可用应用"]];

    [result addObject:[PSSpecifier groupSpecifierWithName:@"指令"]];
    [result addObject:[self searchSpecifier:@"shortcut"]]; found = NO;
    for (NSDictionary *shortcut in _shortcuts) if ([self matches:shortcut[@"name"] group:@"shortcut"] || [self matches:shortcut[@"identifier"] group:@"shortcut"]) {
        found = YES; PSSpecifier *item = [PSSpecifier preferenceSpecifierNamed:shortcut[@"name"] target:self set:NULL get:NULL detail:Nil cell:PSStaticTextCell edit:Nil]; [item setProperty:shortcut[@"identifier"] forKey:@"shortcutIdentifier"]; [item setProperty:shortcut[@"name"] forKey:@"shortcutName"]; item->action = @selector(selectShortcut:); [result addObject:item];
    }
    if (!found) [result addObject:[self placeholderSpecifier:_shortcuts.count ? @"无匹配的指令" : @"未找到快捷指令（可点右上角添加链接）"]];

    [result addObject:[PSSpecifier groupSpecifierWithName:@"链接"]];
    [result addObject:[self searchSpecifier:@"link"]]; found = NO;
    for (NSDictionary *link in _links) if ([self matches:link[@"title"] group:@"link"] || [self matches:link[@"url"] group:@"link"]) {
        found = YES; PSSpecifier *item = [PSSpecifier preferenceSpecifierNamed:link[@"title"] target:self set:NULL get:NULL detail:Nil cell:PSStaticTextCell edit:Nil]; [item setProperty:link[@"id"] forKey:@"linkID"]; [item setProperty:link[@"url"] forKey:@"linkURL"]; item->action = @selector(selectLink:); [result addObject:item];
    }
    if (!found) [result addObject:[self placeholderSpecifier:_links.count ? @"无匹配的链接" : @"暂无链接，点击右上角添加"]];
    return result;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    PSSpecifier *spec = [self specifierAtIndexPath:indexPath];
    NSString *group = [spec propertyForKey:@"searchGroup"];
    if (group.length) {
        UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        UISearchBar *bar = [[UISearchBar alloc] initWithFrame:CGRectZero]; bar.tag = 9000 + [@[@"builtin", @"app", @"shortcut", @"link"] indexOfObject:group]; bar.delegate = self; bar.placeholder = [NSString stringWithFormat:@"搜索%@", [@{@"builtin": @"内置动作", @"app": @"应用", @"shortcut": @"指令", @"link": @"链接"} objectForKey:group]]; bar.text = _searches[group]; bar.autocapitalizationType = UITextAutocapitalizationTypeNone; bar.autocorrectionType = UITextAutocorrectionTypeNo; bar.translatesAutoresizingMaskIntoConstraints = NO; [cell.contentView addSubview:bar]; [NSLayoutConstraint activateConstraints:@[[bar.leadingAnchor constraintEqualToAnchor:cell.contentView.leadingAnchor], [bar.trailingAnchor constraintEqualToAnchor:cell.contentView.trailingAnchor], [bar.topAnchor constraintEqualToAnchor:cell.contentView.topAnchor], [bar.bottomAnchor constraintEqualToAnchor:cell.contentView.bottomAnchor]]]; return cell;
    }
    UITableViewCell *cell = [super tableView:tableView cellForRowAtIndexPath:indexPath];
    if ([spec propertyForKey:@"currentSelection"]) { cell.accessoryType = UITableViewCellAccessoryNone; cell.textLabel.font = [UIFont boldSystemFontOfSize:cell.textLabel.font.pointSize]; }
    if ([spec propertyForKey:@"placeholder"]) { cell.textLabel.textColor = [UIColor secondaryLabelColor]; cell.selectionStyle = UITableViewCellSelectionStyleNone; cell.accessoryType = UITableViewCellAccessoryNone; }
    NSString *action = [spec propertyForKey:@"actionID"];
    if (action.length) cell.accessoryType = [_currentValue isEqualToString:action] ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
    NSString *bundleID = [spec propertyForKey:@"appBundleID"];
    if (bundleID.length) cell.accessoryType = [_currentValue isEqualToString:[@"app:" stringByAppendingString:bundleID]] ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
    NSString *shortcutID = [spec propertyForKey:@"shortcutIdentifier"];
    if (shortcutID.length) { NSString *saved = [NSString stringWithFormat:@"shortcutid:%@|%@", shortcutID, [spec propertyForKey:@"shortcutName"]]; cell.accessoryType = [_currentValue isEqualToString:saved] ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone; cell.detailTextLabel.text = shortcutID; }
    NSString *linkID = [spec propertyForKey:@"linkID"];
    if (linkID.length) { cell.accessoryType = [_currentValue isEqualToString:[@"link:" stringByAppendingString:linkID]] ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone; cell.detailTextLabel.text = [spec propertyForKey:@"linkURL"]; }
    return cell;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath { return [[self specifierAtIndexPath:indexPath] propertyForKey:@"searchGroup"] ? 56.0 : UITableViewAutomaticDimension; }

- (void)searchBar:(UISearchBar *)searchBar textDidChange:(NSString *)searchText {
    NSArray *groups = @[@"builtin", @"app", @"shortcut", @"link"]; NSInteger index = searchBar.tag - 9000; if (index < 0 || index >= groups.count) return; _searches[groups[index]] = searchText ?: @""; _specifiers = nil; [self reloadSpecifiers];
}

- (void)saveAction:(NSString *)action {
    if (!action.length) return; _currentValue = [action copy]; CFPreferencesSetAppValue((__bridge CFStringRef)_preferenceKey, (__bridge CFPropertyListRef)action, ABMCDomain); CFPreferencesAppSynchronize(ABMCDomain); CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), ABMCChanged, NULL, NULL, YES); _specifiers = nil; [self reloadSpecifiers]; [self updateCurrentHeader];
}
- (void)selectBuiltin:(PSSpecifier *)spec { [self saveAction:[spec propertyForKey:@"actionID"]]; }
- (void)selectApp:(PSSpecifier *)spec { [self saveAction:[@"app:" stringByAppendingString:[spec propertyForKey:@"appBundleID"]]]; }
- (void)selectShortcut:(PSSpecifier *)spec { [self saveAction:[NSString stringWithFormat:@"shortcutid:%@|%@", [spec propertyForKey:@"shortcutIdentifier"], [spec propertyForKey:@"shortcutName"]]]; }
- (void)selectLink:(PSSpecifier *)spec { [self saveAction:[@"link:" stringByAppendingString:[spec propertyForKey:@"linkID"]]]; }

@end
