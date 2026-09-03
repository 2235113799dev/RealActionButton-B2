#import "ABMCLinkListController.h"

#define ABMCDomain CFSTR("com.huynguyen.actionbuttonmulticlick")
#define ABMCLinksKey CFSTR("savedLinks")
#define ABMCChanged CFSTR("com.huynguyen.actionbuttonmulticlick/prefsChanged")

@implementation ABMCLinkListController {
    NSString *_preferenceKey;
    NSMutableArray *_links;
}

- (instancetype)initWithPreferenceKey:(NSString *)key {
    if ((self = [super initWithStyle:UITableViewStyleInsetGrouped])) {
        _preferenceKey = [key copy];
        self.title = @"选择链接";
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAdd target:self action:@selector(addLink)];
    [self loadLinks];
}

- (void)loadLinks {
    _links = [NSMutableArray array];
    CFPropertyListRef value = CFPreferencesCopyAppValue(ABMCLinksKey, ABMCDomain);
    if (value && CFGetTypeID(value) == CFArrayGetTypeID()) {
        for (id entry in (__bridge NSArray *)value) {
            if ([entry isKindOfClass:[NSDictionary class]] && [entry[@"id"] isKindOfClass:[NSString class]] && [entry[@"title"] isKindOfClass:[NSString class]] && [entry[@"url"] isKindOfClass:[NSString class]]) [_links addObject:[entry mutableCopy]];
        }
    }
    if (value) CFRelease(value);
    [self.tableView reloadData];
}

- (void)saveLinks {
    CFPreferencesSetAppValue(ABMCLinksKey, (__bridge CFPropertyListRef)_links, ABMCDomain);
    CFPreferencesAppSynchronize(ABMCDomain);
}

- (NSString *)selectedLinkID {
    CFStringRef value = CFPreferencesCopyAppValue((__bridge CFStringRef)_preferenceKey, ABMCDomain);
    NSString *action = value ? [(__bridge NSString *)value copy] : nil;
    if (value) CFRelease(value);
    return [action hasPrefix:@"link:"] ? [action substringFromIndex:5] : nil;
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return 1; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return _links.count; }

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"ABMCLinkCell"];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"ABMCLinkCell"];
    NSDictionary *link = _links[indexPath.row];
    cell.textLabel.text = link[@"title"];
    cell.detailTextLabel.text = link[@"url"];
    cell.accessoryType = [link[@"id"] isEqualToString:[self selectedLinkID]] ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    NSString *action = [@"link:" stringByAppendingString:_links[indexPath.row][@"id"]];
    CFPreferencesSetAppValue((__bridge CFStringRef)_preferenceKey, (__bridge CFPropertyListRef)action, ABMCDomain);
    CFPreferencesAppSynchronize(ABMCDomain);
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), ABMCChanged, NULL, NULL, YES);
    [self.navigationController popViewControllerAnimated:YES];
}

- (void)addLink { [self editLink:nil]; }

- (void)editLink:(NSDictionary *)existing {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:existing ? @"编辑链接" : @"新增链接" message:nil preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *field) { field.placeholder = @"标题"; field.text = existing[@"title"]; }];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *field) { field.placeholder = @"URL-Scheme 或网址"; field.text = existing[@"url"]; field.autocapitalizationType = UITextAutocapitalizationTypeNone; field.autocorrectionType = UITextAutocorrectionTypeNo; }];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"保存" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        NSString *title = [alert.textFields[0].text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        NSString *urlString = [alert.textFields[1].text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        NSURL *url = [NSURL URLWithString:urlString];
        NSCharacterSet *invalid = [NSCharacterSet controlCharacterSet];
        BOOL valid = title.length && title.length <= 100 && urlString.length && urlString.length <= 4096 && url && url.scheme.length && [urlString rangeOfCharacterFromSet:invalid].location == NSNotFound && [urlString rangeOfCharacterFromSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]].location == NSNotFound;
        if (!valid) return;
        NSMutableDictionary *item = [NSMutableDictionary dictionaryWithDictionary:existing ?: @{}];
        if (![item[@"id"] isKindOfClass:[NSString class]]) item[@"id"] = [NSUUID UUID].UUIDString;
        item[@"title"] = title; item[@"url"] = urlString;
        NSUInteger index = existing ? [_links indexOfObject:existing] : NSNotFound;
        if (index == NSNotFound) [_links addObject:item]; else _links[index] = item;
        [self saveLinks]; [self.tableView reloadData];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (NSArray<UITableViewRowAction *> *)tableView:(UITableView *)tableView editActionsForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewRowAction *edit = [UITableViewRowAction rowActionWithStyle:UITableViewRowActionStyleNormal title:@"编辑" handler:^(UITableViewRowAction *action, NSIndexPath *path) { [self editLink:self->_links[path.row]]; }];
    edit.backgroundColor = [UIColor systemBlueColor];
    return @[edit];
}

- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)style forRowAtIndexPath:(NSIndexPath *)indexPath {
    if (style != UITableViewCellEditingStyleDelete) return;
    NSString *deleted = _links[indexPath.row][@"id"];
    if ([deleted isEqualToString:[self selectedLinkID]]) {
        CFPreferencesSetAppValue((__bridge CFStringRef)_preferenceKey, (__bridge CFPropertyListRef)@"none", ABMCDomain);
        CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), ABMCChanged, NULL, NULL, YES);
    }
    [_links removeObjectAtIndex:indexPath.row]; [self saveLinks];
    [tableView deleteRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationAutomatic];
}

@end
