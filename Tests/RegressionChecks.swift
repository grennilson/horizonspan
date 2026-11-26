import AppKit
import ImageIO
import UniformTypeIdentifiers

@main struct RegressionChecks {
    static func image(_ width: Int, _ height: Int, color: CGColor, right: CGColor? = nil) -> CGImage {
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(color)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        if let right {
            context.setFillColor(right)
            context.fill(CGRect(x: width / 2, y: 0, width: width - width / 2, height: height))
        }
        return context.makeImage()!
    }

    static func rgb(_ image: CGImage, x: Int = 0, y: Int = 0) -> [UInt8] {
        let context = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8,
                                bytesPerRow: image.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let pointer = context.data!.assumingMemoryBound(to: UInt8.self)
        let offset = (y * image.width + x) * 4
        return Array(UnsafeBufferPointer(start: pointer + offset, count: 3))
    }

    static func check(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else { fatalError(message) }
    }

    @MainActor static func main() async throws {
        let files = FileManager.default
        let folder = files.temporaryDirectory.appendingPathComponent("ScreenSpan-Tests-\(UUID().uuidString)")
        try files.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? files.removeItem(at: folder) }

        let red = CGColor(srgbRed: 1, green: 0, blue: 0, alpha: 1)
        let blue = CGColor(srgbRed: 0, green: 0, blue: 1, alpha: 1)
        let green = CGColor(srgbRed: 0, green: 1, blue: 0, alpha: 1)
        let white = CGColor(gray: 1, alpha: 1)
        let input = image(80, 20, color: red, right: blue)
        let source = SourceImage(filename: "Test Panorama.png", image: input)
        let left = Display(id: 900001, name: "Left", frame: CGRect(x: -40, y: 0, width: 40, height: 20), pixelWidth: 80, pixelHeight: 40)
        let right = Display(id: 900002, name: "Right", frame: CGRect(x: 0, y: 0, width: 40, height: 20), pixelWidth: 40, pixelHeight: 20)
        let displays = [left, right]

        let legacy = SavedWallpaper(source: source, framing: .fill, zoom: 1, pan: .zero)
        let baseline = try WallpaperRenderer.images(source: input, wallpaper: legacy, displays: displays)
        check(rgb(baseline[0], x: 40, y: 20)[0] > 250, "Panorama left half must be red")
        check(rgb(baseline[1], x: 20, y: 10)[2] > 250, "Panorama right half must be blue")
        check(baseline[0].width == 80 && baseline[1].width == 40, "Mixed output densities must survive")

        var design = WallpaperDesign.standard
        design.monitors = [MonitorPlacement(key: left.hardwareKey, group: 1),
                           MonitorPlacement(key: right.hardwareKey, group: 2)]
        design.customGroups = [1, 2]
        let assets = [1: SourceImage(filename: "Green.png", image: image(20,20,color:green)),
                      2: SourceImage(filename: "Red.png", image: image(20,20,color:red))]
        let groups = SavedWallpaper(source: source, framing: .fill, zoom: 1.2, pan: CGSize(width: 0.1, height: 0), design: design)
        let separate = try WallpaperRenderer.images(source: input, wallpaper: groups, displays: displays, assets: assets)
        check(rgb(separate[0])[1] > 250 && rgb(separate[1])[0] > 250, "Separate monitor sources must remain separate")
        let third = Display(id: 900003, name: "Portrait", frame: CGRect(x: 40, y: 0, width: 20, height: 40),
                            pixelWidth: 40, pixelHeight: 80)
        let groupedThree = try WallpaperRenderer.images(source: input, wallpaper: groups,
                                                         displays: displays + [third], assets: assets)
        check(groupedThree.count == 3 && groupedThree[2].width == 40 && groupedThree[2].height == 80,
              "A separate third portrait monitor must render at its own resolution")

        var adjusted = WallpaperDesign.standard
        adjusted.monitors = [MonitorPlacement(key: right.hardwareKey, offsetX: 20, sizeScale: 1.25)]
        let alignment = SavedWallpaper(source: source, framing: .fill, zoom: 1, pan: .zero, design: adjusted)
        let aligned = try WallpaperRenderer.images(source: input, wallpaper: alignment, displays: displays)
        check(aligned[0].width == 80 && aligned[1].height == 20, "Alignment must preserve display output resolution")
        let rampContext = CGContext(data: nil, width: 80, height: 20, bitsPerComponent: 8, bytesPerRow: 0,
                                    space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        for x in 0..<80 {
            rampContext.setFillColor(CGColor(gray: CGFloat(x) / 79, alpha: 1))
            rampContext.fill(CGRect(x: x, y: 0, width: 1, height: 20))
        }
        let ramp = rampContext.makeImage()!
        let beforeAlignment = try WallpaperRenderer.images(source: ramp, wallpaper: legacy, displays: displays)
        let afterAlignment = try WallpaperRenderer.images(source: ramp, wallpaper: alignment, displays: displays)
        check(rgb(beforeAlignment[0], x: 40, y: 20) != rgb(afterAlignment[0], x: 40, y: 20),
              "Offsets and physical-size adjustments must change the sampled panorama region")
        check(WallpaperDesign.setupKey(displays) == WallpaperDesign.setupKey(displays.reversed()), "Setup identity must ignore enumeration order")
        check(WallpaperDesign.setupKey(displays) != WallpaperDesign.setupKey([left]), "Different monitor sets must have different profiles")

        var appearance = WallpaperAppearance()
        appearance.dim = 0.6
        let dimmed = try appearance.image(image(8,8,color:white))
        check(rgb(dimmed)[0] < 245 && rgb(dimmed)[0] > 0, "Dimming must lower brightness")
        appearance.dim = 0
        appearance.saturation = 0
        let gray = rgb(try appearance.image(image(8,8,color:red)))
        check(abs(Int(gray[0]) - Int(gray[1])) <= 2 && abs(Int(gray[1]) - Int(gray[2])) <= 2, "Zero saturation must produce gray")
        var background = WallpaperDesign.standard
        background.appearance.red = 1
        let narrow = image(10,20,color:blue)
        let backgroundSettings = SavedWallpaper(source: source, framing: .fit, zoom: 1, pan: .zero, design: background)
        let withBackground = try WallpaperRenderer.images(source: narrow, wallpaper: backgroundSettings, displays: displays)
        check(rgb(withBackground[0])[0] > 250, "Fit margins must use the chosen background color")

        let libraryRoot = folder.appendingPathComponent("Library")
        let project = try WallpaperProject.save(source: source, wallpaper: groups, displays: displays, library: libraryRoot, assets: assets)
        let reopened = try WallpaperProject.open(project)
        let restoredAssets = try WallpaperProject.assets(at: project, settings: reopened.1)
        check(reopened.1.design == design && restoredAssets.count == 2, "Projects must restore groups and custom images")
        check(files.fileExists(atPath: project.appendingPathComponent("Thumbnail.png").path), "Library thumbnail must be generated")
        let moved = libraryRoot.appendingPathComponent("Moved Project.ssw")
        try files.moveItem(at: project, to: moved)
        let movedProject = try WallpaperProject.open(moved)
        check(movedProject.1.id == groups.id && movedProject.1.zoom == 1.2, "Portable projects must survive moving")
        check(tryAssets(moved, settings: movedProject.1) == 2, "Moved projects must retain custom image files")

        let cache = WallpaperStore(root: folder.appendingPathComponent("Cache"))
        try cache.store(input, as: groups, assets: assets)
        try cache.select(groups)
        let rendered = try cache.render(input, wallpaper: groups, displays: displays, assets: assets)
        check(cache.current()?.design == design && rendered.count == 2, "Restore cache must keep the complete design")
        check(tryAssetsCount(cache, settings: groups) == 2, "Restore cache must keep group assets")
        let oneMonitor = try cache.render(input, wallpaper: groups, displays: [left], assets: assets)
        check(oneMonitor[0] != rendered[0], "Changed display arrangements need distinct renders")

        // CG display numbers can change at reboot; physical monitor identity and
        // its cached file association must survive that change and enumeration order.
        let stableLeft = Display(id: 910001, name: "Left", frame: left.frame, pixelWidth: 80, pixelHeight: 40, persistentID: "physical-left")
        let stableRight = Display(id: 910002, name: "Right", frame: right.frame, pixelWidth: 40, pixelHeight: 20, persistentID: "physical-right")
        let restartedLeft = Display(id: 920004, name: "Left", frame: left.frame, pixelWidth: 80, pixelHeight: 40, persistentID: "physical-left")
        let restartedRight = Display(id: 920003, name: "Right", frame: right.frame, pixelWidth: 40, pixelHeight: 20, persistentID: "physical-right")
        try cache.store(input, as: legacy)
        let stableURLs = try cache.render(input, wallpaper: legacy, displays: [stableLeft, stableRight])
        let restartedURLs = try cache.render(input, wallpaper: legacy, displays: [restartedRight, restartedLeft])
        check(stableURLs[0] == restartedURLs[1] && stableURLs[1] == restartedURLs[0],
              "Restarted monitors must retain their physical cached image associations")
        let restartedImage = try SourceImage(url: restartedURLs[1])
        check(rgb(restartedImage.image, x: 40, y: 20)[0] > 250, "Restart must not swap panorama halves")
        try Data("damaged cache".utf8).write(to: stableURLs[0], options: .atomic)
        let repairedURLs = try cache.render(input, wallpaper: legacy, displays: [restartedLeft, restartedRight])
        let repairedImage = try SourceImage(url: repairedURLs[0])
        check(repairedImage.image.width == 80, "Unreadable cached PNGs must be rendered again")
        var stableDesign = design
        stableDesign.monitors = [MonitorPlacement(key: stableLeft.hardwareKey, group: 1),
                                 MonitorPlacement(key: stableRight.hardwareKey, group: 2)]
        let stableGroups = SavedWallpaper(source: source, framing: .fill, zoom: 1, pan: .zero, design: stableDesign)
        let restartedGroups = try WallpaperRenderer.images(source: input, wallpaper: stableGroups,
            displays: [restartedLeft, restartedRight], assets: assets)
        check(rgb(restartedGroups[0])[1] > 250 && rgb(restartedGroups[1])[0] > 250,
              "Independent monitor sources must follow physical monitors after reboot")

        var attempts = 0
        var connected = 1
        var desktop = ["macOS", "macOS"]
        await WallpaperRestoreSchedule.run(delays: WallpaperRestoreSchedule.startup, wait: { _ in
            if attempts == 1 { connected = 2 }
            if attempts == 3 { desktop = ["macOS", "macOS"] }
        }, enabled: { true }, attempt: {
            attempts += 1
            if attempts == 1 { return } // A transient startup failure must not stop retries.
            if connected == 2 { desktop = ["saved-left", "saved-right"] }
        })
        check(attempts == 5 && desktop == ["saved-left", "saved-right"],
              "Late display discovery and a later macOS overwrite must be repaired")
        var disabledAttempts = 0
        await WallpaperRestoreSchedule.run(delays: WallpaperRestoreSchedule.startup, wait: { _ in },
            enabled: { disabledAttempts == 0 }, attempt: { disabledAttempts += 1 })
        check(disabledAttempts == 1, "Turning off restoration must stop later attempts")
        var canceledAttempts = 0
        let canceled = Task { @MainActor in
            await WallpaperRestoreSchedule.run(delays: WallpaperRestoreSchedule.startup, wait: { _ in },
                enabled: { true }, attempt: { canceledAttempts += 1 })
        }
        canceled.cancel()
        await canceled.value
        check(canceledAttempts == 0, "A superseded restoration task must not assign wallpapers")

        let oldFolder = libraryRoot.appendingPathComponent("Old.ssw")
        try files.createDirectory(at: oldFolder, withIntermediateDirectories: false)
        var oldJSON = try JSONSerialization.jsonObject(with: JSONEncoder().encode(WallpaperProject(formatVersion: 1, wallpaper: legacy, displays: []))) as! [String:Any]
        var oldSettings = oldJSON["wallpaper"] as! [String:Any]
        oldSettings.removeValue(forKey: "design")
        oldJSON["wallpaper"] = oldSettings
        try JSONSerialization.data(withJSONObject: oldJSON).write(to: oldFolder.appendingPathComponent("Settings.json"))
        try WallpaperProject.write(input, to: oldFolder.appendingPathComponent("Image.png"))
        let old = try WallpaperProject.open(oldFolder)
        check(old.1.design == nil && old.0.image.width == input.width, "Version 1 projects must still open")
        let unsupported = libraryRoot.appendingPathComponent("Unsupported.ssw")
        try files.createDirectory(at: unsupported, withIntermediateDirectories: false)
        oldJSON["formatVersion"] = 999
        try JSONSerialization.data(withJSONObject: oldJSON).write(to: unsupported.appendingPathComponent("Settings.json"))
        do {
            _ = try WallpaperProject.open(unsupported)
            fatalError("Unsupported project versions must be rejected")
        } catch {}

        let library = try WallpaperLibraryStore(root: libraryRoot)
        var index = try library.index()
        index.entries[groups.id.uuidString] = LibraryDetails(title: "My Favorite", favorite: true)
        index.setups[WallpaperDesign.setupKey(displays)] = SetupProfile(name: "Desk", projectID: groups.id)
        try library.write(index)
        let listed = try library.entries(index: library.index())
        check(listed.count == 2, "The library must skip projects with unsupported format versions")
        check(listed.first(where: { $0.id == groups.id })?.title == "My Favorite", "Renaming must persist without modifying project files")
        check(listed.first(where: { $0.id == groups.id })?.favorite == true, "Favorites must persist")
        check(tryProfile(library, displays: displays) == groups.id, "Setup associations must persist")

        check(ReleaseVersion.isNewer("v1.10.0", than: "1.9.9"), "Version comparison must be numeric")
        check(!ReleaseVersion.isNewer("v1.4.0", than: "1.4"), "Equivalent versions must compare equally")
        check(!ReleaseVersion.isNewer("v1.4.0-beta", than: "1.3"), "Unrecognized release tags must be rejected")

        let model = WallpaperState(observeSystem: false)
        model.source = source
        model.design = design
        model.groupImages = assets
        model.framing = .fill
        model.zoom = 1.3
        model.pan = CGSize(width: 0.1, height: 0)
        model.beginCrop()
        model.applyCrop()
        model.undoImageEdit()
        check(model.source?.image.width == input.width && model.zoom == 1.3 && model.design == design,
              "Crop undo must restore the source, framing and complete display design")
        model.redoImageEdit()
        check(model.original != nil, "Crop redo must preserve comparison with the original")
        model.rotationMinutes = 15
        model.rotationEnabled = true
        check(model.nextRotation.timeIntervalSinceNow > 890, "Rotation should wait for the chosen interval")
        model.rotationEnabled = false
        check(model.nextRotation == .distantFuture, "Disabled rotation must have no pending deadline")

        print("PASS — spanning, mixed resolutions, independent sources, alignment, appearance, backgrounds")
        print("PASS — project portability, legacy projects, restore cache, thumbnails, library metadata and monitor profiles")
        print("PASS — numeric update versions, crop undo/redo and rotation deadlines")
        print("PASS — stable monitor identities after reboot, damaged cache recovery, delayed startup retries and cancellation")
    }

    static func tryAssets(_ url: URL, settings: SavedWallpaper) -> Int { (try? WallpaperProject.assets(at: url, settings: settings).count) ?? -1 }
    static func tryAssetsCount(_ store: WallpaperStore, settings: SavedWallpaper) -> Int { (try? store.assets(for: settings).count) ?? -1 }
    static func tryProfile(_ store: WallpaperLibraryStore, displays: [Display]) -> UUID? {
        try? store.index().setups[WallpaperDesign.setupKey(displays)]?.projectID
    }
}
