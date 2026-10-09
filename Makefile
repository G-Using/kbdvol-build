TARGET := iphone:clang:16.5:14.0
ARCHS = arm64 arm64e
THEOS_PACKAGE_SCHEME = rootless
FINALPACKAGE = 1

include $(THEOS)/makefiles/common.mk

SUBPROJECTS += tweak prefs
include $(THEOS_MAKE_PATH)/aggregate.mk

# 显式 ldid 签名（RootHide 下必做）
before-package::
	find $(THEOS_STAGING_DIR) -name '*.dylib' -type f | while read f; do ldid -S "$$f" 2>/dev/null || true; done