#import "ABMCApplicationListController.h"
#import "ABMCUIHelpers.h"

#define Domain CFSTR("com.huynguyen.actionbuttonmulticlick")
#define Changed CFSTR("com.huynguyen.actionbuttonmulticlick/prefsChanged")

@interface ABMCApplicationListController () <UISearchBarDelegate>
@end

@implementation ABMCApplicationListController {
    NSString *_preferenceKey;
    NSArray<NSDictionary *> *_applications;
    NSString *_query;
    ABMCApplicationKind _kind;
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
    _kind = ABMCApplicationKindAll;
    UIView *header = [[UIView alloc] initWithFrame:CGRectMake(0, 0, UIScreen.mainScreen.bounds.size.width, 116)];
    UISearchBar *search = [[UISearchBar alloc] initWithFrame:CGRectMake(8, 4, header.bounds.size.width - 16, 56)];
    search.placeholder = @"搜索应用";
    search.delegate = self;
    [header addSubview:search];
    UISegmentedControl *segments = [[UISegmentedControl alloc] initWithItems:@[@"所有应用", @"用户应用", @"巨魔应用", @"系统应用"]];
    segments.frame = CGRectMake(10, 68, header.bounds.size.width - 20, 36);
    segments.selectedSegmentIndex = 0;
    [segments addTarget:self action:@selector(changeKind:) forControlEvents:UIControlEventValueChanged];
    [header addSubview:segments];
    self.tableView.tableHeaderView = header;
    UIButton *clear=[UIButton buttonWithType:UIButtonTypeSystem];clear.frame=CGRectMake(0,0,48,32);[clear setTitle:@"清空" forState:UIControlStateNormal];UITapGestureRecognizer *single=[[UITapGestureRecognizer alloc]initWithTarget:self action:@selector(clearCurrent:)];UITapGestureRecognizer *doubleTap=[[UITapGestureRecognizer alloc]initWithTarget:self action:@selector(clearAll:)];doubleTap.numberOfTapsRequired=2;[single requireGestureRecognizerToFail:doubleTap];[clear addGestureRecognizer:single];[clear addGestureRecognizer:doubleTap];self.navigationItem.rightBarButtonItem=[[UIBarButtonItem alloc]initWithCustomView:clear];
    [self reloadApplications];
}

- (void)clearCurrent:(UITapGestureRecognizer *)gesture { CFPreferencesSetAppValue((__bridge CFStringRef)_preferenceKey,CFSTR("none"),Domain);CFPreferencesAppSynchronize(Domain);CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),Changed,NULL,NULL,YES);[self.tableView reloadData]; }
- (void)clearAll:(UITapGestureRecognizer *)gesture { for(NSString *key in @[@"singleClickAction",@"doubleClickAction",@"longPressAction"]){CFStringRef value=(CFStringRef)CFPreferencesCopyAppValue((__bridge CFStringRef)key,Domain);NSString *action=value?(__bridge_transfer NSString*)value:nil;if([action hasPrefix:@"app:"])CFPreferencesSetAppValue((__bridge CFStringRef)key,CFSTR("none"),Domain);}CFPreferencesAppSynchronize(Domain);CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),Changed,NULL,NULL,YES);[self.tableView reloadData]; }
- (void)reloadApplications {
    NSMutableArray *items = [NSMutableArray array];
    for (id app in ABMCInstalledApplications()) {
        NSString *identifier = ABMCBundleIdentifierForApplication(app);
        NSString *name = ABMCDisplayNameForApplication(app);
        if (identifier.length && name.length) [items addObject:@{ @"id": identifier, @"name": name, @"kind": @(ABMCApplicationKindForProxy(app)) }];
    }
    _applications = [items sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        return [a[@"name"] localizedCaseInsensitiveCompare:b[@"name"]];
    }];
    [self.tableView reloadData];
}

- (void)changeKind:(UISegmentedControl *)sender { _kind = sender.selectedSegmentIndex; [self.tableView reloadData]; }
- (NSArray<NSDictionary *> *)visibleApplications {
    NSPredicate *filter = [NSPredicate predicateWithBlock:^BOOL(NSDictionary *item, NSDictionary *bindings) {
        if (self->_kind != ABMCApplicationKindAll && [item[@"kind"] integerValue] != self->_kind) return NO;
        return !self->_query.length || [item[@"name"] localizedCaseInsensitiveContainsString:self->_query] || [item[@"id"] localizedCaseInsensitiveContainsString:self->_query];
    }];
    return [_applications filteredArrayUsingPredicate:filter] ?: @[];
}
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return self.visibleApplications.count; }
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"ApplicationCell"];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"ApplicationCell"];
    NSDictionary *item = self.visibleApplications[indexPath.row];
    NSString *identifier = item[@"id"];
    NSString *presentationKey=[@"app." stringByAppendingString:identifier];
    NSString *token=ABMCDisplayIconToken(presentationKey,identifier);
    ABMCApplyLargeIcon(cell, ABMCTintedIcon(token,nil) ?: ABMCIconImageForBundleID(token) ?: ABMCIconImageForBundleID(identifier) ?: ABMCTintedIcon(@"app.badge.checkmark", nil));
    cell.textLabel.font = [UIFont systemFontOfSize:18.0];
    // Keep application browsing clean: identifier remains searchable but is
    // not displayed under the app name.
    cell.detailTextLabel.font = [UIFont systemFontOfSize:14.0];
    cell.textLabel.text = ABMCDisplayTitle(presentationKey,item[@"name"]);
    cell.detailTextLabel.text = nil;
    CFStringRef current = (CFStringRef)CFPreferencesCopyAppValue((__bridge CFStringRef)_preferenceKey, Domain);
    cell.accessoryType = current && [(__bridge NSString *)current isEqualToString:[@"app:" stringByAppendingString:identifier]] ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
    if (current) CFRelease(current);
    return cell;
}
- (UISwipeActionsConfiguration *)tableView:(UITableView *)tableView trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath {
    NSDictionary *item=self.visibleApplications[indexPath.row];NSString *identifier=item[@"id"],*key=[@"app." stringByAppendingString:identifier];
    UIContextualAction *edit=[UIContextualAction contextualActionWithStyle:UIContextualActionStyleNormal title:@"修改" handler:^(__unused UIContextualAction*a,__unused UIView*v,void(^done)(BOOL)){ABMCShowPresentationEditor(self,key,item[@"name"],identifier,^{[self.tableView reloadData];done(YES);});}];edit.backgroundColor=UIColor.systemBlueColor;
    UIContextualAction *clear=[UIContextualAction contextualActionWithStyle:UIContextualActionStyleDestructive title:@"清空" handler:^(__unused UIContextualAction*a,__unused UIView*v,void(^done)(BOOL)){ABMCClearPresentationOverride(key);[self.tableView reloadData];done(YES);}];clear.backgroundColor=UIColor.systemGrayColor;
    return [UISwipeActionsConfiguration configurationWithActions:@[clear,edit]];
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    NSString *action = [@"app:" stringByAppendingString:self.visibleApplications[indexPath.row][@"id"]];
    CFPreferencesSetAppValue((__bridge CFStringRef)_preferenceKey, (__bridge CFPropertyListRef)action, Domain);
    CFPreferencesAppSynchronize(Domain);
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), Changed, NULL, NULL, YES);
    [self.navigationController popViewControllerAnimated:YES];
}
- (void)searchBar:(UISearchBar *)searchBar textDidChange:(NSString *)text { _query = [text copy] ?: @""; [self.tableView reloadData]; }
@end
