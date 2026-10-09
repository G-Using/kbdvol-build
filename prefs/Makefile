include $(THEOS)/makefiles/common.mk

BUNDLE_NAME = KbdVolPrefs

KbdVolPrefs_FILES = RootController.m
KbdVolPrefs_CFLAGS = -fobjc-arc -Wall -I../shared
KbdVolPrefs_FRAMEWORKS = UIKit
KbdVolPrefs_PRIVATE_FRAMEWORKS = Preferences
KbdVolPrefs_LDFLAGS = -F$(TARGET_PRIVATE_FRAMEWORK_PATH)
KbdVolPrefs_INSTALL_PATH = /Library/PreferenceBundles

include $(THEOS_MAKE_PATH)/bundle.mk