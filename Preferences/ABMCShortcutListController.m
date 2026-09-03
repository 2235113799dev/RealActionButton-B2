#import "ABMCShortcutListController.h"
#import <objc/message.h>
#import <dlfcn.h>

#define ABMCDomain CFSTR("com.huynguyen.actionbuttonmulticlick")
#define ABMCChanged CFSTR("com.huynguyen.actionbuttonmulticlick/prefsChanged")

static NSString *ABMCValue(id obj, NSArray *names) {
    for (NSString *name in names) { SEL s=NSSelectorFromString(name); if ([obj respondsToSelector:s]) { id v=((id(*)(id,SEL))objc_msgSend)(obj,s); if ([v isKindOfClass:[NSString class]] && [v length]) return v; } }
    return nil;
}
@implementation ABMCShortcutListController {
    NSString *_preferenceKey;
    NSArray *_shortcuts;
    NSString *_searchText;
}
- (instancetype)initWithPreferenceKey:(NSString *)key { if((self=[super initWithStyle:UITableViewStyleInsetGrouped])){_preferenceKey=[key copy];self.title=@"指令";}return self; }
- (void)viewDidLoad { [super viewDidLoad]; _searchText=@""; UISearchBar *bar=[[UISearchBar alloc]initWithFrame:CGRectMake(0,0,UIScreen.mainScreen.bounds.size.width,56)];bar.placeholder=@"搜索指令";bar.delegate=(id)self;self.tableView.tableHeaderView=bar; self.navigationItem.rightBarButtonItem=[[UIBarButtonItem alloc]initWithBarButtonSystemItem:UIBarButtonSystemItemRefresh target:self action:@selector(loadShortcuts)];[self loadShortcuts]; }
- (void)append:(id)obj to:(NSMutableDictionary *)unique { if([obj isKindOfClass:[NSDictionary class]]){NSString*n=obj[@"name"]?:obj[@"title"];NSString*i=obj[@"identifier"]?:obj[@"workflowIdentifier"]?:obj[@"id"];if([n isKindOfClass:[NSString class]]&&[i isKindOfClass:[NSString class]]&&n.length&&i.length)unique[i]=@{ @"name":n,@"identifier":i };return;}NSString*n=ABMCValue(obj,@[@"name",@"localizedName",@"displayName",@"title"]);NSString*i=ABMCValue(obj,@[@"identifier",@"workflowIdentifier",@"persistentIdentifier",@"recordIdentifier",@"uniqueIdentifier"]);if(n.length&&i.length)unique[i]=@{ @"name":n,@"identifier":i}; }
- (void)loadShortcuts { NSMutableDictionary *unique=[NSMutableDictionary dictionary]; @try { dlopen("/System/Library/PrivateFrameworks/WorkflowKit.framework/WorkflowKit",RTLD_LAZY|RTLD_LOCAL); for(NSString*cn in @[@"WFWorkflowController",@"WFWorkflowManager",@"WFWorkflowStore",@"WFDatabase",@"WFWorkflowDatabase",@"ICDatabase",@"SGShortcutsController",@"SGShortcutsGenerator"]){Class c=NSClassFromString(cn);if(!c)continue;NSMutableArray*t=[NSMutableArray array];for(NSString*sn in @[@"sharedInstance",@"sharedDatabase",@"sharedStore",@"defaultDatabase",@"defaultStore",@"sharedController"]){SEL s=NSSelectorFromString(sn);if([c respondsToSelector:s]){id o=((id(*)(id,SEL))objc_msgSend)(c,s);if(o)[t addObject:o];}}if([c instancesRespondToSelector:NSSelectorFromString(@"shortcutsArray")]||[c instancesRespondToSelector:NSSelectorFromString(@"shortcuts")]){id o=[[c alloc]init];if(o)[t addObject:o];}for(id o in t){for(NSString*mn in @[@"allWorkflows",@"sortedVisibleWorkflowsByName",@"visibleWorkflows",@"workflows",@"shortcutsArray",@"shortcuts",@"allShortcuts",@"allWorkflowsSortedByName"]){SEL s=NSSelectorFromString(mn);if([o respondsToSelector:s]){id r=((id(*)(id,SEL))objc_msgSend)(o,s);if([r isKindOfClass:[NSArray class]])for(id x in r)[self append:x to:unique];}}}if(unique.count)break;}}@catch(NSException*e){} _shortcuts=[[unique allValues]sortedArrayUsingComparator:^NSComparisonResult(NSDictionary*a,NSDictionary*b){return[a[@"name"] localizedCaseInsensitiveCompare:b[@"name"]];}];[self.tableView reloadData]; }
- (NSArray*)filtered{NSMutableArray*r=[NSMutableArray array];for(NSDictionary*x in _shortcuts)if(!_searchText.length||[x[@"name"]localizedCaseInsensitiveContainsString:_searchText]||[x[@"identifier"]localizedCaseInsensitiveContainsString:_searchText])[r addObject:x];return r;}
- (NSInteger)tableView:(UITableView*)tableView numberOfRowsInSection:(NSInteger)section{return self.filtered.count;}
- (UITableViewCell*)tableView:(UITableView*)tableView cellForRowAtIndexPath:(NSIndexPath*)p{UITableViewCell*c=[tableView dequeueReusableCellWithIdentifier:@"ShortcutCell"]?:[[UITableViewCell alloc]initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"ShortcutCell"];NSDictionary*x=self.filtered[p.row];c.textLabel.text=x[@"name"];c.detailTextLabel.text=x[@"identifier"];NSString*a=[NSString stringWithFormat:@"shortcutid:%@|%@",x[@"identifier"],x[@"name"]];CFStringRef v=(CFStringRef)CFPreferencesCopyAppValue((__bridge CFStringRef)_preferenceKey,ABMCDomain);c.accessoryType=v&&[(__bridge NSString*)v isEqualToString:a]?UITableViewCellAccessoryCheckmark:UITableViewCellAccessoryNone;if(v)CFRelease(v);return c;}
- (void)tableView:(UITableView*)tableView didSelectRowAtIndexPath:(NSIndexPath*)p{NSDictionary*x=self.filtered[p.row];NSString*a=[NSString stringWithFormat:@"shortcutid:%@|%@",x[@"identifier"],x[@"name"]];CFPreferencesSetAppValue((__bridge CFStringRef)_preferenceKey,(__bridge CFPropertyListRef)a,ABMCDomain);CFPreferencesAppSynchronize(ABMCDomain);CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),ABMCChanged,NULL,NULL,YES);[self.navigationController popViewControllerAnimated:YES];}
- (void)searchBar:(UISearchBar*)bar textDidChange:(NSString*)text{_searchText=[text copy];[self.tableView reloadData];}
@end
