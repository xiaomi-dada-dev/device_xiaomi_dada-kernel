# device_xiaomi_dada-kernel

Prebuilt kernel and modules for Xiaomi 15 (`dada`).

## Usage

Clone this repository to your Android build tree, ideally:

```text
$ANDROID_ROOT/device/xiaomi/dada-kernel
```

### `BoardConfig.mk`

```make
PREBUILT_PATH := path/to/device_xiaomi_dada-kernel

SYSTEM_DLKM_MODULES_PATH := $(PREBUILT_PATH)/modules/system_dlkm
VENDOR_DLKM_MODULES_PATH := $(PREBUILT_PATH)/modules/vendor_dlkm
RAMDISK_MODULES_PATH := $(PREBUILT_PATH)/modules/vendor_boot

BOARD_SYSTEM_KERNEL_MODULES := $(wildcard $(SYSTEM_DLKM_MODULES_PATH)/*.ko)
BOARD_SYSTEM_KERNEL_MODULES_LOAD := $(patsubst %,$(SYSTEM_DLKM_MODULES_PATH)/%,$(shell cat $(SYSTEM_DLKM_MODULES_PATH)/modules.load))

BOARD_VENDOR_KERNEL_MODULES := $(wildcard $(VENDOR_DLKM_MODULES_PATH)/*.ko)
BOARD_VENDOR_KERNEL_MODULES_LOAD := $(patsubst %,$(VENDOR_DLKM_MODULES_PATH)/%,$(shell cat $(VENDOR_DLKM_MODULES_PATH)/modules.load))
BOARD_VENDOR_KERNEL_MODULES_BLOCKLIST_FILE := $(VENDOR_DLKM_MODULES_PATH)/modules.blocklist

BOARD_VENDOR_RAMDISK_KERNEL_MODULES := $(wildcard $(RAMDISK_MODULES_PATH)/*.ko)
BOARD_VENDOR_RAMDISK_KERNEL_MODULES_LOAD := $(patsubst %,$(RAMDISK_MODULES_PATH)/%,$(shell cat $(RAMDISK_MODULES_PATH)/modules.load))
BOARD_VENDOR_RAMDISK_RECOVERY_KERNEL_MODULES_LOAD := $(patsubst %,$(RAMDISK_MODULES_PATH)/%,$(shell cat $(RAMDISK_MODULES_PATH)/modules.load.recovery))
BOARD_VENDOR_RAMDISK_KERNEL_MODULES_BLOCKLIST_FILE := $(RAMDISK_MODULES_PATH)/modules.blocklist
```

### `device.mk`

```make
PREBUILT_PATH := path/to/device_xiaomi_dada-kernel

PRODUCT_COPY_FILES += $(PREBUILT_PATH)/images/kernel:kernel
```
