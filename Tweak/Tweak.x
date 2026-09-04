#import "ABMCClickManager.h"
#import "ABMCActionExecutor.h"
#import <objc/runtime.h>
#import <objc/message.h>
#define ABMC_TEST_NOTIFICATION CFSTR("com.huynguyen.actionbuttonmulticlick/testCurrentAction")

static BOOL longPressActive = NO;
static BOOL longPressUsesNativeAction = NO;

static void testCurrentAction(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    CFStringRef value = (CFStringRef)CFPreferencesCopyAppValue(CFSTR("testAction"), CFSTR("com.huynguyen.actionbuttonmulticlick"));
    NSString *action = value ? (__bridge_transfer NSString *)value : nil;
    if (action.length && ![action isEqualToString:@"none"]) [[ABMCActionExecutor sharedExecutor] executeAction:action];
    CFPreferencesSetAppValue(CFSTR("testAction"), NULL, CFSTR("com.huynguyen.actionbuttonmulticlick"));
    CFPreferencesAppSynchronize(CFSTR("com.huynguyen.actionbuttonmulticlick"));
}
static void prefsChanged(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    ABMCActionExecutor *executor=[ABMCActionExecutor sharedExecutor];
    [executor reloadPreferences];
}

// iOS 26+
%hook SBActionHardwareButton



- (void)performActionsForButtonDown:(id)event {
    if (ABMCPerformingDefaultAction) { %orig; return; }
    // Keep the real hardware context for a later single/double “系统默认” replay.
    [ABMCActionExecutor sharedExecutor].buttonInstance = self;
    [ABMCActionExecutor sharedExecutor].lastDownEvent = event;
    if ([[ABMCActionExecutor sharedExecutor] usesNativeLongPressAction]) { %orig; return; }
}

- (void)performActionsForButtonUp:(id)event {
    if (ABMCPerformingDefaultAction) { %orig; return; }
    if (longPressActive) {
        BOOL shouldPerformNativeButtonUp = longPressUsesNativeAction;
        longPressActive = NO;
        longPressUsesNativeAction = NO;
        if (shouldPerformNativeButtonUp) %orig;
        [[ABMCActionExecutor sharedExecutor] clearHardwareContext];
        return;
    }

    // If native long press is enabled, SpringBoard received the real down
    // event. It must also receive this short-release to dismiss its assertion
    // / Dynamic Island state; below-long-press releases do not run its action.
    if ([[ABMCActionExecutor sharedExecutor] usesNativeLongPressAction]) %orig;
    [[ABMCClickManager sharedManager] registerClick];
}

- (void)performActionsForButtonLongPress:(id)event {
    if (ABMCPerformingDefaultAction) { %orig; return; }
    longPressActive = YES;
    [[ABMCClickManager sharedManager] cancelPendingClicks];
    if ([[ABMCActionExecutor sharedExecutor] usesNativeLongPressAction]) {
        // The real down event already reached SpringBoard. Do not replay it:
        // native long press gets exactly one down → longPress → up sequence.
        longPressUsesNativeAction = YES;
        %orig;
        return;
    }
    longPressUsesNativeAction = NO;
    [[ABMCActionExecutor sharedExecutor] executeConfiguredLongPressAction];
}

%end

// iOS 17-18
%hook SBRingerHardwareButton



- (void)performActionsForButtonDown:(id)event {
    if (ABMCPerformingDefaultAction) { %orig; return; }
    // Keep the real hardware context for a later single/double “系统默认” replay.
    [ABMCActionExecutor sharedExecutor].buttonInstance = self;
    [ABMCActionExecutor sharedExecutor].lastDownEvent = event;
    if ([[ABMCActionExecutor sharedExecutor] usesNativeLongPressAction]) { %orig; return; }
}

- (void)performActionsForButtonUp:(id)event {
    if (ABMCPerformingDefaultAction) { %orig; return; }
    if (longPressActive) {
        BOOL shouldPerformNativeButtonUp = longPressUsesNativeAction;
        longPressActive = NO;
        longPressUsesNativeAction = NO;
        if (shouldPerformNativeButtonUp) %orig;
        [[ABMCActionExecutor sharedExecutor] clearHardwareContext];
        return;
    }

    // If native long press is enabled, SpringBoard received the real down
    // event. It must also receive this short-release to dismiss its assertion
    // / Dynamic Island state; below-long-press releases do not run its action.
    if ([[ABMCActionExecutor sharedExecutor] usesNativeLongPressAction]) %orig;
    [[ABMCClickManager sharedManager] registerClick];
}

- (void)performActionsForButtonLongPress:(id)event {
    if (ABMCPerformingDefaultAction) { %orig; return; }
    longPressActive = YES;
    [[ABMCClickManager sharedManager] cancelPendingClicks];
    if ([[ABMCActionExecutor sharedExecutor] usesNativeLongPressAction]) {
        // The real down event already reached SpringBoard. Do not replay it:
        // native long press gets exactly one down → longPress → up sequence.
        longPressUsesNativeAction = YES;
        %orig;
        return;
    }
    longPressUsesNativeAction = NO;
    [[ABMCActionExecutor sharedExecutor] executeConfiguredLongPressAction];
}

%end

%ctor {
    [ABMCClickManager sharedManager].clickCallback = ^(ABMCClickType clickType) {
        [[ABMCActionExecutor sharedExecutor] executeActionForClickType:clickType];
    };

    prefsChanged(NULL, NULL, NULL, NULL, NULL);

    CFNotificationCenterAddObserver(
        CFNotificationCenterGetDarwinNotifyCenter(),
        NULL,
        prefsChanged,
        CFSTR("com.huynguyen.actionbuttonmulticlick/prefsChanged"),
        NULL,
        CFNotificationSuspensionBehaviorDeliverImmediately
    );

    CFNotificationCenterAddObserver(
        CFNotificationCenterGetDarwinNotifyCenter(),
        NULL,
        testCurrentAction,
        ABMC_TEST_NOTIFICATION,
        NULL,
        CFNotificationSuspensionBehaviorDeliverImmediately
    );
}
