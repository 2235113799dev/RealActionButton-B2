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
/// Builds an app's native long-press shortcut icon using SpringBoardHome.
UIImage *ABMCAppShortcutIconImage(id shortcutItem, NSString *bundleID);
/// Uses Apple's VoiceShortcutClient renderer; returns nil when unavailable.
UIImage *ABMCWorkflowIconImage(NSInteger glyph, long long backgroundColor);

/// B2-only presentation overrides. They never modify apps or Shortcuts data.
NSString *ABMCDisplayTitle(NSString *key, NSString *fallback);
NSString *ABMCDisplayIconToken(NSString *key, NSString *fallback);
void ABMCShowPresentationEditor(UIViewController *controller, NSString *key, NSString *defaultTitle, NSString *defaultIcon, dispatch_block_t completion);
void ABMCClearPresentationOverride(NSString *key);
BOOL ABMCUnifiedIconSizingEnabled(void);
CGFloat ABMCUnifiedIconSize(void);
UIColor *ABMCUnifiedIconColor(void);
NSString *ABMCUnifiedIconColorHex(void);
UIImage *ABMCIconImage(NSString *token);
UIImage *ABMCTintedIcon(NSString *token, UIColor *color);
NSString *ABMCInferLinkIcon(NSString *urlString);
NSString *ABMCApplicationName(NSString *bundleID);
void ABMCApplyLargeIcon(UITableViewCell *cell, UIImage *image);
