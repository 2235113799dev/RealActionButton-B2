TARGET := iphone:clang:16.5:17.0
INSTALL_TARGET_PROCESSES = Preferences
THEOS_PACKAGE_SCHEME = rootless
export ARCHS = arm64 arm64e

BUNDLE_NAME = RealActionButton
$(BUNDLE_NAME)_FILES = ABMCPreferences.m ABMCActionListController.m ABMCBuiltinListController.m ABMCApplicationListController.m ABMCAppShortcutListController.m ABMCShortcutListController.m ABMCLinkListController.m ABMCPresetLinkController.m ABMCUIHelpers.m
$(BUNDLE_NAME)_CFLAGS = -fobjc-arc
$(BUNDLE_NAME)_FRAMEWORKS = UIKit
$(BUNDLE_NAME)_PRIVATE_FRAMEWORKS = Preferences
$(BUNDLE_NAME)_LIBRARIES = sqlite3
$(BUNDLE_NAME)_INSTALL_PATH = /Library/PreferenceBundles

include $(THEOS)/makefiles/common.mk
include $(THEOS_MAKE_PATH)/bundle.mk
