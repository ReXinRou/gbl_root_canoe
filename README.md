# GBL Root Canoe

[中文版](README_zh.md)

`gbl_root_canoe` is an EDK2-based workspace for patching the EFI applications within Qualcomm ABL (Android Bootloader) images. It leverages a GBL (Generic Bootloader Loader) vulnerability to patch the embedded EFI, primarily intended for achieving a **Fake Locked Bootloader** state on Snapdragon 8 Gen 5 / 8 Elite (Gen 5) devices to bypass bootloader unlock detection. The patched EFI is typically flashed into the `efisp` partition.

---

## Builder Guide

This section is for developers who want to compile the toolkits from source.

### Prerequisites
You must be on a **Linux** host to build the project:
- `gcc` / `clang`, `lld`, `make`, `zip`, `python3`
- `liblzma-dev` (for compiling `extractfv`)
- **Android NDK** (Required for `make build_module` to cross-compile tools for Android)
- **MinGW-w64** (`x86_64-w64-mingw32-gcc`, required for `make dist_loader_windows` cross-compilation)

### Build Targets

**Note:** You **do not** need to provide an `abl.img` to build the distributable toolkits or Magisk module. Set the `DIST_NAME` environment variable to name your release ZIP (e.g., `DIST_NAME=my_toolkit make dist_loader`).

- **`make dist_loader`**
  Compiles the patching utilities (`extractfv`, `patch_abl`) for Linux and packages them into a `.zip` in `release/`.

- **`make dist_loader_windows`**
  Similar to `dist_loader`, but cross-compiles the patching utilities into Windows `.exe` programs using MinGW-w64.

- **`make build_module`**
  Cross-compiles the patcher tools for Android using your NDK. Packages them into a Magisk Module zip in `release/`.

- **`make dist`**
  Builds the patched EFI for a specific device model.



---

## User Guide

This section is for end-users using the compiled outputs found in the `release/` directory. For more detailed instructions, please refer to the [Wiki](https://github.com/superturtlee/gbl_root_canoe/wiki).

### 1. Using the Magisk Module (On-Device)

The Magisk module is designed to run directly on your rooted Android device.

**Requirements:**
- Device must be Snapdragon 8 Gen 5 / 8 Elite (Gen 5).
- Bootloader must be unlocked.
- Kernel must NOT have Baseband Guard.

**Installation & Usage:**
When flashing the Magisk module via a root manager (like KernelSU, Magisk, or APatch), the customized script will interact with you using the volume keys:
- **Volume Up (First-time installation):** The script automatically extracts the live `.abl` image, patches it, and flashes the patched file directly to `/dev/block/by-name/efisp`. After this finishes, you must reboot into Recovery mode and **format Data**. Once booted, install this module again (selecting Volume Down the second time) to complete the installation.
- **Volume Down (OTA retention or post-format):** Used for retaining the BL version after an OTA update. Before updating OTA, use the module to automatically downgrade ABL, then reboot the system.

### 2. Using the PC Toolkits (Linux / Windows)

If you downloaded the `dist_loader` or `dist_loader_windows` zip files:
1. Extract the toolkit zip on your PC.
2. Place your device's stock `abl.img` inside the `images/` (or `images\`) directory of the toolkit.
3. **Linux:** Run `bash build.sh` (or `make build`). **Windows:** Run `build.bat`.
4. The scripts will extract, patch, and patch the ABL, outputting the modified file `ABL.efi`. (Check the output logs; if it says "Warning: Failed to patch ABL GBL", the device is not vulnerable and ABL needs to be downgraded).

### 3. Using Pre-patched EFIs
Download a specific release version that contains the phone model or codename in its filename. Use `ABL.efi` from the package to boot or flash via `fastboot` commands (e.g., `fastboot flash efisp ABL.efi`).

### 4. OTA Upgrade
Before rebooting for an OTA update, use the module to flash and retain the old ABL version. If you are doing a major version upgrade, it is recommended to check "Update efisp", otherwise the device might get stuck on the initial boot screen.

### 5. Explanation of Different Variants
1. `ABL.efi`: The patched ABL.
2. `ABL_original`: For developers to analyze in IDA, used for error reporting. **DO NOT flash**.
