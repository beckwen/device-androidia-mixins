ifeq ($(TARGET_PREBUILT_KERNEL), true)
ifeq ($(TARGET_BUILD_VARIANT), user)
PREBUILT_KERNEL_ROOT := vendor/intel/utils_priv/kernel/prebuilts/6.6/{{{prebuilt_kernel_target}}}/user
else
PREBUILT_KERNEL_ROOT := vendor/intel/utils_priv/kernel/prebuilts/6.6/{{{prebuilt_kernel_target}}}/userdebug
endif
endif

TARGET_KERNEL_CLANG_VERSION := r530567
CLANG_PREBUILTS_PATH := $(abspath $(INTEL_PATH_DEVICE)/../../../prebuilts/clang)

ifneq ($(TARGET_KERNEL_CLANG_VERSION),)
    # Find the clang-* directory containing the specified version
    KERNEL_CLANG_VERSION := $(shell find $(CLANG_PREBUILTS_PATH)/host/$(HOST_OS)-x86/ -name AndroidVersion.txt -exec grep -l $(TARGET_KERNEL_CLANG_VERSION) "{}" \; | sed -e 's|/AndroidVersion.txt$$||g;s|^.*/||g')
else
    # Only set the latest version of clang if TARGET_KERNEL_CLANG_VERSION hasn't been set by the device con    fig
    KERNEL_CLANG_VERSION := $(shell ls -d $(CLANG_PREBUILTS_PATH)/host/$(HOST_OS)-x86/clang-* | xargs -n 1     basename | tail -1)
endif
TARGET_KERNEL_CLANG_PATH ?= $(CLANG_PREBUILTS_PATH)/host/$(HOST_OS)-x86/$(KERNEL_CLANG_VERSION)/bin
KERNEL_CLANG_TRIPLE ?= CLANG_TRIPLE=x86_64-linux-gnu-
KERNEL_CC ?= CC="$(ccache) $(TARGET_KERNEL_CLANG_PATH)/clang"

LOCAL_KERNEL_PATH := $(PRODUCT_OUT)/obj/kernel
KERNEL_INSTALL_MOD_PATH := .
LOCAL_KERNEL := $(LOCAL_KERNEL_PATH)/arch/x86/boot/{{{binary_name}}}
LOCAL_KERNEL_MODULE_TREE_PATH := $(LOCAL_KERNEL_PATH)/lib/modules
KERNELRELEASE := $(shell cat $(LOCAL_KERNEL_PATH)/include/config/kernel.release)

KERNEL_CCACHE := $(realpath $(CC_WRAPPER))

#remove time_macros from ccache options, it breaks signing process
KERNEL_CCSLOP := $(filter-out time_macros,$(subst $(comma), ,$(CCACHE_SLOPPINESS)))
KERNEL_CCSLOP := $(subst $(space),$(comma),$(KERNEL_CCSLOP))

{{#build_dtbs}}
BUILD_DTBS := true
BOARD_DTB := $(LOCAL_KERNEL_PATH)/{{{board_dtb}}}
DTB ?= $(BOARD_DTB)
{{/build_dtbs}}

ifeq ($(BASE_LTS2023_CHROMIUM_KERNEL), true)
  LOCAL_KERNEL_SRC := {{{lts2023_chromium_src_path}}}
  KERNEL_CONFIG_PATH := $(TARGET_DEVICE_DIR)/{{{lts2023_chromium_cfg_path}}}
else ifeq ($(BASE_LINUX_INTEL_LTS2023_KERNEL), true)
  LOCAL_KERNEL_SRC := {{{linux_intel_lts2023_src_path}}}
  KERNEL_CONFIG_PATH := $(TARGET_DEVICE_DIR)/{{{linux_intel_lts2023_cfg_path}}}
  ENABLE_I915_OOT_MODULE_LOADING := true
else ifeq ($(BASE_LTS2024_ANDROID_KERNEL), true)
  LOCAL_KERNEL_SRC := {{{lts2024_android_src_path}}}
  KERNEL_CONFIG_PATH := $(TARGET_DEVICE_DIR)/{{{lts2024_android_cfg_path}}}
else
  LOCAL_KERNEL_SRC := {{{src_path}}}
  EXT_MODULES := {{{external_modules}}}
  DEBUG_MODULES := {{{debug_modules}}}
  {{#cfg_path}}
  KERNEL_CONFIG_PATH := $(TARGET_DEVICE_DIR)/{{cfg_path}}
  {{/cfg_path}}
  {{^cfg_path}}
  KERNEL_CONFIG_PATH := $(LOCAL_KERNEL_SRC)/arch/x86/configs
  {{/cfg_path}}
endif

EXTMOD_SRC := ../modules
EXTERNAL_MODULES := $(EXT_MODULES)

KERNEL_DEFCONFIG := $(KERNEL_CONFIG_PATH)/$(TARGET_KERNEL_ARCH)_{{{kdefconfig}}}defconfig
ifneq ($(TARGET_BUILD_VARIANT), user)
  KERNEL_DEBUG_DIFFCONFIG += $(wildcard $(KERNEL_CONFIG_PATH)/debug_diffconfig)
  ifneq ($(KERNEL_DEBUG_DIFFCONFIG),)
    KERNEL_DIFFCONFIG += $(KERNEL_DEBUG_DIFFCONFIG)
  else
    KERNEL_DEFCONFIG := $(LOCAL_KERNEL_SRC)/arch/x86/configs/$(TARGET_KERNEL_ARCH)_{{{kdefconfig}}}debug_defconfig
  endif
  EXTERNAL_MODULES := $(EXT_MODULES) $(DEBUG_MODULES)
endif # variant not eq user

KERNEL_CONFIG := $(LOCAL_KERNEL_PATH)/.config

ifeq ($(TARGET_BUILD_VARIANT), eng)
  KERNEL_ENG_DIFFCONFIG := $(wildcard $(KERNEL_CONFIG_PATH)/eng_diffconfig)
  ifneq ($(KERNEL_ENG_DIFFCONFIG),)
    KERNEL_DIFFCONFIG += $(KERNEL_ENG_DIFFCONFIG)
  endif
endif

KERNEL_MAKE_OPTIONS = \
    SHELL=/bin/bash \
    -C $(LOCAL_KERNEL_SRC) \
    O=$(abspath $(LOCAL_KERNEL_PATH)) \
    ARCH=$(TARGET_KERNEL_ARCH) \
    INSTALL_MOD_PATH=$(KERNEL_INSTALL_MOD_PATH) \
    CROSS_COMPILE="x86_64-linux-androidkernel-" \
    CCACHE_SLOPPINESS=$(KERNEL_CCSLOP) \
    $(KERNEL_CLANG_TRIPLE) \
    $(KERNEL_CC)

KERNEL_MAKE_OPTIONS += \
    EXTRA_FW="$(_EXTRA_FW_)" \
    EXTRA_FW_DIR="$(abspath $(PRODUCT_OUT)/vendor/firmware)"

KERNEL_MAKE_OPTIONS += \
    LLVM=1 \
    HOSTLDFLAGS=-fuse-ld=lld \

KERNEL_BRANCH = {{{branch}}}
KERNEL_KMI_GENERATION = {{{kmi_generation}}}
KERNEL_MAKE_OPTIONS += \
    BRANCH=$(KERNEL_BRANCH) \
    KMI_GENERATION=$(KERNEL_KMI_GENERATION)

{{#more_modules}}
KERNEL_MODULES_DIFFCONFIG += $(wildcard $(KERNEL_CONFIG_PATH)/modules_diffconfig)
ifneq ($(KERNEL_MODULES_DIFFCONFIG),)
    KERNEL_DIFFCONFIG += $(KERNEL_MODULES_DIFFCONFIG)
endif
{{/more_modules}}

KERNEL_CONFIG_DEPS = $(strip $(KERNEL_DEFCONFIG) $(KERNEL_DIFFCONFIG))

CHECK_CONFIG_SCRIPT := $(LOCAL_KERNEL_SRC)/scripts/diffconfig
CHECK_CONFIG_LOG :=  $(LOCAL_KERNEL_PATH)/.config.check

KERNEL_DEPS := $(shell find $(LOCAL_KERNEL_SRC) \( -name *.git -prune \) -o -print )

KERNEL_MAKE_CMD:= \
      PATH="$(PWD)/prebuilts/build-tools/linux-x86/bin:$(TARGET_KERNEL_CLANG_PATH):$(PWD)/prebuilts/gcc/linux-x86/host/x86_64-linux-glibc2.17-4.8/x86_64-linux/bin:$$PATH" \
      make -j24

# Before building final defconfig with debug diffconfigs
# Check that base defconfig is correct. Check is performed
# by comparing generated .config with .config.old if it exists.
# On incremental build, remove the old .config.old before checking.
# If differences are observed, display a help message
# and stop kernel build.
# If a .config is already present, save it before processing
# the check and restore it at the end
$(CHECK_CONFIG_LOG): $(KERNEL_DEFCONFIG) $(KERNEL_DEPS)
	$(hide) mkdir -p $(@D)
	-$(hide) [[ -e $(KERNEL_CONFIG) ]] && mv -f $(KERNEL_CONFIG) $(KERNEL_CONFIG).save
	$(hide) rm -f $(KERNEL_CONFIG).old
	$(hide) cat $< > $(KERNEL_CONFIG)
	$(hide) $(KERNEL_MAKE_CMD) $(KERNEL_MAKE_OPTIONS) olddefconfig
	$(hide) if [[ -e  $(KERNEL_CONFIG).old ]] ; then \
	  $(CHECK_CONFIG_SCRIPT) $(KERNEL_CONFIG).old $(KERNEL_CONFIG) > $@ ;  fi;
	-$(hide) [[ -e $(KERNEL_CONFIG).save ]] && mv -f $(KERNEL_CONFIG).save $(KERNEL_CONFIG)
	$(hide) if [[ -s $@ ]] ; then \
	  echo "CHECK KERNEL DEFCONFIG FATAL ERROR :" ; \
	  echo "Kernel config copied from $(KERNEL_DEFCONFIG) has some config issue." ; \
	  echo "Final '.config' and '.config.old' differ. This should never happen." ; \
	  echo "Observed diffs are :" ; \
	  cat $@ ; \
	  echo "Root cause is probably that a dependancy declared in Kconfig is not respected" ; \
	  echo "or config was added in Kconfig but value not explicitly added to defconfig." ; \
	  echo "Recommanded method to generate defconfig is menuconfig tool instead of manual edit." ; \
	  exit 1;  fi;

.PHONY: menuconfig xconfig gconfig

menuconfig xconfig gconfig: $(CHECK_CONFIG_LOG)
	$(hide) xterm -e $(KERNEL_MAKE_CMD) $(KERNEL_MAKE_OPTIONS) $@
	$(hide) cp -f $(KERNEL_CONFIG) $(KERNEL_DEFCONFIG)
	@echo ===========
	@echo $(KERNEL_DEFCONFIG) has been modified !
	@echo ===========

$(KERNEL_CONFIG): $(KERNEL_CONFIG_DEPS) | $(CHECK_CONFIG_LOG)
	$(hide) cat $(KERNEL_CONFIG_DEPS) > $@
	@echo "Generating Kernel configuration, using $(KERNEL_CONFIG_DEPS)"
	$(hide) $(KERNEL_MAKE_CMD) $(KERNEL_MAKE_OPTIONS) olddefconfig </dev/null

# BOARD_KERNEL_CONFIG_FILE and BOARD_KERNEL_VERSION can be used to override the values extracted
# from INSTALLED_KERNEL_TARGET.
BOARD_KERNEL_CONFIG_FILE = $(KERNEL_CONFIG)
BOARD_KERNEL_VERSION = $(shell cat $(KERNEL_DEFCONFIG) | sed -nr 's|.*([0-9]+[.][0-9]+[.][0-9]+)(-rc[1-9])? Kernel Configuration.*|\1|p')

$(PRODUCT_OUT)/kernel: $(LOCAL_KERNEL) $(LOCAL_KERNEL_PATH)/copy_modules
	$(hide) cp $(LOCAL_KERNEL) $@

{{#modules_in_bootimg}}
# kernel modules must be copied before ramdisk is generated
$(PRODUCT_OUT)/ramdisk.img: $(LOCAL_KERNEL_PATH)/copy_modules
{{/modules_in_bootimg}}
{{^modules_in_bootimg}}
# kernel modules must be copied before vendorimage is generated
$(PRODUCT_OUT)/vendor.img: $(LOCAL_KERNEL_PATH)/copy_modules
{{/modules_in_bootimg}}

# Copy modules in directory pointed by $(KERNEL_MODULES_ROOT)
# First copy modules keeping directory hierarchy lib/modules/`uname-r`for libkmod
# Second, create flat hierarchy for insmod linking to previous hierarchy
$(LOCAL_KERNEL_PATH)/copy_modules: $(LOCAL_KERNEL)
	@echo Copy modules from $(LOCAL_KERNEL_PATH)/lib/modules/$(KERNELRELEASE) into $(PRODUCT_OUT)/$(KERNEL_MODULES_ROOT)
ifneq ($(TARGET_PREBUILT_KERNEL), true)
	$(hide) rm -rf $(PRODUCT_OUT)/$(KERNEL_MODULES_ROOT)
	$(hide) rm -rf $(TARGET_RECOVERY_ROOT_OUT)/$(KERNEL_MODULES_ROOT)
	$(hide) mkdir -p $(PRODUCT_OUT)/$(KERNEL_MODULES_ROOT)
	$(hide) cd $(LOCAL_KERNEL_PATH)/lib/modules/$(KERNELRELEASE) && for f in `find . -name '*.ko' -or -name 'modules.*'`; do \
		cp $$f $(PWD)/$(PRODUCT_OUT)/$(KERNEL_MODULES_ROOT)/$$(basename $$f) || exit 1; \
		mkdir -p $(PWD)/$(PRODUCT_OUT)/$(KERNEL_MODULES_ROOT)/$(KERNELRELEASE)/$$(dirname $$f) ; \
		ln -s /$(KERNEL_MODULES_ROOT_PATH)/$$(basename $$f) $(PWD)/$(PRODUCT_OUT)/$(KERNEL_MODULES_ROOT)/$(KERNELRELEASE)/$$f || exit 1; \
		done
endif
	$(hide) cd $(LOCAL_KERNEL_PATH)/lib/modules/$(KERNELRELEASE) && for f in `find . -name 'compat.ko'`; do \
		cp $$f $(PWD)/$(PRODUCT_OUT)/vendor/firmware/i915/ || exit 1; \
		done
	$(hide) cd $(LOCAL_KERNEL_PATH)/lib/modules/$(KERNELRELEASE) && for f in `find . -name 'intel_vsec.ko'`; do \
		cp $$f $(PWD)/$(PRODUCT_OUT)/vendor/firmware/i915/ || exit 1; \
		done
	$(hide) cd $(LOCAL_KERNEL_PATH)/lib/modules/$(KERNELRELEASE) && for f in `find . -name 'i915_ag.ko'`; do \
		cp $$f $(PWD)/$(PRODUCT_OUT)/vendor/firmware/i915/ || exit 1; \
		done
	$(hide) rm -rf $(PWD)/$(PRODUCT_OUT)/obj/kernel/drivers/base/firmware_loader
	$(KERNEL_MAKE_CMD) $(KERNEL_MAKE_OPTIONS)
	$(hide) touch $@
#usb-init for recovery
	$(hide) mkdir -p $(TARGET_RECOVERY_ROOT_OUT)/$(KERNEL_MODULES_ROOT)
	$(hide) for f in dwc3.ko dwc3-pci.ko xhci-hcd.ko xhci-pci.ko; do \
		find $(LOCAL_KERNEL_PATH)/lib/modules/ -name $$f -exec cp {} $(TARGET_RECOVERY_ROOT_OUT)/$(KERNEL_MODULES_ROOT)/ \; ;\
		done
ifneq ($(BASE_LTS2024_ANDROID_KERNEL), true)
ifeq ($(TARGET_PREBUILT_KERNEL), true)
	echo "Copying mei modules from prebuilt"
#mei for recovery
	$(hide) mkdir -p $(TARGET_RECOVERY_ROOT_OUT)/$(KERNEL_MODULES_ROOT)
	$(hide) for f in mei.ko mei-me.ko mei-txe.ko mei-gsc.ko mei_pxp.ko mei_hdcp.ko; do \
		find $(PREBUILT_KERNEL_ROOT)/vendor_dlkm/ -name $$f -exec cp {} $(TARGET_RECOVERY_ROOT_OUT)/$(KERNEL_MODULES_ROOT)/ \; ;\
		done
	$(hide) cp $(PRODUCT_OUT)/obj/modules/intel-gpu-i915-backports/compat/compat.ko $(PRODUCT_OUT)/vendor_dlkm/lib/modules/
	$(hide) cp $(PRODUCT_OUT)/obj/modules/intel-gpu-i915-backports/drivers/gpu/drm/i915/i915_ag.ko $(PRODUCT_OUT)/vendor_dlkm/lib/modules/
	$(hide) cp $(PRODUCT_OUT)/obj/modules/intel-gpu-i915-backports/drivers/platform/x86/intel/intel_vsec.ko $(PRODUCT_OUT)/vendor_dlkm/lib/modules/
	rm -rf out/target/product/base_aaos/obj/kernel
	rm -rf out/target/product/base_aaos/obj/modules
else
	echo "Copying mei modules from legacy kernel"
#mei for recovery
	$(hide) for f in mei.ko mei-me.ko mei-txe.ko mei-gsc.ko mei_pxp.ko mei_hdcp.ko; do \
		find $(LOCAL_KERNEL_PATH)/lib/modules/ -name $$f -exec cp {} $(TARGET_RECOVERY_ROOT_OUT)/$(KERNEL_MODULES_ROOT)/ \; ;\
		done
endif
endif

{{#camera_cos_hack}}
ifeq ($(KERNEL_MODULES_ROOT),vendor/lib/modules)
	$(hide) mkdir -p $(PRODUCT_OUT)/root/vendor/lib/modules/
	$(hide) for f in atomisp-css2401a0_v21.ko videobuf-core.ko videobuf-vmalloc.ko; do \
		find $(LOCAL_KERNEL_PATH)/lib/modules/ -name $$f -exec cp {} $(PRODUCT_OUT)/root/vendor/lib/modules/ \; ;\
		done

$(PRODUCT_OUT)/ramdisk.img: $(LOCAL_KERNEL_PATH)/copy_modules
endif
{{/camera_cos_hack}}

$(LOCAL_KERNEL): $(MINIGZIP) $(KERNEL_CONFIG) $(BOARD_DTB) $(KERNEL_DEPS)
	$(KERNEL_MAKE_CMD) $(KERNEL_MAKE_OPTIONS)
	$(KERNEL_MAKE_CMD) $(KERNEL_MAKE_OPTIONS) modules
	$(KERNEL_MAKE_CMD) $(KERNEL_MAKE_OPTIONS) INSTALL_MOD_STRIP=1 modules_install
{{#build_dtbs}}
	cp $(LOCAL_KERNEL_PATH)/scripts/dtc/dtc $(LOCAL_KERNEL_PATH)
{{/build_dtbs}}


# disable the modules built in parallel due to some modules symbols has dependency,
# and module install depmod need they be installed one at a time.

PREVIOUS_KERNEL_MODULE := $(LOCAL_KERNEL)

define bld_external_module

$(eval MODULE_DEPS_$(2) := $(shell find kernel/modules/$(1) \( -name *.git -prune \) -o -print ))

$(LOCAL_KERNEL_PATH)/build_$(2): $(LOCAL_KERNEL) $(MODULE_DEPS_$(2)) $(PREVIOUS_KERNEL_MODULE)
	@echo BUILDING $(1)
	@mkdir -p $(LOCAL_KERNEL_PATH)/../modules/$(1)
	$(hide) $(KERNEL_MAKE_CMD) $$(KERNEL_MAKE_OPTIONS) M=$(EXTMOD_SRC)/$(1) V=1 $(ADDITIONAL_ARGS_$(subst /,_,$(1))) modules
	@touch $$(@)

$(LOCAL_KERNEL_PATH)/install_$(2): $(LOCAL_KERNEL_PATH)/build_$(2) $(PREVIOUS_KERNEL_MODULE)
	@echo INSTALLING $(1)
	$(hide) $(KERNEL_MAKE_CMD) $$(KERNEL_MAKE_OPTIONS) M=$(EXTMOD_SRC)/$(1) INSTALL_MOD_STRIP=1 modules_install
	@touch $$(@)

$(LOCAL_KERNEL_PATH)/copy_modules: $(LOCAL_KERNEL_PATH)/install_$(2)

$(eval PREVIOUS_KERNEL_MODULE := $(LOCAL_KERNEL_PATH)/install_$(2))
endef

{{#use_bcmdhd}}
EXTERNAL_MODULES += bcm43xx/{{{extmod_platform}}} bcm43xx/{{{extmod_platform}}}_pcie
ADDITIONAL_ARGS_bcm43xx_{{{extmod_platform}}} := CONFIG_BCM43241=m CONFIG_BCMDHD=m CONFIG_DHD_USE_SCHED_SCAN=y CONFIG_BCMDHD_PCIE=  CONFIG_BCMDHD_SDIO=y
ADDITIONAL_ARGS_bcm43xx_{{{extmod_platform}}}_pcie := CONFIG_BCM4356=m CONFIG_BCMDHD=m CONFIG_DHD_USE_SCHED_SCAN=y CONFIG_BCMDHD_PCIE=y CONFIG_BCMDHD_SDIO=
{{/use_bcmdhd}}

# Check external module path
$(foreach m,$(EXTERNAL_MODULES),$(if $(findstring .., $(m)), $(error $(m): All external kernel modules should be put under kernel/modules folder)))

$(foreach m,$(EXTERNAL_MODULES),$(eval $(call bld_external_module,$(m),$(subst /,_,$(m)))))

{{#build_dtbs}}
$(BOARD_DTB): $(KERNEL_CONFIG)
	$(KERNEL_MAKE_CMD) $(KERNEL_MAKE_OPTIONS) dtbs
	cp $(LOCAL_KERNEL_PATH)/arch/x86/boot/dts/{{{board_dtb}}} $@
{{/build_dtbs}}

{{#build_dtbs}}
define board_dtb_per_variant
BOARD_DTB.$(1) := $(LOCAL_KERNEL_PATH)/$$(BOARD_DTB_FILE.$(1))

ifneq ({{{board_dtb}}}, $$(BOARD_DTB_FILE.$(1)))
$$(BOARD_DTB.$(1)): $(BOARD_DTB)
	cp $(LOCAL_KERNEL_PATH)/arch/x86/boot/dts/$$(BOARD_DTB_FILE.$(1)) $$@
endif
endef

$(foreach v,$(BOARD_DTB_VARIANTS),$(eval $(call board_dtb_per_variant,$(v))))
{{/build_dtbs}}

ifneq ($(BASE_LTS2024_ANDROID_KERNEL), true)
{{#i915_ag_mods_version}}

I915_AG_ADDITIONS_PATH := ../modules/intel-gpu-i915-backports
I915_AG_MODS_SRC_PATH := $(I915_AG_ADDITIONS_PATH)/
I915_AG_MODS_OBJ_PATH := $(LOCAL_KERNEL_PATH)/$(I915_AG_ADDITIONS_PATH)/
I915_AG_MODS_TARGET   := $(LOCAL_KERNEL_PATH)/$(I915_AG_ADDITIONS_PATH)/build_i915_ag_{{{i915_ag_mods_version}}}

$(I915_AG_MODS_TARGET): $(LOCAL_KERNEL)
	@echo BUILDING $(I915_AG_MODS_SRC_PATH)
	$(hide) mkdir -p $(I915_AG_MODS_OBJ_PATH)
	$(hide) $(KERNEL_MAKE_CMD) $(KERNEL_MAKE_OPTIONS) M=$(I915_AG_MODS_SRC_PATH) modules
	$(hide) $(KERNEL_MAKE_CMD) $(KERNEL_MAKE_OPTIONS) M=$(I915_AG_MODS_SRC_PATH) INSTALL_MOD_STRIP=1 modules_install
	@touch $@

$(LOCAL_KERNEL_PATH)/copy_modules: $(I915_AG_MODS_TARGET)

{{/i915_ag_mods_version}}
endif

# Add a kernel target, so "make kernel" will build the kernel
.PHONY: kernel
kernel: $(LOCAL_KERNEL_PATH)/copy_modules $(PRODUCT_OUT)/kernel


