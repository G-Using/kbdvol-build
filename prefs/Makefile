include $(THEOS)/makefiles/common.mk

BUNDLE_NAME = KbdVolPrefs

# 面板本体由系统 PSListItemsController 承载（入口 plist 里 items 写全），
# 本类只实现 showDiag action，因此同样不需要 Preferences 私有框架。
KbdVolPrefs_FILES = KbdVolPrefs.m
KbdVolPrefs_CFLAGS = -fobjc-arc -Wall -I../shared
KbdVolPrefs_FRAMEWORKS = UIKit
KbdVolPrefs_INSTALL_PATH = /Library/PreferenceBundles

include $(THEOS_MAKE_PATH)/bundle.mk