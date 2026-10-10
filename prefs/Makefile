include $(THEOS)/makefiles/common.mk

BUNDLE_NAME = KbdVolPrefs

# 面板已改为继承 UIViewController（不继承 PSListController），
# 因此不再需要 Preferences 私有框架 —— 少一个链接依赖，少一个失败点。
KbdVolPrefs_FILES = RootController.m
KbdVolPrefs_CFLAGS = -fobjc-arc -Wall -I../shared
KbdVolPrefs_FRAMEWORKS = UIKit
KbdVolPrefs_INSTALL_PATH = /Library/PreferenceBundles

include $(THEOS_MAKE_PATH)/bundle.mk