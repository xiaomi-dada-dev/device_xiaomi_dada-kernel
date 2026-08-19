#!/bin/bash
#
# Copyright (C) 2026 Naufal Altaf <me@altaf.xyz>
# SPDX-License-Identifier: Apache-2.0
#

set -e

EXTRACT_OTA=../../../prebuilts/extract-tools/linux-x86/bin/ota_extractor
EXTRACT_DTB=../../../prebuilts/misc/linux-x86/libufdt/extract_dtb
UNPACKBOOTIMG=../../../system/tools/mkbootimg/unpack_bootimg.py
INPUT="${1:-}"

# Cleanup
extract_out=""
cleanup() {
    if [[ -n "${extract_out}" && -d "${extract_out}" ]]; then
        rm -rf "${extract_out}"
    fi
}
trap cleanup EXIT INT TERM

usage() {
    echo "Usage: $0 <rom-zip|dump-dir>"
    exit 1
}

# AOSP tools
if [[ ! -f "${UNPACKBOOTIMG}" ]]; then
    echo "Error: ${UNPACKBOOTIMG} not found."
    echo "Ensure you are running from device/xiaomi/dada-kernel within an Android tree."
    exit 1
fi

if [[ ! -f "${EXTRACT_OTA}" ]]; then
    echo "Error: ${EXTRACT_OTA} not found."
    echo "Ensure you are running from device/xiaomi/dada-kernel and have built the ota_extractor target."
    exit 1
fi

if [[ ! -f "${EXTRACT_DTB}" ]]; then
    echo "Error: ${EXTRACT_DTB} not found."
    echo "Ensure you are running from device/xiaomi/dada-kernel within an Android tree."
    exit 1
fi

# Host tools
for host_cmd in unlz4 cpio; do
    if ! command -v "${host_cmd}" &>/dev/null; then
        echo "Error: Required host tool '${host_cmd}' not found in PATH."
        exit 1
    fi
done

if [[ -z "${INPUT}" ]]; then
    usage
fi

if [[ -d "${INPUT}" ]]; then
    MODE="dump"
    DUMP_DIR="$(realpath "${INPUT}")"

    # Validate dump
    for f in boot/kernel vendor_boot.img vendor_dlkm/lib/modules system_dlkm/lib dtbo.img; do
        if [[ ! -e "${DUMP_DIR}/${f}" ]]; then
            echo "Error: Missing ${f} in ${DUMP_DIR}, is this a complete dump?"
            exit 1
        fi
    done
    if ! compgen -G "${DUMP_DIR}/system_dlkm/lib/modules/*" > /dev/null; then
        echo "Error: Missing system_dlkm/lib/modules in ${DUMP_DIR}, is this a complete dump?"
        exit 1
    fi
elif [[ -f "${INPUT}" ]]; then
    MODE="zip"
    for host_cmd in unzip fsck.erofs; do
        if ! command -v "${host_cmd}" &>/dev/null; then
            echo "Error: Required host tool '${host_cmd}' not found for ZIP mode."
            exit 1
        fi
    done
else
    usage
fi

# Output directories
for dir in ./modules/vendor_dlkm ./modules/system_dlkm ./modules/vendor_boot ./images ./images/dtbs; do
    rm -rf "${dir}"
    mkdir -p "${dir}"
done

extract_out="$(TMPDIR=/var/tmp mktemp -d)"
echo "Using ${extract_out} as working directory"

# Acquire artifacts
if [[ "${MODE}" == "dump" ]]; then
    echo "Staging artifacts from dump at ${DUMP_DIR}"

    mkdir -p "${extract_out}/boot-out"
    cp "${DUMP_DIR}/boot/kernel" "${extract_out}/boot-out/kernel"

    echo "Extracting vendor_boot.img"
    mkdir -p "${extract_out}/vendor_boot-out"
    "${UNPACKBOOTIMG}" --boot_img "${DUMP_DIR}/vendor_boot.img" --out "${extract_out}/vendor_boot-out" --format mkbootimg

    ln -s "${DUMP_DIR}/vendor_dlkm" "${extract_out}/vendor_dlkm"
    ln -s "${DUMP_DIR}/system_dlkm" "${extract_out}/system_dlkm"
    cp "${DUMP_DIR}/dtbo.img" "${extract_out}/dtbo.img"
else
    echo "Extracting payload from ${INPUT}"
    unzip -q "${INPUT}" payload.bin -d "${extract_out}"

    echo "Extracting OTA images"
    "${EXTRACT_OTA}" -payload "${extract_out}/payload.bin" -output_dir "${extract_out}" -partitions boot,dtbo,vendor_boot,vendor_dlkm,system_dlkm
    rm -f "${extract_out}/payload.bin"

    echo "Extracting boot.img"
    mkdir -p "${extract_out}/boot-out"
    "${UNPACKBOOTIMG}" --boot_img "${extract_out}/boot.img" --out "${extract_out}/boot-out" --format mkbootimg

    echo "Extracting vendor_boot.img"
    mkdir -p "${extract_out}/vendor_boot-out"
    "${UNPACKBOOTIMG}" --boot_img "${extract_out}/vendor_boot.img" --out "${extract_out}/vendor_boot-out" --format mkbootimg

    echo "Extracting vendor_dlkm.img"
    fsck.erofs --extract="${extract_out}/vendor_dlkm" "${extract_out}/vendor_dlkm.img"

    echo "Extracting system_dlkm.img"
    fsck.erofs --extract="${extract_out}/system_dlkm" "${extract_out}/system_dlkm.img"
fi

# Extract artifacts

# kernel
echo "Copying the kernel"
cp "${extract_out}/boot-out/kernel" ./images/kernel

# vendor_boot
echo "Extracting the ramdisk kernel modules"
ramdisk_out="${extract_out}/vendor_boot-out"
mkdir -p "${ramdisk_out}/ramdisk"
if [[ -f "${ramdisk_out}/vendor_ramdisk00" ]]; then
    unlz4 -f -q "${ramdisk_out}/vendor_ramdisk00" "${ramdisk_out}/vendor_ramdisk"
fi
cpio -i -F "${ramdisk_out}/vendor_ramdisk" -D "${ramdisk_out}/ramdisk" 2>/dev/null || true

find "${ramdisk_out}/ramdisk" \( -name "*.ko" -o -name "modules.load*" -o -name "modules.blocklist" \) \
    -exec cp -t ./modules/vendor_boot/ {} +

# vendor_dlkm
find "${extract_out}/vendor_dlkm/lib" \( -name "*.ko" -o -name "modules.load*" -o -name "modules.blocklist" \) \
    -exec cp -t ./modules/vendor_dlkm/ {} +

# system_dlkm
if [[ -d "${extract_out}/system_dlkm/flatten/lib/modules" ]]; then
    find "${extract_out}/system_dlkm/flatten/lib/modules" \( -name "*.ko" -o -name "modules.load*" -o -name "modules.blocklist" \) \
        -exec cp -t ./modules/system_dlkm/ {} +
else
    find "${extract_out}/system_dlkm/lib/modules" \( -name "*.ko" -o -name "modules.load*" -o -name "modules.blocklist" \) \
        -exec cp -t ./modules/system_dlkm/ {} +
    if [[ -f ./modules/system_dlkm/modules.load ]]; then
        sed -i 's|.*/||' ./modules/system_dlkm/modules.load
    fi
fi

# dtbo / dtbs
echo "Extracting DTBO and DTBs"
mkdir -p "${extract_out}/dtbs"
"${EXTRACT_DTB}" "${extract_out}/vendor_boot-out/dtb" "${extract_out}/dtbs/dtb"

shopt -s nullglob
for dtb in "${extract_out}"/dtbs/dtb "${extract_out}"/dtbs/dtb.*; do
    if [[ "${dtb}" != *.dtb ]]; then
        mv "${dtb}" "${dtb}.dtb"
    fi
done
shopt -u nullglob

dtb_count=$(find "${extract_out}/dtbs" -name "*.dtb" | wc -l)
if [[ ${dtb_count} -eq 0 ]]; then
    echo "Error: No DTBs extracted from the vendor_boot dtb blob"
    exit 1
fi
echo "Extracted ${dtb_count} DTBs"

find "${extract_out}/dtbs" -type f -name "*.dtb" -exec cp -t ./images/dtbs/ {} +
cp -f "${extract_out}/dtbo.img" ./images/dtbo.img

echo "Done"
echo "Extracted files successfully"
