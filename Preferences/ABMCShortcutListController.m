#import "ABMCShortcutListController.h"
#import <objc/message.h>
#import <dlfcn.h>

#define ABMCDomain CFSTR("com.huynguyen.actionbuttonmulticlick")
#define ABMCChanged CFSTR("com.huynguyen.actionbuttonmulticlick/prefsChanged")

@implementation ABMCShortcutListController {
    NSString *_preferenceKey;
    NSArray *_shortcuts;
}

- (instancetype)initWithPreferenceKey:(NSString *)key {
    if ((self = [super initWithStyle:UITableViewStyleInsetGrouped])) {
        _preferenceKey = [key copy];
        self.title = @"选择指令";
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemRefresh target:self action:@selector(loadShortcuts)];
    [self loadShortcuts];
}

- (void)loadShortcuts {
    NSMutableArray *items = [NSMutableArray array];
    dlopen("/System/Library/PrivateFrameworks/WorkflowKit.framework/WorkflowKit", RTLD_LAZY | RTLD_LOCAL);
    @try {
        for (NSString *className in @[@"WFDatabase", @"WFWorkflowDatabase"]) {
            Class databaseClass = NSClassFromString(className);
            if (!databaseClass) continue;
            id database = nil;
            SEL selector = NSSelectorFromString(@"sharedDatabase");
            if ([databaseClass respondsToSelector:selector]) database = ((id (*)(id, SEL))objc_msgSend)(databaseClass, selector);
            if (!database) {
                selector = NSSelectorFromString(@"sharedInstance");
                if ([databaseClass respondsToSelector:selector]) database = ((id (*)(id, SEL))objc_msgSend)(databaseClass, selector);
            }
            for (NSString *methodName in @[@"sortedVisibleWorkflowsByName", @"allWorkflows", @"workflows"]) {
                selector = NSSelectorFromString(methodName);
                id workflows = (database && [database respondsToSelector:selector]) ? ((id (*)(id, SEL))objc_msgSend)(database, selector) : nil;
                if (![workflows isKindOfClass:[NSArray class]]) continue;
                for (id workflow in workflows) {
                    NSString *name = [workflow respondsToSelector:@selector(name)] ? [workflow name] : nil;
                    NSString *identifier = [workflow respondsToSelector:@selector(identifier)] ? [workflow identifier] : nil;
                    if (name.length && identifier.length) [items addObject:@{@"name": name, @"identifier": identifier}];
                }
                if (items.count) break;
            }
            if (items.count) break;
        }
    } @catch (NSException *exception) {}
    NSMutableDictionary *unique = [NSMutableDictionary dictionary];
    for (NSDictionary *item in items) unique[item[@"identifier"]] = item;
    _shortcuts = [[unique allValues] sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) { return [a[@"name"] localizedCaseInsensitiveCompare:b[@"name"]]; }];
    [self.tableView reloadData];
    if (!_shortcuts.count) [self showManualEntry];
}

- (NSString *)selectedAction {
    CFStringRef value = CFPreferencesCopyAppValue((__bridge CFStringRef)_preferenceKey, ABMCDomain);
    NSString *result = value ? [(__bridge NSString *)value copy] : nil;
    if (value) CFRelease(value);
    return result;
}

- (void)showManualEntry {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"无法读取指令库" message:@"可以手动输入快捷指令名称。包含打开 App、确认或输入等界面操作的指令，系统仍可能打开快捷指令 App。" preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *field) {
        field.placeholder = @"快捷指令名称";
        NSString *selected = [self selectedAction];
        if ([selected hasPrefix:@"shortcut:"]) field.text = [selected substringFromIndex:9];
    }];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"保存" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        NSString *name = [alert.textFields.firstObject.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (!name.length || name.length > 200) return;
        NSString *saved = [@"shortcut:" stringByAppendingString:name];
        CFPreferencesSetAppValue((__bridge CFStringRef)self->_preferenceKey, (__bridge CFPropertyListRef)saved, ABMCDomain);
        CFPreferencesAppSynchronize(ABMCDomain);
        CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), ABMCChanged, NULL, NULL, YES);
        [self.navigationController popViewControllerAnimated:YES];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return 1; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return _shortcuts.count; }

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"ABMCShortcutCell"];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"ABMCShortcutCell"];
    NSDictionary *item = _shortcuts[indexPath.row];
    cell.textLabel.text = item[@"name"];
    cell.detailTextLabel.text = item[@"identifier"];
    NSString *selected = [self selectedAction];
    NSString *action = [NSString stringWithFormat:@"shortcutid:%@|%@", item[@"identifier"], item[@"name"]];
    cell.accessoryType = [selected isEqualToString:action] || [selected isEqualToString:[@"shortcut:" stringByAppendingString:item[@"name"]]] ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    NSDictionary *item = _shortcuts[indexPath.row];
    NSString *action = [NSString stringWithFormat:@"shortcutid:%@|%@", item[@"identifier"], item[@"name"]];
    CFPreferencesSetAppValue((__bridge CFStringRef)_preferenceKey, (__bridge CFPropertyListRef)action, ABMCDomain);
    CFPreferencesAppSynchronize(ABMCDomain);
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), ABMCChanged, NULL, NULL, YES);
    [self.navigationController popViewControllerAnimated:YES];
}

@end
