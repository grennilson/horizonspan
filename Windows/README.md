# ScreenSpan Wallpaper for Windows 1.0.2

Create desktop wallpapers for one, two, three, four or more monitors. The app follows the arrangement reported by Windows and renders a separate image at each display's resolution.

## Install or run

Download from the [Windows 1.0.2 release](https://github.com/grennilson/horizonspan/releases/tag/windows-v1.0.2):

- **ScreenSpan-Wallpaper-Windows-Setup-1.0.2.exe** installs for your Windows account, with Desktop and Start menu shortcuts. No administrator access is needed. Updates keep saved pictures and preferences.
- **ScreenSpan-Wallpaper-Windows-1.0.2.exe** is the standalone application. It embeds its application dependencies; neighboring DLL files are not needed.
- The portable ZIP includes the application and documentation.

Requires Windows 10 or Windows 11, 64-bit, with .NET Framework 4.8 or newer. Windows 11 includes it. If Windows 10 reports a missing framework, install [.NET Framework 4.8 from Microsoft](https://dotnet.microsoft.com/en-us/download/dotnet-framework/net48). The executables are unsigned; Windows may show an unknown-publisher message. SHA-256 checksums are included with the release.

## Import, combine and crop

Choose **Choose Images…** or drop image files into the preview. JPEG, PNG, BMP and TIFF are supported. A newly imported picture uses **Fit Entire Photo** to preserve its full height and proportions. **Fill & Crop** fills the monitor layout instead. Drag the preview to position the image; use the scroll wheel to zoom.

Select several images to combine them. Reorder the list, select horizontal placement or **Stack vertically**, and combine. Each image retains its proportions. The combined image is limited to 64 megapixels.

**Crop…** opens a rectangle locked to the connected monitor layout, including portrait and vertically arranged monitors. Move it by dragging inside; resize it using any corner. The scroll wheel changes the crop size. **Apply Crop** commits it; **Cancel Crop** leaves the image unchanged.

**Undo** and **Redo** restore image edits and framing. **Show Original** compares with the draft's originally imported image. **Revert to Original** restores that source and its settings. Undo history belongs to the current editor session; it is not included in project files.

## Displays and appearance

Open **Wallpaper → Displays & Appearance…**.

- Group **0** is the main panorama. Displays in the same group share a spanning image.
- Assign different group numbers to use independent pictures, or span a subset of displays.
- Choose a picture for each group, or let the group use the main image.
- Horizontal/vertical offsets and relative display size adjust which part of the wallpaper is sampled. Positive vertical offsets move the sampling area upward. These controls do not change Windows display settings.
- Appearance provides brightness, saturation, dimming and background color for uncovered areas.

Click **Done** and review the preview before applying. Display designs and group pictures are included in saved projects and Undo history.

## Library, favorites and monitor profiles

**Saved Wallpapers…** opens a thumbnail library. Select a wallpaper to rename it, mark it as a favorite, open its settings, apply it, or show its files. Library application leaves the current editor draft untouched.

Enter a monitor setup name and choose **Use for This Monitor Setup**. Enable **Automatically match saved monitor setups** in Settings. Matching includes display identity, resolution and arrangement. **Forget Setup** removes the association.

Settings can rotate favorites at a chosen interval. If there are no favorites, rotation uses all saved projects. **Next Wallpaper** is also available from the Wallpaper menu and tray menu. Rotation waits while an owned dialog, crop or AI task is active.

## Local AI and edge filling

**Image Tools → Extend with AI…** adds scenery around the original image to fit the monitor ratio. Position the image first, then describe what should continue at its edges. It preserves the original source region while generating outside it. SDXL may invent details or leave seams; review the result before applying and use Undo if needed.

**Enhance Detail…** uses Real-ESRGAN to enlarge a low-resolution source up to four times per side, within a 64-megapixel output limit. It enlarges to the size needed by the current monitor framing.

**Fade Edges to Black** extends a narrow strip of edge texture into black, without generating scenery. It supports horizontal and vertical extension, runs offline and preserves the original picture at the selected position.

AI setup downloads a private Python runtime, PyTorch and model dependencies under `%LOCALAPPDATA%/ScreenSpan Wallpaper/LocalAI-v1`. First-use downloads can be large: the detail model is about 67 MB and the edge model about 7 GB, plus runtime packages. Models are downloaded from their upstream sources and large weights are checked against pinned SHA-256 digests. Your image is processed on the PC and is not uploaded to an image service. No account, API key, subscription or per-image fee is required.

Settings selects CPU or NVIDIA CUDA processing. CPU detail enhancement works on Intel/AMD systems. CPU edge generation requires at least 32 GB RAM and can be very slow; NVIDIA CUDA is recommended for it. CUDA requires a compatible NVIDIA GPU and driver. Intel integrated graphics and AMD GPUs use CPU mode in this release. Cancellation stops the worker process tree and leaves the editor source unchanged. Runtime and model downloads remain cached for later attempts. See [third-party notices](THIRD-PARTY-NOTICES.md) for dependencies and model terms.

## Saved projects and portability

**Save Project** and **Apply Wallpaper** create a new `.ssw` project folder under **Pictures/ScreenSpan Wallpaper**. Each project includes:

- `Settings.json`: framing, zoom, position, display groups, alignment and appearance.
- `Image.png`: the current edited source.
- `Group-N.png`: pictures used by independent groups.
- `Wallpaper.png`: the rendered combined wallpaper.
- `Thumbnail.png`: a library thumbnail.
- `Displays/Display-N.png`: the individual display images.

Open projects through the library, **File → Open Project Folder…**, by dropping a project folder into the editor, or by dropping it onto the standalone EXE. New saves create new folders and do not overwrite the imported project. Missing group images or unsupported formats are rejected with an explanation.

The `.ssw` format is a directory package on Mac and an ordinary folder on Windows. Versions 1 and 2 open on Windows. Display identities differ between operating systems; when no saved identity matches, Windows maps saved assignments in display order. Check grouping/alignment when moving between computers. Mac can read the format and image assets, but hardware-specific monitor assignments may need to be selected again. Finished `Wallpaper.png` and individual display PNGs remain directly reusable.

Names, favorites and named monitor profiles are in `Pictures/ScreenSpan Wallpaper/.Library.json`. Preferences and render caches are under `%LOCALAPPDATA%/ScreenSpan Wallpaper`. Uninstalling the app keeps projects, preferences and downloaded models.

## Keep wallpapers in place

After **Apply Wallpaper**, the app saves a self-contained project and remembers its location. It restores and rerenders that wallpaper after display changes, wake and session reconnection, while it is running. Cached renders are reused for the same settings and monitor layout. Background errors are recorded in `Background.log`, without interrupting the editor with repeated dialogs.

Minimize keeps the editor on the Windows taskbar. Closing with **X** hides the editor and keeps the app running in the Windows notification area. A pinned taskbar icon or the Desktop/Start menu shortcut reopens the existing instance; a single left-click on its icon beside the clock also opens the editor. Right-click that notification icon for a new wallpaper, saved wallpapers, Next, Reapply, Settings and Quit. Reopening restores a minimized window, preserves a maximized window, and brings an existing settings or AI dialog forward. **Start ScreenSpan when I sign in** is optional and off by default.

Windows virtual desktops and Remote Desktop behave differently from macOS Spaces. A remote session may expose virtual monitors; this cannot prove how physically connected screens behave after reconnection. If the Windows wallpaper service does not expose a usable display, the editor uses a preview-only fallback and reports that wallpaper application is unavailable in that session.

## Updates, builds and contributions

**Check for Updates…** finds Windows release tags only (`windows-v…`). Mac and Windows downloads are separate. The Mac release remains the repository's latest Mac download.

Install the .NET 10 SDK from Microsoft, then run from this directory:

```powershell
./build.ps1
```

If your PowerShell policy prevents running a local script, review the script and run its individual build commands in your terminal. No global execution-policy change is required.

The script builds the app, runs cross-platform checks and Windows rendering/project/editor checks, builds the installer, and tests the extracted standalone EXE without neighboring application DLLs. It writes executables, a portable ZIP, checksums and reports to `artifacts/`. AI inference is a separate optional integration check because it downloads large dependencies:

```powershell
& './App/bin/Release/net48/ScreenSpan Wallpaper.exe' --ai-smoke-test "$PWD/ai-checks.txt"
```

On a machine with at least 32 GB RAM, `--ai-edge-smoke-test "$PWD/edge-checks.txt"` downloads the SDXL model and runs a small CPU extension with two inference steps. It checks output dimensions and preservation of the source pixels. Normal editor generation uses 26 steps; this short diagnostic does not assess visual quality.

Source layout: `Core/` contains geometry, settings validation, profiles and AI planning; `App/` contains the Windows UI, wallpaper COM interface, library, rendering, persistence and AI launcher; `LocalAI/` contains the Python worker; `Setup/` contains the per-user installer; `Tests/` contains platform-independent checks.

See [TESTING.md](TESTING.md) for results and remaining real-world checks. Do not interpret passing software tests as a guarantee that every driver or physical monitor arrangement has been exercised.
