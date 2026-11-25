# LineageOS 23.2 (Android 16) on Linux 3.4 kernels

Patches to boot LineageOS 23.2 on devices still running a 3.4 kernel, with
no eBPF and none of the syscalls Android 16 now takes for granted. Brought up
on the Moto G 2013 (falcon, msm8226), 32-bit userspace.

These go **on top of**
[legacy_support_patches](https://github.com/Ultra-Legacy-Hippeastrum/legacy_support_patches)
(lineage-23.2), which they don't duplicate.

## Building for the Moto G 2013 (falcon) / Moto G LTE (peregrine)

From an empty directory, with the
[usual LineageOS build requirements](https://wiki.lineageos.org/devices/falcon/build)
installed:

```sh
# 1. LineageOS 23.2 source, plus the msm8226 trees
mkdir lineage-23.2 && cd lineage-23.2
repo init -u https://github.com/LineageOS/android.git -b lineage-23.2 --git-lfs --no-clone-bundle
git clone https://github.com/Moto-Legacy/local_manifests -b lineage-23.2 .repo/local_manifests
repo sync -c -j8 --no-tags --no-clone-bundle

# 2. Patches (git am needs an identity)
git config --global user.name  >/dev/null || git config --global user.name  "Your Name"
git config --global user.email >/dev/null || git config --global user.email "you@example.com"
git clone https://github.com/Ultra-Legacy-Hippeastrum/legacy_support_patches -b lineage-23.2
git clone https://github.com/Moto-Legacy/patches -b lineage-23.2
chmod +x legacy_support_patches/apply.sh
./legacy_support_patches/apply.sh
./patches/apply.sh
# (no kernel path: the msm8226 kernel tree already carries kernel-3.4/)

# 3. Build (falcon or peregrine)
source build/envsetup.sh
lunch lineage_falcon-bp4a-userdebug
mka bacon
```

The flashable zip ends up in `out/target/product/falcon/`. Flash it from
TWRP (`adb sideload`). The partition table is never changed (the bootloader
only boots Motorola signed tables):

Both devices use retrofit dynamic partitions: a `super` spanning the stock
`system` and `cache` partitions (1.6 GB on both), holding ext4 `system` and
`vendor` logical partitions plus an empty `metadata` one. The zip writes
`boot` and that `super`, so `cache` is taken over. peregrine's layout mirrors
falcon's but has not been built or tested on a device yet.

Only one build at a time on machines with little RAM, and keep `repo sync`
at `-j8` or lower if GitHub starts refusing connections.

## Using the patches on another device

```sh
# from the root of a lineage-23.2 tree
./legacy_support_patches/apply.sh
./patches/apply.sh kernel/<vendor>/<device>
```

The kernel path is optional; without it only the platform patches are
applied. The non-A/B OTA patches also need
[LineageOS/android_system_tools_dtbtool](https://github.com/LineageOS/android_system_tools_dtbtool)
(`lineage-18.1`) at `system/tools/dtbtool` for devices with
`BOARD_KERNEL_SEPARATED_DT`; add it to your local manifest:

```xml
<project path="system/tools/dtbtool" name="LineageOS/android_system_tools_dtbtool" remote="github" revision="lineage-18.1" />
```

## Status

falcon boots to the setup wizard and Settings, with adb (root, from
early-init). The UI is still very slow and several things are missing (radio,
camera, compass...). Not daily driver material yet.

## What they fix

### Missing syscalls and kernel features (platform)

| Repo | Problem on 3.4 | Fix |
|---|---|---|
| bionic | `arc4random` aborts: `MADV_WIPEONFORK` needs 4.14 (kills every process, even the recovery updater) | pid based fork detection, like OpenBSD's Linux port |
| bionic | `fstat()` on `O_PATH` fds needs 3.6: `realpath()` fails, first stage init can't mount `/system` | emulate it through `/proc/self/fd` |
| bionic | `rename()`/`renameat()` use `renameat2()` (3.15): every rename fails (derive_classpath → zygote, installd, vold) | fall back to `renameat()` |
| system/core | tombstoned uses `O_TMPFILE` (3.11) and aborts on every crash | named temporary file + rename |
| frameworks/native, system/hwservicemanager | servicemanagers abort without binder security contexts (`TXN_SECURITY_CTX`, 4.20) | fall back to `getpidcon()` |
| packages/modules/Connectivity | `netbpfload` fails with no `bpf()` syscall at all (3.18) and init reboots | mark the programs loaded and exit |
| packages/modules/Connectivity | `ClatCoordinator` aborts system_server when `/sys/fs/bpf` doesn't exist | skip the clat BPF checks there |
| bionic | `epoll_pwait2()` (5.11) fails on every frame in BLASTBufferQueue | fall back to `epoll_pwait()` with the timeout rounded up to ms |
| art | the JIT of forked processes needs `memfd_create()` (3.17): system_server aborts | use ashmem, like the zygote region already does |
| system/security | keystore2 rejects every call without a binder `calling_sid` | look the caller context up with `getpidcon()` instead |
| system/sepolicy | the `getpidcon()` fallbacks need to read `/proc/<pid>/attr/current` | let servicemanager, hwservicemanager, vndservicemanager and keystore2 read it |

### Building and packaging

| Repo | Fix |
|---|---|
| build/make | Non-A/B OTAs for devices without a recovery partition (fstab and install helpers in the target files, `cache_size` without a cache image) |
| build/make | Pass the QCDT `dt.img` (`BOARD_KERNEL_SEPARATED_DT`) to the boot image, also when releasetools rebuilds it |
| build/make | Retrofit dynamic partitions on non-A/B devices: allow them in `check_partition_sizes`, and support empty logical partitions (falcon's `metadata`) in full OTAs, created writable |
| build/soong | Keep dex compressed when dexpreopt is disabled globally (space) |
| build/soong, build/make | Bring back `WITH_DEXPREOPT_BOOT_IMG_AND_SYSTEM_SERVER_ONLY`: preopt the boot images and system_server only (no boot image means the whole framework runs interpreted and system_server trips the watchdog) |
| build/soong, build/make | With that knob, still preopt `PRODUCT_DEXPREOPT_SPEED_APPS` (SystemUI, launcher, Settings): left to the JIT they're most of the UI lag on a 1 GB Cortex-A7 |

### Kernel (`kernel-3.4/`, generic 3.4 patches)

| Patch | Fix |
|---|---|
| kconfig, dtc, xz_wrap, kbuild | Build with current host tools |
| selinux | Android 15+ policies carry `nlmsg` extended permissions; the Android M compatibility code took them for an M policy and failed to load it |
| usb: gadget: f_fs | Android 16 adbd only uses AIO on FunctionFS (3.15); without it the device stays `offline` |

### Third party patches (authors kept)

Picked from [MisterZtr/LineageOS_gsi](https://github.com/MisterZtr/LineageOS_gsi)
`patches/trebledroid` (TrebleDroid), for BPF-less kernels and old encryption
setups:

- **Pierre-Hugues Husson (phhusson)**: BPF-less support in Connectivity,
  DnsResolver, system/bpf, netd; gpuservice off without BPF; FDE fallback,
  quota handling, fscrypt errors in system/core; `O_DIRECT` off in apexd.
- **Alberto Ponces**: encryptable fstab flag in fs_mgr; netd init abort revert.
- **Michael Bestas**: netd kernel version restrictions.
- **ChonDoit**: no-bpf use case in netd.
- **Luca Stefani**: libfscrypt directory bail out.
- **danielzhang130**: sepolicy without the bpf file context.

The FunctionFS AIO support in `kernel-3.4/` is taken from **acroreiser**'s
[lineage-23.2 hammerhead kernel](https://github.com/acroreiser/android_kernel_lge_hammerhead),
who also maintains legacy_support_patches.

Everything else: FPSensor.

## Device side notes

Not patches, but needed in the device tree on these kernels:

- `ro.hardware.egl=<name>` (libEGL no longer scans `/vendor/lib/egl`).
- `PRODUCT_COMPRESSED_APEX := false` if `androidboot.apex.early_adbd=true`
  (compressed APEXes can't be bootstrap ones).
- `AB_OTA_UPDATER := false` (Android 16 defaults it to true).
- No early mount fstab in the device tree if the ramdisk fstab differs.
- IRadio < 1.4 is rejected by telephony: wrap the RIL (see LineageOS'
  hammerhead radio 1.4 service).
- `CONFIG_IKCONFIG_PROC=y` (`android.os.Debug` reads `/proc/config.gz`).
- A `/metadata` partition (aconfigd keeps the feature flags there; without it
  flagged permissions disappear and AppOps kills system_server). An unused
  cache partition works, or an empty logical partition in a retrofit `super`
  (`BOARD_SUPER_EMPTY_PARTITIONS`).
- Legacy keymaster (0.x/3.0) has no AES: use AOSP's software keymaster 4.1 and
  gatekeeper, or LockSettings kills system_server.
- Legacy HALs must be installed to `/vendor/lib/hw` (`LOCAL_VENDOR_MODULE`).
- 1 GB of RAM: `ro.config.low_ram=true`, AOSP's `phone-xhdpi-1024` heap
  (`heapgrowthlimit=96m`), a bigger zram and no blur. Without them zram fills
  up, nothing gets killed and the UI drops to ~1 FPS.
- Preopt the UI apps with `PRODUCT_DEXPREOPT_SPEED_APPS` (the launcher module
  is `Launcher3QuickStep` in 23.2, not `TrebuchetQuickStep`).
