TARGET := iphone:clang:16.5:14.0
ARCHS = arm64 arm64e
THEOS_PACKAGE_SCHEME = rootless
FINALPACKAGE = 1

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = KbdVol

KbdVol_FILES = src/KbdVol.m src/KbdAudio.m
KbdVol_CFLAGS = -fobjc-arc -Wall -Isrc
KbdVol_FRAMEWORKS = UIKit Foundation AVFoundation AudioToolbox

include $(THEOS_MAKE_PATH)/tweak.mk

# ---------------- 设置面板 ----------------
BUNDLE_NAME = KbdVolPrefs
KbdVolPrefs_FILES = src/Prefs/RootController.m
KbdVolPrefs_CFLAGS = -fobjc-arc -Wall -Isrc
KbdVolPrefs_FRAMEWORKS = UIKit
KbdVolPrefs_PRIVATE_FRAMEWORKS = Preferences
KbdVolPrefs_LDFLAGS = -F$(TARGET_PRIVATE_FRAMEWORK_PATH)
KbdVolPrefs_INSTALL_PATH = /Library/PreferenceBundles

include $(THEOS_MAKE_PATH)/bundle.mk

SUBPROJECTS += KbdVolPrefs
include $(THEOS_MAKE_PATH)/aggregate.mk

# 显式 ldid 签名（RootHide 下必做）
before-package::
	find $(THEOS_STAGING_DIR) -name '*.dylib' -type f | while read f; do ldid -S "$$f" 2>/dev/null || true; done