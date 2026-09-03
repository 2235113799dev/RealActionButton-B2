#import "ABMCLinkListController.h"
#import "ABMCUIHelpers.h"

#define ABMCDomain CFSTR("com.huynguyen.actionbuttonmulticlick")
#define ABMCLinksKey CFSTR("savedLinks")
#define ABMCChanged CFSTR("com.huynguyen.actionbuttonmulticlick/prefsChanged")

static NSString *ABMCNormalizeURL(NSString *value) {
    NSString *url = [value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (!url.length || url.length > 4096 || [url rangeOfCharacterFromSet:[NSCharacterSet controlCharacterSet]].location != NSNotFound) return nil;
    NSURL *parsed = [NSURL URLWithString:url];
    if (!parsed.scheme.length) {
        if ([url rangeOfString:@"."].location == NSNotFound) return nil;
        url = [@"https://" stringByAppendingString:url];
    }
    url = [url stringByReplacingOccurrencesOfString:@" " withString:@"%20"];
    return [NSURL URLWithString:url].scheme.length ? url : nil;
}

@interface ABMCLinkListController () <UISearchBarDelegate>
@end
@implementation ABMCLinkListController {
    NSString *_preferenceKey;
    NSMutableArray *_links;
    NSString *_query;
}
- (instancetype)initWithPreferenceKey:(NSString *)key { if ((self=[super initWithStyle:UITableViewStyleInsetGrouped])) { _preferenceKey=[key copy]; self.title=@"URL"; } return self; }
- (void)viewDidLoad {
    [super viewDidLoad]; _query=@"";
    UIView *header=[[UIView alloc]initWithFrame:CGRectMake(0,0,UIScreen.mainScreen.bounds.size.width,68)];
    UISearchBar *search=[[UISearchBar alloc]initWithFrame:CGRectInset(header.bounds,8,6)]; search.placeholder=@"搜索 URL"; search.delegate=self; [header addSubview:search]; self.tableView.tableHeaderView=header;
    UIBarButtonItem *add=[[UIBarButtonItem alloc]initWithBarButtonSystemItem:UIBarButtonSystemItemAdd target:self action:@selector(addLink)];
    UIBarButtonItem *import=[[UIBarButtonItem alloc]initWithTitle:@"导入" style:UIBarButtonItemStylePlain target:self action:@selector(importClipboard)]; self.navigationItem.rightBarButtonItems=@[add,import]; [self loadLinks];
}
- (void)loadLinks { _links=[NSMutableArray array]; CFPropertyListRef value=CFPreferencesCopyAppValue(ABMCLinksKey,ABMCDomain); if(value&&CFGetTypeID(value)==CFArrayGetTypeID()){for(id item in (__bridge NSArray *)value)if([item isKindOfClass:[NSDictionary class]]&&[item[@"id"] isKindOfClass:[NSString class]]&&[item[@"title"] isKindOfClass:[NSString class]]&&[item[@"url"] isKindOfClass:[NSString class]])[_links addObject:[item mutableCopy]];} if(value)CFRelease(value); }
- (void)saveLinks { CFPreferencesSetAppValue(ABMCLinksKey,(__bridge CFPropertyListRef)_links,ABMCDomain); CFPreferencesAppSynchronize(ABMCDomain); }
- (NSArray *)filteredLinks { if(!_query.length)return _links; NSPredicate*p=[NSPredicate predicateWithBlock:^BOOL(NSDictionary*x,NSDictionary*b){return[x[@"title"] localizedCaseInsensitiveContainsString:self->_query]||[x[@"url"] localizedCaseInsensitiveContainsString:self->_query];}];return[_links filteredArrayUsingPredicate:p]; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section{return self.filteredLinks.count;}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)path { UITableViewCell*c=[tableView dequeueReusableCellWithIdentifier:@"LinkCell"]?:[[UITableViewCell alloc]initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"LinkCell"];NSDictionary*x=self.filteredLinks[path.row];NSString*token=x[@"icon"]?:ABMCInferLinkIcon(x[@"url"]);ABMCApplyLargeIcon(c,ABMCTintedIcon(token,UIColor.systemBlueColor));c.textLabel.font=[UIFont systemFontOfSize:18];c.textLabel.text=x[@"title"];c.detailTextLabel.font=[UIFont systemFontOfSize:13];c.detailTextLabel.text=x[@"url"];CFStringRef v=(CFStringRef)CFPreferencesCopyAppValue((__bridge CFStringRef)_preferenceKey,ABMCDomain);c.accessoryType=v&&[(__bridge NSString*)v isEqualToString:[@"link:" stringByAppendingString:x[@"id"]]]?UITableViewCellAccessoryCheckmark:UITableViewCellAccessoryNone;if(v)CFRelease(v);return c; }
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)path { NSDictionary*x=self.filteredLinks[path.row];NSString*a=[@"link:"stringByAppendingString:x[@"id"]];CFPreferencesSetAppValue((__bridge CFStringRef)_preferenceKey,(__bridge CFPropertyListRef)a,ABMCDomain);CFPreferencesAppSynchronize(ABMCDomain);CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),ABMCChanged,NULL,NULL,YES);[self.navigationController popViewControllerAnimated:YES]; }
- (void)editLink:(NSDictionary *)old {
    UIAlertController *alert=[UIAlertController alertControllerWithTitle:old?@"编辑 URL":@"新增 URL" message:@"第三项可填写 SF Symbol 名称，或应用 Bundle ID。留空会自动识别。" preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField*f){f.placeholder=@"URL 名称";f.text=old[@"title"]; }];
    [alert addTextFieldWithConfigurationHandler:^(UITextField*f){f.placeholder=@"网页地址或 URL Scheme";f.text=old[@"url"];f.autocorrectionType=UITextAutocorrectionTypeNo;f.autocapitalizationType=UITextAutocapitalizationTypeNone;}];
    [alert addTextFieldWithConfigurationHandler:^(UITextField*f){f.placeholder=@"SF 图标名或应用标识符（可选）";f.text=old[@"icon"];f.autocorrectionType=UITextAutocorrectionTypeNo;f.autocapitalizationType=UITextAutocapitalizationTypeNone;}];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"保存" style:UIAlertActionStyleDefault handler:^(UIAlertAction*x){NSString*t=[alert.textFields[0].text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];NSString*u=ABMCNormalizeURL(alert.textFields[1].text);NSString*i=[alert.textFields[2].text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];if(!t.length||t.length>100||!u.length)return;NSMutableDictionary*d=[NSMutableDictionary dictionaryWithDictionary:old?:@{}];if(!d[@"id"])d[@"id"]=NSUUID.UUID.UUIDString;d[@"title"]=t;d[@"url"]=u;d[@"icon"]=i.length?i:ABMCInferLinkIcon(u);NSUInteger n=old?[_links indexOfObject:old]:NSNotFound;if(n==NSNotFound)[_links addObject:d];else _links[n]=d;[self saveLinks];[self.tableView reloadData];}]];
    [self presentViewController:alert animated:YES completion:nil];
}
- (void)addLink{[self editLink:nil];}
- (void)importClipboard { NSString*u=ABMCNormalizeURL(UIPasteboard.generalPasteboard.string);if(!u.length){UIAlertController*a=[UIAlertController alertControllerWithTitle:@"无法导入" message:@"剪贴板中没有有效的 URL 或 URL Scheme。" preferredStyle:UIAlertControllerStyleAlert];[a addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];[self presentViewController:a animated:YES completion:nil];return;}[self editLink:@{ @"id":NSUUID.UUID.UUIDString,@"title":@"导入链接",@"url":u,@"icon":ABMCInferLinkIcon(u)}];}
- (UISwipeActionsConfiguration *)tableView:(UITableView *)tableView trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)path { NSDictionary*x=self.filteredLinks[path.row];UIContextualAction*edit=[UIContextualAction contextualActionWithStyle:UIContextualActionStyleNormal title:@"修改" handler:^(UIContextualAction*a,UIView*v,void(^done)(BOOL)){[self editLink:x];done(YES);}];edit.backgroundColor=UIColor.systemBlueColor;UIContextualAction*clear=[UIContextualAction contextualActionWithStyle:UIContextualActionStyleDestructive title:@"清空" handler:^(UIContextualAction*a,UIView*v,void(^done)(BOOL)){NSString*defaultTitle=x[@"url"]?:@"URL";NSMutableDictionary*d=[x mutableCopy];d[@"title"]=defaultTitle;d[@"icon"]=ABMCInferLinkIcon(d[@"url"]);NSUInteger i=[_links indexOfObject:x];if(i!=NSNotFound)_links[i]=d;[self saveLinks];[self.tableView reloadData];done(YES);}];clear.backgroundColor=UIColor.systemGrayColor;return[UISwipeActionsConfiguration configurationWithActions:@[clear,edit]];}
- (void)searchBar:(UISearchBar *)searchBar textDidChange:(NSString *)text {_query=[text copy]?:@"";[self.tableView reloadData];}
@end
