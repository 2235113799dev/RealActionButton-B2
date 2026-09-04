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

- (void)clearCurrent:(UITapGestureRecognizer *)gesture { ABMCStoreSelectedActions(_preferenceKey,@[]);[self.tableView reloadData]; }
- (void)clearAll:(UITapGestureRecognizer *)gesture { for(NSString *key in @[@"singleClickAction",@"doubleClickAction",@"longPressAction"]){NSMutableArray *items=[ABMCSelectedActions(key) mutableCopy];[items filterUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSString *a,NSDictionary *b){return ![a hasPrefix:@"app:"];}]];ABMCStoreSelectedActions(key,items);}[self.tableView reloadData]; }
- (void)reloadApplications {
    NSMutableArray *items = [NSMutableArray array];
    for (id app in ABMCInstalledApplications()) {
        NSString *identifier = ABMCBundleIdentifierForApplication(app);
        NSString *name = ABMCDisplayNameForApplication(app);
        // A launchable app must expose a genuine SpringBoard icon. Service
        // proxies render as the white blueprint in Settings and are excluded.
        if (identifier.length && name.length && ABMCIconImageForProxy(app)) [items addObject:@{ @"id": identifier, @"name": name, @"kind": @(ABMCApplicationKindForProxy(app)) }];
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
    NSString *action=[@"app:" stringByAppendingString:identifier];
    cell.accessoryType=[ABMCSelectedActions(_preferenceKey) containsObject:action] ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
    ABMCInstallPresentationLongPress(cell,self,presentationKey,ABMCDisplayTitle(presentationKey,item[@"name"]),ABMCDisplayIconToken(presentationKey,identifier),^{ [self.tableView reloadData]; });
    return cell;
}


- (void)showLimit { UIAlertController *a=[UIAlertController alertControllerWithTitle:@"最多 8 项" message:@"每个按键动作最多可选择 8 项。" preferredStyle:UIAlertControllerStyleAlert];[a addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];[self presentViewController:a animated:YES completion:nil]; }

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    NSString *action=[@"app:" stringByAppendingString:self.visibleApplications[indexPath.row][@"id"]]; NSMutableArray *chosen=[ABMCSelectedActions(_preferenceKey) mutableCopy];
    if([chosen containsObject:action])[chosen removeObject:action]; else if(chosen.count<8)[chosen addObject:action]; else { [self showLimit]; return; }
    ABMCStoreSelectedActions(_preferenceKey,chosen); [tableView reloadData];
}
- (void)searchBar:(UISearchBar *)searchBar textDidChange:(NSString *)text { _query = [text copy] ?: @""; [self.tableView reloadData]; }
@end
