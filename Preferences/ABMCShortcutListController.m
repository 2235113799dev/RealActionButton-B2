#import "ABMCShortcutListController.h"
#import "ABMCUIHelpers.h"
#import <objc/message.h>
#import <sqlite3.h>
#import <uuid/uuid.h>

#define ABMCDomain CFSTR("com.huynguyen.actionbuttonmulticlick")
#define ABMCChanged CFSTR("com.huynguyen.actionbuttonmulticlick/prefsChanged")

static BOOL ABMCIsUUID(NSString *value) { return [value isKindOfClass:[NSString class]] && [[NSUUID alloc] initWithUUIDString:value] != nil; }
static NSString *ABMCUUIDFromColumn(sqlite3_stmt *statement, int column) {
    if (sqlite3_column_type(statement, column) == SQLITE_BLOB && sqlite3_column_bytes(statement, column) == 16) {
        uuid_t bytes; memcpy(bytes, sqlite3_column_blob(statement, column), 16);
        return [[NSUUID alloc] initWithUUIDBytes:bytes].UUIDString.uppercaseString;
    }
    const unsigned char *text = sqlite3_column_text(statement, column);
    NSString *value = text ? [NSString stringWithUTF8String:(const char *)text] : nil;
    return ABMCIsUUID(value) ? value.uppercaseString : nil;
}
static id ABMCInvoke(id target, NSString *name) { SEL selector=NSSelectorFromString(name); return target&&[target respondsToSelector:selector]?((id(*)(id,SEL))objc_msgSend)(target,selector):nil; }

@interface ABMCShortcutListController () <UISearchBarDelegate>
@end

@implementation ABMCShortcutListController {
    NSString *_preferenceKey;
    NSArray *_shortcuts;
    NSString *_query;
}

- (instancetype)initWithPreferenceKey:(NSString *)key { if ((self=[super initWithStyle:UITableViewStyleInsetGrouped])) { _preferenceKey=[key copy]; self.title=@"指令列表"; } return self; }
- (void)viewDidLoad {
    [super viewDidLoad]; _query=@"";
    UIView *header=[[UIView alloc]initWithFrame:CGRectMake(0,0,UIScreen.mainScreen.bounds.size.width,72)];
    UISearchBar *search=[[UISearchBar alloc]initWithFrame:CGRectInset(header.bounds,10,8)]; search.placeholder=@"搜索全部快捷指令"; search.delegate=self; [header addSubview:search]; self.tableView.tableHeaderView=header;
    self.navigationItem.rightBarButtonItem=[[UIBarButtonItem alloc]initWithBarButtonSystemItem:UIBarButtonSystemItemRefresh target:self action:@selector(reloadShortcuts)]; [self reloadShortcuts];
}

- (NSArray *)databasePaths {
    NSMutableOrderedSet *paths=[NSMutableOrderedSet orderedSetWithArray:@[@"/var/mobile/Library/Shortcuts/Shortcuts.sqlite",@"/private/var/mobile/Library/Shortcuts/Shortcuts.sqlite",@"/var/mobile/Library/Shortcuts/Shortcuts.db",@"/private/var/mobile/Library/Shortcuts/Shortcuts.db"]];
    @try {
        Class workspaceClass=NSClassFromString(@"LSApplicationWorkspace"); id workspace=ABMCInvoke(workspaceClass,@"defaultWorkspace"); SEL proxySelector=NSSelectorFromString(@"applicationProxyForBundleIdentifier:");
        id proxy=workspace&&[workspace respondsToSelector:proxySelector]?((id(*)(id,SEL,id))objc_msgSend)(workspace,proxySelector,@"is.workflow.my.app"):nil;
        NSMutableArray *bases=[NSMutableArray array];
        id dataURL=ABMCInvoke(proxy,@"dataContainerURL"); if([dataURL isKindOfClass:[NSURL class]])[bases addObject:dataURL];
        id groupURLs=ABMCInvoke(proxy,@"groupContainerURLs"); if([groupURLs isKindOfClass:[NSDictionary class]])[bases addObjectsFromArray:[groupURLs allValues]];
        SEL groupSelector=NSSelectorFromString(@"groupContainerURLForSecurityApplicationGroupIdentifier:");
        for(NSString *group in @[@"group.is.workflow.my.app", @"group.com.apple.shortcuts", @"group.com.apple.shortcuts.widgets"]) {
            if([proxy respondsToSelector:groupSelector]) { id URL=((id(*)(id,SEL,id))objc_msgSend)(proxy,groupSelector,group); if([URL isKindOfClass:[NSURL class]])[bases addObject:URL]; }
        }
        for(NSURL *base in bases) {
            NSDirectoryEnumerator *enumerator=[[NSFileManager defaultManager] enumeratorAtURL:base includingPropertiesForKeys:nil options:NSDirectoryEnumerationSkipsHiddenFiles errorHandler:nil];
            NSUInteger found=0;
            for(NSURL *url in enumerator) {
                NSString *name=url.lastPathComponent.lowercaseString;
                if(([name hasSuffix:@".sqlite"]||[name hasSuffix:@".db"])&&([name containsString:@"shortcut"]||[name containsString:@"workflow"])) { [paths addObject:url.path]; if(++found>=24)break; }
            }
        }
    } @catch(NSException *exception) {}
    return paths.array;
}

- (void)addName:(NSString *)name identifier:(NSString *)identifier into:(NSMutableDictionary *)results {
    if(name.length&&ABMCIsUUID(identifier)) results[identifier.uppercaseString]=@{ @"name":name, @"identifier":identifier.uppercaseString };
}

- (void)readWorkflowKitInto:(NSMutableDictionary *)results {
    @try {
        dlopen("/System/Library/PrivateFrameworks/WorkflowKit.framework/WorkflowKit", RTLD_LAZY | RTLD_LOCAL);
        for (NSString *className in @[@"WFWorkflowController", @"WFWorkflowManager", @"WFWorkflowStore", @"WFDatabase", @"WFWorkflowDatabase", @"ICDatabase"]) {
            Class klass = NSClassFromString(className);
            if (!klass) continue;
            NSMutableArray *targets = [NSMutableArray array];
            for (NSString *sharedName in @[@"sharedInstance", @"sharedController", @"sharedDatabase", @"sharedStore", @"defaultStore", @"defaultDatabase"]) {
                SEL selector = NSSelectorFromString(sharedName);
                if ([klass respondsToSelector:selector]) {
                    id target = ((id (*)(id, SEL))objc_msgSend)(klass, selector);
                    if (target) [targets addObject:target];
                }
            }
            for (id target in targets) {
                for (NSString *method in @[@"sortedVisibleWorkflowsByName", @"allWorkflows", @"allWorkflowsSortedByName", @"visibleWorkflows", @"workflows", @"workflowRecords"]) {
                    SEL selector = NSSelectorFromString(method);
                    if (![target respondsToSelector:selector]) continue;
                    id workflows = ((id (*)(id, SEL))objc_msgSend)(target, selector);
                    if (![workflows isKindOfClass:[NSArray class]]) continue;
                    for (id workflow in workflows) {
                        NSString *name = nil, *identifier = nil;
                        for (NSString *selectorName in @[@"name", @"localizedName", @"displayName", @"title"]) { id value = ABMCInvoke(workflow, selectorName); if ([value isKindOfClass:[NSString class]] && [value length]) { name = value; break; } }
                        for (NSString *selectorName in @[@"workflowIdentifier", @"identifier", @"persistentIdentifier", @"recordIdentifier", @"uniqueIdentifier"]) { id value = ABMCInvoke(workflow, selectorName); if ([value isKindOfClass:[NSString class]] && [value length]) { identifier = value; break; } }
                        [self addName:name identifier:identifier into:results];
                    }
                }
            }
            if (results.count) return;
        }
    } @catch (NSException *exception) {}
}

- (void)readWorkflowDatabase:(NSString *)path into:(NSMutableDictionary *)results {
    sqlite3 *db=NULL; if(sqlite3_open_v2(path.fileSystemRepresentation,&db,SQLITE_OPEN_READONLY,NULL)!=SQLITE_OK){if(db)sqlite3_close(db);return;}
    sqlite3_stmt *tables=NULL;
    if(sqlite3_prepare_v2(db,"SELECT name FROM sqlite_master WHERE type='table'",-1,&tables,NULL)==SQLITE_OK) {
        while(sqlite3_step(tables)==SQLITE_ROW) {
            const char *raw=(const char *)sqlite3_column_text(tables,0); if(!raw)continue; NSString *table=[NSString stringWithUTF8String:raw];
            NSString *lower=table.lowercaseString; if([table hasPrefix:@"sqlite_"]||(![lower containsString:@"workflow"]&&! [lower containsString:@"shortcut"]))continue;
            NSString *escaped=[table stringByReplacingOccurrencesOfString:@"\"" withString:@"\"\""]; sqlite3_stmt *columns=NULL;
            NSString *nameColumn=nil,*idColumn=nil; NSString *pragma=[NSString stringWithFormat:@"PRAGMA table_info(\"%@\")",escaped];
            if(sqlite3_prepare_v2(db,pragma.UTF8String,-1,&columns,NULL)==SQLITE_OK) while(sqlite3_step(columns)==SQLITE_ROW) {
                const char *columnText=(const char *)sqlite3_column_text(columns,1); if(!columnText)continue; NSString *column=[NSString stringWithUTF8String:columnText],*field=column.lowercaseString;
                if(!nameColumn&&([field containsString:@"name"]||[field containsString:@"title"]))nameColumn=column;
                if(!idColumn&&([field containsString:@"workflowidentifier"]||[field containsString:@"workflowid"]||[field containsString:@"uuid"]||[field isEqualToString:@"identifier"]||[field isEqualToString:@"zidentifier"]))idColumn=column;
            }
            if(columns)sqlite3_finalize(columns); if(!nameColumn||!idColumn)continue;
            NSString *query=[NSString stringWithFormat:@"SELECT \"%@\",\"%@\" FROM \"%@\" WHERE \"%@\" IS NOT NULL",[nameColumn stringByReplacingOccurrencesOfString:@"\"" withString:@"\"\""],[idColumn stringByReplacingOccurrencesOfString:@"\"" withString:@"\"\""],escaped,[nameColumn stringByReplacingOccurrencesOfString:@"\"" withString:@"\"\""]];
            sqlite3_stmt *rows=NULL; if(sqlite3_prepare_v2(db,query.UTF8String,-1,&rows,NULL)!=SQLITE_OK)continue;
            while(sqlite3_step(rows)==SQLITE_ROW) { const char *nameText=(const char *)sqlite3_column_text(rows,0); NSString *name=nameText?[NSString stringWithUTF8String:nameText]:nil; [self addName:name identifier:ABMCUUIDFromColumn(rows,1) into:results]; }
            sqlite3_finalize(rows);
        }
        sqlite3_finalize(tables);
    }
    sqlite3_close(db);
}

- (void)readWorkflowFilesBelow:(NSURL *)base into:(NSMutableDictionary *)results {
    NSDirectoryEnumerator *enumerator=[[NSFileManager defaultManager] enumeratorAtURL:base includingPropertiesForKeys:nil options:NSDirectoryEnumerationSkipsHiddenFiles errorHandler:nil]; NSUInteger seen=0;
    for(NSURL *url in enumerator) {
        if(![[url.pathExtension lowercaseString] isEqualToString:@"shortcut"]||seen++>100)continue;
        NSData *data=[NSData dataWithContentsOfURL:url]; id object=data?[NSPropertyListSerialization propertyListWithData:data options:NSPropertyListImmutable format:nil error:nil]:nil;
        if([object isKindOfClass:[NSDictionary class]]) [self addName:object[@"WFWorkflowName"]?:object[@"name"] identifier:object[@"WFWorkflowIdentifier"]?:object[@"identifier"] into:results];
    }
}

- (void)reloadShortcuts {
    NSMutableDictionary *results=[NSMutableDictionary dictionary];
    [self readWorkflowKitInto:results];
    NSArray *paths=[self databasePaths];
    for(NSString *path in paths) [self readWorkflowDatabase:path into:results];
    // Exported .shortcut files are a secondary source; the database remains authoritative.
    for(NSString *path in paths) [self readWorkflowFilesBelow:[NSURL fileURLWithPath:[path stringByDeletingLastPathComponent]] into:results];
    _shortcuts=[[results allValues] sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *a,NSDictionary *b){return[a[@"name"] localizedCaseInsensitiveCompare:b[@"name"]];}]; [self.tableView reloadData];
}

- (NSArray *)visibleShortcuts { if(!_query.length)return _shortcuts?:@[]; NSPredicate *p=[NSPredicate predicateWithBlock:^BOOL(NSDictionary *item,NSDictionary *bindings){return[item[@"name"] localizedCaseInsensitiveContainsString:self->_query]||[item[@"identifier"] localizedCaseInsensitiveContainsString:self->_query];}]; return[_shortcuts filteredArrayUsingPredicate:p]; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return self.visibleShortcuts.count?:1; }
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)path {
    NSArray *items=self.visibleShortcuts; UITableViewCell *cell=[tableView dequeueReusableCellWithIdentifier:@"ShortcutCell"]?:[[UITableViewCell alloc]initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"ShortcutCell"];
    if(!items.count){cell.imageView.image=ABMCTintedIcon(@"exclamationmark.circle",UIColor.secondaryLabelColor);cell.textLabel.text=@"未读取到快捷指令";cell.detailTextLabel.text=@"请确认快捷指令 App 已打开过一次后刷新";cell.selectionStyle=UITableViewCellSelectionStyleNone;return cell;}
    NSDictionary *item=items[path.row];cell.selectionStyle=UITableViewCellSelectionStyleDefault;cell.imageView.image=ABMCTintedIcon(@"square.stack.3d.up.fill",UIColor.systemBlueColor);cell.textLabel.font=[UIFont systemFontOfSize:17];cell.detailTextLabel.font=[UIFont systemFontOfSize:13];cell.textLabel.text=item[@"name"];cell.detailTextLabel.text=item[@"identifier"];
    NSString *action=[NSString stringWithFormat:@"shortcutid:%@|%@",item[@"identifier"],item[@"name"]];CFStringRef current=(CFStringRef)CFPreferencesCopyAppValue((__bridge CFStringRef)_preferenceKey,ABMCDomain);cell.accessoryType=current&&[(__bridge NSString*)current isEqualToString:action]?UITableViewCellAccessoryCheckmark:UITableViewCellAccessoryNone;if(current)CFRelease(current);return cell;
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)path { NSArray*items=self.visibleShortcuts;if(!items.count)return;NSDictionary*item=items[path.row];NSString*action=[NSString stringWithFormat:@"shortcutid:%@|%@",item[@"identifier"],item[@"name"]];CFPreferencesSetAppValue((__bridge CFStringRef)_preferenceKey,(__bridge CFPropertyListRef)action,ABMCDomain);CFPreferencesAppSynchronize(ABMCDomain);CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),ABMCChanged,NULL,NULL,YES);[self.navigationController popViewControllerAnimated:YES]; }
- (void)searchBar:(UISearchBar *)searchBar textDidChange:(NSString *)text {_query=[text copy]?:@"";[self.tableView reloadData];}
@end
