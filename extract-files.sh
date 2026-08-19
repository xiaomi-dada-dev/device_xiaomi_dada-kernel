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

if [[ -z "${INPUT}" ]]; then
    usage
fi

if [[ -d "${INPUT}" ]]; then
    MODE="dump"
    DUMP_DIR="$(realpath "${INPUT}")"

    # Validate dump
    for f in boot/kernel vendor_boot.img dtbo.img; do
        if [[ ! -e "${DUMP_DIR}/${f}" ]]; then
            echo "Error: Missing ${f} in ${DUMP_DIR}, is this a complete dump?"
            exit 1
        fi
    done
elif [[ -f "${INPUT}" ]]; then
    MODE="zip"
    for host_cmd in unzip; do
        if ! command -v "${host_cmd}" &>/dev/null; then
            echo "Error: Required host tool '${host_cmd}' not found for ZIP mode."
            exit 1
        fi
    done
else
    usage
fi

# Output directories
for dir in ./images ./images/dtbs; do
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

    cp "${DUMP_DIR}/dtbo.img" "${extract_out}/dtbo.img"
else
    echo "Extracting payload from ${INPUT}"
    unzip -q "${INPUT}" payload.bin -d "${extract_out}"

    echo "Extracting OTA images"
    "${EXTRACT_OTA}" -payload "${extract_out}/payload.bin" -output_dir "${extract_out}" -partitions boot,dtbo,vendor_boot
    rm -f "${extract_out}/payload.bin"

    echo "Extracting boot.img"
    mkdir -p "${extract_out}/boot-out"
    "${UNPACKBOOTIMG}" --boot_img "${extract_out}/boot.img" --out "${extract_out}/boot-out" --format mkbootimg

    echo "Extracting vendor_boot.img"
    mkdir -p "${extract_out}/vendor_boot-out"
    "${UNPACKBOOTIMG}" --boot_img "${extract_out}/vendor_boot.img" --out "${extract_out}/vendor_boot-out" --format mkbootimg
fi

# Extract artifacts

# kernel
echo "Copying the kernel"
cp "${extract_out}/boot-out/kernel" ./images/kernel

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
