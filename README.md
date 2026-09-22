# Samsung Tablet Optimizer

Speed up and debloat Samsung Galaxy tablets via ADB — no root required.

## What it does

| Step | A7 (SM-T220) | A8 (SM-X200) |
|---|---|---|
| Launcher | Installs Lawnchair | Installs Lawnchair |
| Animations | 0.5x scale | 0.5x scale |
| Bloatware | Disables ~41 packages | Disables ~55 packages |
| User apps | Removes bloat games | N/A |
| System apps | Uninstalls Chrome | N/A |
| Browser | Sets Chrome as default | Sets Chrome as default |
| Performance | Compiles speed profiles | Compiles speed profiles |
| Caches | Trims 8GB | Trims 8GB |

## Prerequisites

```bash
# Install ADB
sudo dnf install android-tools    # Fedora
sudo apt install adb             # Debian/Ubuntu

# On tablet: Settings → About → tap Build Number 7x → Developer Options → USB debugging ON
# Connect tablet via USB, authorize this computer when prompted
```

## Quick start

```bash
# 1. Clone / download this repo
git clone https://github.com/YOUR_USER/tablet-optimize.git
cd tablet-optimize

# 2. Download Lawnchair APK and place it
#    https://github.com/LawnchairLauncher/lawnchair/releases
cp ~/Downloads/Lawnchair*.apk lawnchair/Lawnchair.apk

# 3. Find your tablet's serial
adb devices
# Output: YOUR_SERIAL    device

# 4. Run
./optimize.sh --tablet YOUR_SERIAL

# 5. Reboot
adb reboot
```

## Commands

```bash
# Optimize (auto-detects A7 or A8)
./optimize.sh --tablet SERIAL

# Optimize a specific model (safety check)
./optimize.sh --tablet SERIAL --model SM-X200
./optimize.sh --tablet SERIAL --model SM-T220

# Show device info (storage, memory, packages)
./optimize.sh --info

# Restore original state (re-enable packages)
./optimize.sh --tablet SERIAL --restore-original
```

## Adding/removing packages

Edit the package lists in `packages/`:

```
packages/
├── a7-disabled.txt         # Packages to disable (A7)
├── a7-removed-user.txt     # User apps to fully uninstall (A7)
├── a7-uninstalled-system.txt # System apps to uninstall (A7)
├── a8-disabled.txt         # Packages to disable (A8)
```

Each file is one package name per line. Lines starting with `#` are comments.

## Tested tablets

| Model | Codename | Status |
|---|---|---|
| Samsung Galaxy Tab A8 (4/64GB) | SM-X200 | ✅ |
| Samsung Galaxy Tab A7 Lite (3/32GB) | SM-T220 | ✅ |

## How it works

- **ADB** (Android Debug Bridge) controls the tablet from your PC
- **`pm disable-user`** — disables a package (reversible, keeps data)
- **`pm uninstall`** — removes a user app permanently
- **`pm uninstall --user 0`** — removes a pre-installed system app
- **`settings put global`** — adjusts animation scales and display options
- **`cmd package compile`** —Ahead-of-time (AOT) compilation for faster app starts

## Safety

- All changes are **reversible** with `--restore-original`
- Packages are *disabled*, not deleted — re-enable any time via:
  ```bash
  adb shell pm enable --user 0 PACKAGE_NAME
  ```
- Chrome is uninstalled only on A7 — if you need it, remove it from `a7-uninstalled-system.txt`

## Customizing for other tablets

1. Run `--info` to see what packages are installed
2. Dump all packages: `adb shell pm list packages`
3. Find bloat: `adb shell pm list packages -d` (disabled-capable)
4. Add package names to the appropriate list in `packages/`
5. Test on your specific model

## License

MIT
