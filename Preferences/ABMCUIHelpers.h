#import <UIKit/UIKit.h>

typedef NS_ENUM(NSInteger, ABMCApplicationKind) {
    ABMCApplicationKindAll = 0,
    ABMCApplicationKindUser,
    ABMCApplicationKindTrollStore,
    ABMCApplicationKindSystem,
};

/// Preferences-only system services. No third-party framework is loaded,
/// bundled, or injected by B2.
NSArray *ABMCInstalledApplications(void);
ABMCApplicationKind ABMCApplicationKindForProxy(id application);
NSString *ABMCBundleIdentifierForApplication(id application);
NSString *ABMCDisplayNameForApplication(id application);
UIImage *ABMCIconImageForBundleID(NSString *bundleID);
UIImage *ABMCIconImageForProxy(id application);
BOOL ABMCApplicationHasRealIcon(id application);
/// Builds an app's native long-press shortcut icon using SpringBoardHome.
/// Uses Apple's VoiceShortcutClient renderer; returns nil when unavailable.
UIImage *ABMCWorkflowIconImage(NSInteger glyph, long long backgroundColor);
/// Reads one saved Shortcut's original icon by UUID (Preferences-only, read-only).
UIImage *ABMCWorkflowIconForIdentifier(NSString *identifier);
/// Compatibility lookup for older name-based saved actions.
UIImage *ABMCWorkflowIconForName(NSString *name);

/// B2-only presentation overrides. They never modify apps or Shortcuts data.
NSString *ABMCDisplayTitle(NSString *key, NSString *fallback);
NSString *ABMCDisplayIconToken(NSString *key, NSString *fallback);
void ABMCShowPresentationEditor(UIViewController *controller, NSString *key, NSString *defaultTitle, NSString *defaultIcon, dispatch_block_t completion);
void ABMCClearPresentationOverride(NSString *key);
/// Installs the common long-press “修改显示 / 清空显示” native action sheet.
void ABMCInstallPresentationLongPress(UITableViewCell *cell, UIViewController *controller, NSString *key, NSString *title, NSString *icon, dispatch_block_t completion);
/// Shared 1–8 action selection, persisted independently of each category UI.
NSArray<NSString *> *ABMCSelectedActions(NSString *preferenceKey);
void ABMCStoreSelectedActions(NSString *preferenceKey, NSArray<NSString *> *actions);
CGFloat ABMCUnifiedIconSize(void);
UIColor *ABMCUnifiedIconColor(void);
NSString *ABMCUnifiedIconColorHex(void);
UIImage *ABMCIconImage(NSString *token);
UIImage *ABMCTintedIcon(NSString *token, UIColor *color);
NSString *ABMCInferLinkIcon(NSString *urlString);
NSString *ABMCApplicationName(NSString *bundleID);
void ABMCApplyLargeIcon(UITableViewCell *cell, UIImage *image);
UIImage *ABMCSelectedActionIcon(NSString *action);
NSString *ABMCShortcutFolderTitle(NSString *action);
