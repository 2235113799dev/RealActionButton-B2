#import "ABMCClickManager.h"
#import "ABMCActionExecutor.h"
#import <objc/runtime.h>
#import <objc/message.h>
#define ABMC_TEST_NOTIFICATION CFSTR("com.huynguyen.actionbuttonmulticlick/testCurrentAction")

static BOOL longPressActive = NO;
static BOOL longPressUsesNativeAction = NO;

static void disableArbiterMultiClick(id buttonInstance) {
    Ivar arbiterIvar = class_getInstanceVariable(object_getClass(buttonInstance), "_buttonArbiter");
    if (!arbiterIvar) return;
    id arbiter = object_getIvar(buttonInstance, arbiterIvar);
    if (!arbiter) return;

    SEL setMaxSel = NSSelectorFromString(@"setMaximumRepeatedPressCount:");
    if ([arbiter respondsToSelector:setMaxSel]) {
        ((void (*)(id, SEL, unsigned long long))objc_msgSend)(arbiter, setMaxSel, 0);
    }
}

static void testCurrentAction(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    CFStringRef value = (CFStringRef)CFPreferencesCopyAppValue(CFSTR("testAction"), CFSTR("com.huynguyen.actionbuttonmulticlick"));
    NSString *action = value ? (__bridge_transfer NSString *)value : nil;
    if (action.length && ![action isEqualToString:@"none"]) [[ABMCActionExecutor sharedExecutor] executeAction:action];
    CFPreferencesSetAppValue(CFSTR("testAction"), NULL, CFSTR("com.huynguyen.actionbuttonmulticlick"));
    CFPreferencesAppSynchronize(CFSTR("com.huynguyen.actionbuttonmulticlick"));
}
static void prefsChanged(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    [[ABMCActionExecutor sharedExecutor] reloadPreferences];
}

// iOS 26+
%hook SBActionHardwareButton

- (void)_configureButtonArbiter {
    %orig;
    disableArbiterMultiClick(self);
}

- (void)performActionsForButtonDown:(id)event {
    if (ABMCPerformingDefaultAction) { %orig; return; }
    [ABMCActionExecutor sharedExecutor].buttonInstance = self;
    [ABMCActionExecutor sharedExecutor].lastDownEvent = event;
    // Only the native long-press configuration enters SpringBoard's genuine
    // down-state machine. Custom single/double actions remain intercepted.
    if ([[ABMCActionExecutor sharedExecutor] usesNativeLongPressAction]) %orig;
}

- (void)performActionsForButtonUp:(id)event {
    if (ABMCPerformingDefaultAction) { %orig; return; }
    if (longPressActive) {
        BOOL shouldPerformNativeButtonUp = longPressUsesNativeAction;
        longPressActive = NO;
        longPressUsesNativeAction = NO;
        if (shouldPerformNativeButtonUp) %orig;
        return;
    }

    [[ABMCClickManager sharedManager] registerClick];
}

- (void)performActionsForButtonLongPress:(id)event {
    if (ABMCPerformingDefaultAction) { %orig; return; }
    longPressActive = YES;
    [[ABMCClickManager sharedManager] cancelPendingClicks];
    longPressUsesNativeAction = ![[ABMCActionExecutor sharedExecutor] executeConfiguredLongPressAction];
    // Default must retain the exact hardware event/state machine. Replaying a
    // synthetic buttonDown here leaves Action Button's native panel inert.
    if (longPressUsesNativeAction) %orig;
}

%end

// iOS 17-18
%hook SBRingerHardwareButton

- (void)_configureButtonArbiter {
    %orig;
    disableArbiterMultiClick(self);
}

- (void)performActionsForButtonDown:(id)event {
    if (ABMCPerformingDefaultAction) { %orig; return; }
    [ABMCActionExecutor sharedExecutor].buttonInstance = self;
    [ABMCActionExecutor sharedExecutor].lastDownEvent = event;
    // Only the native long-press configuration enters SpringBoard's genuine
    // down-state machine. Custom single/double actions remain intercepted.
    if ([[ABMCActionExecutor sharedExecutor] usesNativeLongPressAction]) %orig;
}

- (void)performActionsForButtonUp:(id)event {
    if (ABMCPerformingDefaultAction) { %orig; return; }
    if (longPressActive) {
        BOOL shouldPerformNativeButtonUp = longPressUsesNativeAction;
        longPressActive = NO;
        longPressUsesNativeAction = NO;
        if (shouldPerformNativeButtonUp) %orig;
        return;
    }

    [[ABMCClickManager sharedManager] registerClick];
}

- (void)performActionsForButtonLongPress:(id)event {
    if (ABMCPerformingDefaultAction) { %orig; return; }
    longPressActive = YES;
    [[ABMCClickManager sharedManager] cancelPendingClicks];
    longPressUsesNativeAction = ![[ABMCActionExecutor sharedExecutor] executeConfiguredLongPressAction];
    // Default must retain the exact hardware event/state machine. Replaying a
    // synthetic buttonDown here leaves Action Button's native panel inert.
    if (longPressUsesNativeAction) %orig;
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
