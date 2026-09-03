#import "ABMCPresetLinkController.h"
#import "ABMCUIHelpers.h"

#define Domain CFSTR("com.huynguyen.actionbuttonmulticlick")
#define Changed CFSTR("com.huynguyen.actionbuttonmulticlick/prefsChanged")
typedef struct { NSString *identifier; NSString *title; NSString *icon; } Preset;
static const Preset kPresets[] = {
    {@"wechatScan", @"微信扫码", @"qrcode.viewfinder"}, {@"wechatPay", @"微信付款码", @"creditcard.fill"},
    {@"alipayScan", @"支付宝扫码", @"qrcode.viewfinder"}, {@"alipayPay", @"支付宝付款码", @"creditcard.fill"}
};
@implementation ABMCPresetLinkController { NSString *_key; }
- (instancetype)initWithPreferenceKey:(NSString *)key { if((self=[super initWithStyle:UITableViewStyleInsetGrouped])){_key=[key copy];self.title=@"预设链接";}return self; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section{return sizeof(kPresets)/sizeof(kPresets[0]);}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)path { UITableViewCell *cell=[tableView dequeueReusableCellWithIdentifier:@"Preset"]?:[[UITableViewCell alloc]initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"Preset"];Preset p=kPresets[path.row];ABMCApplyLargeIcon(cell,ABMCTintedIcon(p.icon,UIColor.systemBlueColor));cell.textLabel.font=[UIFont systemFontOfSize:18];cell.textLabel.text=p.title;CFStringRef v=(CFStringRef)CFPreferencesCopyAppValue((__bridge CFStringRef)_key,Domain);cell.accessoryType=v&&[(__bridge NSString*)v isEqualToString:p.identifier]?UITableViewCellAccessoryCheckmark:UITableViewCellAccessoryNone;if(v)CFRelease(v);return cell; }
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)path {NSString *action=kPresets[path.row].identifier;CFPreferencesSetAppValue((__bridge CFStringRef)_key,(__bridge CFPropertyListRef)action,Domain);CFPreferencesAppSynchronize(Domain);CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),Changed,NULL,NULL,YES);[self.navigationController popViewControllerAnimated:YES];}
@end
