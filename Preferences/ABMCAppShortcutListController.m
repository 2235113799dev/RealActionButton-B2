#import "ABMCAppShortcutListController.h"
#import "ABMCUIHelpers.h"
#import <objc/message.h>
#import <dlfcn.h>

#define Domain CFSTR("com.huynguyen.actionbuttonmulticlick")
#define Changed CFSTR("com.huynguyen.actionbuttonmulticlick/prefsChanged")
static id Call(id object, NSString *name) { SEL s=NSSelectorFromString(name); return object&&[object respondsToSelector:s]?((id(*)(id,SEL))objc_msgSend)(object,s):nil; }

@interface ABMCAppShortcutListController () <UISearchBarDelegate>
@end
@implementation ABMCAppShortcutListController { NSString *_key,*_query; NSArray *_groups; BOOL _loading; }
- (instancetype)initWithPreferenceKey:(NSString *)key { if((self=[super initWithStyle:UITableViewStyleInsetGrouped])){_key=[key copy];self.title=@"快捷方式";}return self; }
- (void)viewDidLoad { [super viewDidLoad];_query=@"";self.tableView.rowHeight=64;UIView*h=[[UIView alloc]initWithFrame:CGRectMake(0,0,UIScreen.mainScreen.bounds.size.width,68)];UISearchBar*s=[[UISearchBar alloc]initWithFrame:CGRectInset(h.bounds,8,6)];s.placeholder=@"搜索快捷方式";s.delegate=self;[h addSubview:s];self.tableView.tableHeaderView=h;self.navigationItem.rightBarButtonItem=[[UIBarButtonItem alloc]initWithBarButtonSystemItem:UIBarButtonSystemItemRefresh target:self action:@selector(reloadShortcuts)];[self reloadShortcuts]; }
- (void)addItems:(NSArray *)raw into:(NSMutableArray *)items {
    for(id entry in [raw isKindOfClass:NSArray.class]?raw:@[]) {
        NSDictionary *dict=[entry isKindOfClass:NSDictionary.class]?entry:nil;
        NSString *type=Call(entry,@"type")?:dict[@"UIApplicationShortcutItemType"];
        NSString *title=Call(entry,@"localizedTitle")?:Call(entry,@"title")?:dict[@"UIApplicationShortcutItemTitle"];
        NSString *subtitle=Call(entry,@"localizedSubtitle")?:dict[@"UIApplicationShortcutItemSubtitle"]?:@"";
        if(!type.length||!title.length)continue;
        BOOL duplicate=NO;for(NSDictionary*x in items)if([x[@"type"]isEqualToString:type]){duplicate=YES;break;}
        if(!duplicate)[items addObject:@{ @"type":type,@"title":title,@"subtitle":subtitle }];
    }
}
- (NSArray *)serviceItemsForBundleID:(NSString *)bundleID client:(id)client {
    SEL selector=NSSelectorFromString(@"applicationShortcutItemsOfTypes:forBundleIdentifier:");
    if(!client||![client respondsToSelector:selector])return @[];
    @try { id items=((id(*)(id,SEL,unsigned long long,id))objc_msgSend)(client,selector,~0ULL,bundleID);return[items isKindOfClass:NSArray.class]?items:@[]; } @catch(NSException *e){return @[];}
}
- (void)reloadShortcuts {
    if(_loading)return;
    _loading=YES;_groups=@[];[self.tableView reloadData];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY,0), ^{
        dlopen("/System/Library/PrivateFrameworks/SpringBoardServices.framework/SpringBoardServices",RTLD_LAZY|RTLD_LOCAL);
        Class clientClass=NSClassFromString(@"SBSApplicationClient");SEL checkout=NSSelectorFromString(@"checkOutClientWithClass:"),checkin=NSSelectorFromString(@"checkInClient:");id client=nil;
        @try { if([clientClass respondsToSelector:checkout])client=((id(*)(id,SEL,id))objc_msgSend)(clientClass,checkout,clientClass); } @catch(NSException *e){}
        NSMutableArray *groups=[NSMutableArray array];
        for(id app in ABMCInstalledApplications()) {
            NSString *bundleID=ABMCBundleIdentifierForApplication(app),*name=ABMCDisplayNameForApplication(app);if(!bundleID.length||!name.length)continue;
            NSMutableArray *items=[NSMutableArray array];
            [self addItems:Call(app,@"staticShortcutItems") into:items];
            NSURL *url=Call(app,@"bundleURL");
            [self addItems:[NSBundle bundleWithURL:url].infoDictionary[@"UIApplicationShortcutItems"] into:items];
            // One checked-out system client serves all apps; this is substantially
            // lighter than opening a cross-process connection for every row.
            if(!items.count)[self addItems:[self serviceItemsForBundleID:bundleID client:client] into:items];
            if(items.count)[groups addObject:@{ @"id":bundleID,@"name":name,@"items":items }];
        }
        if(client&&[clientClass respondsToSelector:checkin])((void(*)(id,SEL,id))objc_msgSend)(clientClass,checkin,client);
        NSArray *sorted=[groups sortedArrayUsingComparator:^NSComparisonResult(NSDictionary*a,NSDictionary*b){return[a[@"name"] localizedCaseInsensitiveCompare:b[@"name"]];}];
        dispatch_async(dispatch_get_main_queue(), ^{ self->_groups=sorted;self->_loading=NO;[self.tableView reloadData]; });
    });
}
- (NSArray *)visibleGroups {if(!_query.length)return _groups?:@[];NSMutableArray*r=[NSMutableArray array];for(NSDictionary*g in _groups){NSMutableArray*m=[NSMutableArray array];for(NSDictionary*i in g[@"items"]){if([g[@"name"] localizedCaseInsensitiveContainsString:_query]||[g[@"id"] localizedCaseInsensitiveContainsString:_query]||[i[@"title"] localizedCaseInsensitiveContainsString:_query]||[i[@"subtitle"] localizedCaseInsensitiveContainsString:_query])[m addObject:i];}if(m.count){NSMutableDictionary*c=[g mutableCopy];c[@"items"]=m;[r addObject:c];}}return r;}
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView{return self.visibleGroups.count?:1;}
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section{return self.visibleGroups.count?[self.visibleGroups[section][@"items"]count]:1;}
- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section{return self.visibleGroups.count?self.visibleGroups[section][@"name"]:nil;}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)path {UITableViewCell*c=[tableView dequeueReusableCellWithIdentifier:@"AppShortcutCell"]?:[[UITableViewCell alloc]initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"AppShortcutCell"];if(_loading){ABMCApplyLargeIcon(c,ABMCTintedIcon(@"arrow.clockwise",UIColor.secondaryLabelColor));c.textLabel.text=@"正在读取快捷方式…";c.detailTextLabel.text=@"";c.selectionStyle=UITableViewCellSelectionStyleNone;c.accessoryType=UITableViewCellAccessoryNone;return c;}if(!self.visibleGroups.count){ABMCApplyLargeIcon(c,ABMCTintedIcon(@"square.grid.2x2",UIColor.secondaryLabelColor));c.textLabel.text=@"未发现应用快捷方式";c.detailTextLabel.text=@"应用需要提供快捷操作";c.selectionStyle=UITableViewCellSelectionStyleNone;c.accessoryType=UITableViewCellAccessoryNone;return c;}NSDictionary*g=self.visibleGroups[path.section],*i=g[@"items"][path.row];ABMCApplyLargeIcon(c,ABMCIconImageForBundleID(g[@"id"])?:ABMCTintedIcon(@"app.fill",UIColor.systemBlueColor));c.textLabel.font=[UIFont systemFontOfSize:18];c.detailTextLabel.font=[UIFont systemFontOfSize:14];c.textLabel.text=i[@"title"];c.detailTextLabel.text=i[@"subtitle"];c.selectionStyle=UITableViewCellSelectionStyleDefault;NSString*a=[NSString stringWithFormat:@"appshortcut:%@|%@|%@",g[@"id"],i[@"type"],i[@"title"]];CFStringRef v=(CFStringRef)CFPreferencesCopyAppValue((__bridge CFStringRef)_key,Domain);c.accessoryType=v&&[(__bridge NSString*)v isEqualToString:a]?UITableViewCellAccessoryCheckmark:UITableViewCellAccessoryNone;if(v)CFRelease(v);return c;}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)path {if(_loading||!self.visibleGroups.count)return;NSDictionary*g=self.visibleGroups[path.section],*i=g[@"items"][path.row];NSString*a=[NSString stringWithFormat:@"appshortcut:%@|%@|%@",g[@"id"],i[@"type"],i[@"title"]];CFPreferencesSetAppValue((__bridge CFStringRef)_key,(__bridge CFPropertyListRef)a,Domain);CFPreferencesAppSynchronize(Domain);CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),Changed,NULL,NULL,YES);[self.navigationController popViewControllerAnimated:YES];}
- (void)searchBar:(UISearchBar *)searchBar textDidChange:(NSString *)text{_query=[text copy]?:@"";[self.tableView reloadData];}
@end
