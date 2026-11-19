import AppKit
import SwiftUI

extension WallpaperState {
    var currentDesign: WallpaperDesign {
        var result = design
        result.customGroups = groupImages.keys.sorted()
        return result
    }

    func refreshLibrary() {
        do {
            let store = try WallpaperLibraryStore()
            let index = try store.index()
            let entries = try store.entries(index: index)
            libraryIndex = index
            libraryEntries = entries
            if selectedLibraryID == nil { selectedLibraryID = entries.first?.id }
            if let profile = index.setups[WallpaperDesign.setupKey(displays)] { setupName = profile.name }
        } catch { featureError = "Couldn’t read the wallpaper library. \(error.localizedDescription)" }
    }

    func updateLibraryEntry(_ entry: LibraryEntry, title: String? = nil, favorite: Bool? = nil) {
        var index = libraryIndex
        let name = title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? entry.title
        guard !name.isEmpty else { return }
        index.entries[entry.id.uuidString] = LibraryDetails(title: String(name.prefix(120)), favorite: favorite ?? entry.favorite)
        do {
            try WallpaperLibraryStore().write(index)
            refreshLibrary()
        } catch { featureError = error.localizedDescription }
    }

    func rememberSetup(_ entry: LibraryEntry) {
        var index = libraryIndex
        let title = setupName.trimmingCharacters(in: .whitespacesAndNewlines)
        index.setups[WallpaperDesign.setupKey(displays)] = SetupProfile(
            name: title.isEmpty ? "My Desk" : String(title.prefix(80)), projectID: entry.id)
        do {
            try WallpaperLibraryStore().write(index)
            libraryIndex = index
            autoMatchSetups = true
            activateProject(entry)
        } catch { featureError = error.localizedDescription }
    }

    func forgetCurrentSetup() {
        var index = libraryIndex
        index.setups.removeValue(forKey: WallpaperDesign.setupKey(displays))
        do {
            try WallpaperLibraryStore().write(index)
            libraryIndex = index
        } catch { featureError = error.localizedDescription }
    }

    func matchedSetup(for displays: [Display]) -> LibraryEntry? {
        guard let profile = libraryIndex.setups[WallpaperDesign.setupKey(displays)] else { return nil }
        return libraryEntries.first { $0.id == profile.projectID }
    }

    nonisolated static func readProject(_ url: URL) async throws -> (SourceImage, SavedWallpaper, [Int: SourceImage]) {
        try await Task.detached(priority: .userInitiated) {
            let (source, settings) = try WallpaperProject.open(url)
            let assets = try WallpaperProject.assets(at: url, settings: settings)
            return (source, settings, assets)
        }.value
    }

    func activateProject(_ entry: LibraryEntry) {
        guard !isBusy else { return }
        isApplying = true
        Task {
            defer { isApplying = false }
            do {
                let (source, settings, assets) = try await Self.readProject(entry.url)
                try await applyPrepared(source: source, wallpaper: settings, assets: assets, archive: false)
            } catch { featureError = "Couldn’t apply \(entry.title). \(error.localizedDescription)" }
        }
    }

    func resetRotationClock() {
        nextRotation = rotationEnabled ? Date().addingTimeInterval(Double(rotationMinutes) * 60) : .distantFuture
    }

    func rotateIfDue() {
        guard rotationEnabled, Date() >= nextRotation, canChooseImage else { return }
        refreshLibrary()
        let favorites = libraryEntries.filter(\.favorite)
        guard !favorites.isEmpty else {
            resetRotationClock()
            return
        }
        nextWallpaper(favoritesOnly: true)
        resetRotationClock()
    }

    func nextWallpaper(favoritesOnly: Bool = false) {
        guard !isBusy else { return }
        refreshLibrary()
        let favorites = libraryEntries.filter(\.favorite)
        let choices = favoritesOnly || !favorites.isEmpty ? favorites : libraryEntries
        guard !choices.isEmpty else {
            featureError = "Save a wallpaper project to the library first."
            return
        }
        let current = choices.firstIndex { $0.id == saved?.id } ?? -1
        activateProject(choices[(current + 1) % choices.count])
    }

    func placement(for display: Display) -> MonitorPlacement { design.placement(for: display) }

    func setPlacement(_ value: MonitorPlacement) {
        guard value.isValid else { return }
        if let index = design.monitors.firstIndex(where: { $0.key == value.key }) {
            design.monitors[index] = value
        } else { design.monitors.append(value) }
    }

    func separateDisplays() {
        for (index, display) in displays.enumerated() {
            var item = placement(for: display)
            item.group = index + 1
            setPlacement(item)
        }
    }

    func chooseGroupImage(_ group: Int) {
        guard !isBusy else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do { groupImages[group] = try SourceImage(url: url) }
        catch { featureError = error.localizedDescription }
    }

    func checkForUpdates() {
        guard !checkingUpdates else { return }
        checkingUpdates = true
        updateStatus = "Checking GitHub…"
        updateURL = nil
        Task {
            defer { checkingUpdates = false }
            do {
                let url = URL(string: "https://api.github.com/repos/grennilson/horizonspan/releases/latest")!
                var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
                request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { throw URLError(.badServerResponse) }
                let release = try JSONDecoder().decode(ReleaseInfo.self, from: data)
                guard ReleaseVersion.components(release.tag_name) != nil,
                      release.html_url.scheme == "https", release.html_url.host == "github.com",
                      release.html_url.path.hasPrefix("/grennilson/horizonspan/releases/") else {
                    throw URLError(.cannotParseResponse)
                }
                let installed = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
                if ReleaseVersion.isNewer(release.tag_name, than: installed) {
                    updateStatus = "\(release.tag_name) is available."
                    updateURL = release.html_url
                } else { updateStatus = "You’re running the latest version (\(installed))." }
            } catch { updateStatus = "Couldn’t check for updates. Try again when online." }
        }
    }
}

struct WallpaperLibraryView: View {
    @ObservedObject var model: WallpaperState
    @Environment(\.openWindow) private var openWindow

    private var selected: LibraryEntry? { model.libraryEntries.first { $0.id == model.selectedLibraryID } }

    var body: some View {
        HStack(spacing: 0) {
            List(selection: $model.selectedLibraryID) {
                ForEach(model.libraryEntries) { entry in
                    HStack {
                        Image(nsImage: entry.thumbnailImage)
                            .resizable().scaledToFit().frame(width: 84, height: 46)
                        Text(entry.title).lineLimit(2)
                        Spacer()
                        if entry.favorite { Image(systemName: "star.fill").foregroundStyle(.yellow) }
                    }
                    .padding(.vertical, 4)
                    .tag(entry.id)
                }
            }
            .frame(minWidth: 250, idealWidth: 290)
            Divider()
            VStack(alignment: .leading, spacing: 14) {
                if let entry = selected {
                    Image(nsImage: entry.thumbnailImage)
                        .resizable().scaledToFit().frame(maxWidth: .infinity, maxHeight: 220)
                    HStack {
                        TextField("Wallpaper name", text: $model.libraryTitle)
                        Button("Rename") { model.updateLibraryEntry(entry, title: model.libraryTitle) }
                    }
                    Toggle("Favorite", isOn: Binding(get: { entry.favorite },
                        set: { model.updateLibraryEntry(entry, favorite: $0) }))
                    HStack {
                        Button("Open in Editor") {
                            guard model.canChooseImage else { return }
                            model.loadImage(entry.url)
                            openWindow(id: "main", value: true)
                            NSApp.activate(ignoringOtherApps: true)
                        }
                        .disabled(!model.canChooseImage)
                        Button("Apply Wallpaper") { model.activateProject(entry) }
                            .buttonStyle(.borderedProminent).disabled(model.isBusy)
                    }
                    Divider()
                    TextField("Monitor setup name", text: $model.setupName)
                    Button("Use for This Monitor Setup") { model.rememberSetup(entry) }
                        .disabled(model.isBusy || model.displays.isEmpty)
                    if let match = model.matchedSetup(for: model.displays) {
                        Text("This setup uses \(match.title)").font(.caption).foregroundStyle(.secondary)
                        Button("Forget This Setup", action: model.forgetCurrentSetup)
                    }
                    Spacer()
                    Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([entry.url]) }
                } else {
                    Text("Save a wallpaper project to build your library.").foregroundStyle(.secondary)
                    Spacer()
                }
                HStack {
                    Button("Refresh", action: model.refreshLibrary)
                    Button("Open Folder", action: model.showWallpaperLibrary)
                }
            }
            .padding(20).frame(minWidth: 350)
        }
        .frame(minWidth: 720, minHeight: 490)
        .onAppear {
            model.refreshLibrary()
            model.libraryTitle = selected?.title ?? ""
        }
        .onChange(of: model.selectedLibraryID) { _ in model.libraryTitle = selected?.title ?? "" }
        .alert("Wallpaper Library", isPresented: Binding(get: { model.featureError != nil },
            set: { if !$0 { model.featureError = nil } })) {
                Button("OK") { model.featureError = nil }
            } message: { Text(model.featureError ?? "") }
    }
}

struct WallpaperDesignView: View {
    @ObservedObject var model: WallpaperState

    private func binding(_ display: Display, _ key: WritableKeyPath<MonitorPlacement, Double>) -> Binding<Double> {
        Binding(get: { model.placement(for: display)[keyPath: key] }, set: { value in
            var placement = model.placement(for: display)
            placement[keyPath: key] = value
            model.setPlacement(placement)
        })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Displays & Appearance").font(.title2.bold())
            if let source = model.source, !model.displays.isEmpty {
                DesignedPreview(source: source, wallpaper: SavedWallpaper(source: source, framing: model.framing,
                    zoom: model.zoom, pan: model.pan, design: model.currentDesign),
                    displays: model.displays, assets: model.groupImages)
                    .frame(height: 160)
            }
            TabView {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            Button("Span All Displays") { for display in model.displays {
                                var value = model.placement(for: display)
                                value.group = 0
                                model.setPlacement(value)
                            }}
                            Button("Separate Images", action: model.separateDisplays)
                        }
                        ForEach(model.displays) { display in
                            GroupBox(display.name) {
                                VStack(alignment: .leading) {
                                    Picker("Wallpaper group", selection: Binding(get: { model.placement(for: display).group },
                                        set: { var item = model.placement(for: display); item.group = $0; model.setPlacement(item) })) {
                                        Text("Main panorama").tag(0)
                                        ForEach(1...max(1, model.displays.count, model.design.monitors.map(\.group).max() ?? 1), id: \.self) {
                                            Text("Group \($0)").tag($0)
                                        }
                                    }
                                    HStack {
                                        Text("Horizontal offset")
                                        TextField("Horizontal offset", value: binding(display, \.offsetX), format: .number)
                                            .frame(width: 75)
                                        Text("Vertical offset")
                                        TextField("Vertical offset", value: binding(display, \.offsetY), format: .number)
                                            .frame(width: 75)
                                    }
                                    HStack {
                                        Text("Relative screen size")
                                        Slider(value: binding(display, \.sizeScale), in: 0.5...2)
                                        Text(String(format: "%.2f×", model.placement(for: display).sizeScale)).monospacedDigit()
                                    }
                                }.padding(5)
                            }
                        }
                        Text("Offsets move the wallpaper sampling area. Positive vertical offsets move it up. Relative screen size helps align displays with different physical sizes.")
                            .font(.caption).foregroundStyle(.secondary)
                        ForEach(Array(Set(model.displays.map { model.placement(for: $0).group }).subtracting([0])).sorted(), id: \.self) { group in
                            HStack {
                                Button("Choose Group \(group) Image…") { model.chooseGroupImage(group) }
                                Text(model.groupImages[group]?.filename ?? "Using the main image").lineLimit(1)
                                if model.groupImages[group] != nil {
                                    Button("Use Main") { model.groupImages.removeValue(forKey: group) }
                                }
                            }
                        }
                    }.padding(10)
                }.tabItem { Text("Displays & Groups") }
                Form {
                    LabeledContent("Brightness") { Slider(value: $model.design.appearance.brightness, in: -0.5...0.5) }
                    LabeledContent("Saturation") { Slider(value: $model.design.appearance.saturation, in: 0...2) }
                    LabeledContent("Dim Wallpaper") { Slider(value: $model.design.appearance.dim, in: 0...0.8) }
                    ColorPicker("Background Color", selection: Binding(get: {
                        Color(red: model.design.appearance.red, green: model.design.appearance.green, blue: model.design.appearance.blue)
                    }, set: { color in
                        guard let rgb = NSColor(color).usingColorSpace(.sRGB) else { return }
                        model.design.appearance.red = rgb.redComponent
                        model.design.appearance.green = rgb.greenComponent
                        model.design.appearance.blue = rgb.blueComponent
                    }), supportsOpacity: false)
                    Button("Reset Appearance") { model.design.appearance = WallpaperAppearance() }
                }.padding(15).tabItem { Text("Appearance") }
            }.frame(height: 300)
            HStack {
                Button("Reset Display Alignment") { model.design.monitors = [] }
                Spacer()
                Button("Done") { model.showDesignOptions = false }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(22).frame(width: 650)
        .alert("ScreenSpan Wallpaper", isPresented: Binding(get: { model.featureError != nil },
            set: { if !$0 { model.featureError = nil } })) {
                Button("OK") { model.featureError = nil }
            } message: { Text(model.featureError ?? "") }
    }
}

@MainActor final class DesignPreviewImage: ObservableObject {
    @Published var image: CGImage?
    @Published var failed = false

    func render(source: SourceImage, wallpaper: SavedWallpaper, displays: [Display], assets: [Int: SourceImage]) async {
        do {
            try await Task.sleep(for: .milliseconds(90))
            try Task.checkCancellation()
            let result = try await Task.detached(priority: .userInitiated) {
                let images = try WallpaperRenderer.images(source: source.image, wallpaper: wallpaper, displays: displays,
                                                          assets: assets, preview: true)
                return try WallpaperRenderer.combined(images, displays: displays, maxPixels: 800_000)
            }.value
            guard !Task.isCancelled else { return }
            image = result
            failed = false
        } catch { if !Task.isCancelled { failed = true } }
    }
}

struct DesignedPreview: View {
    let source: SourceImage
    let wallpaper: SavedWallpaper
    let displays: [Display]
    let assets: [Int: SourceImage]
    @StateObject private var preview = DesignPreviewImage()

    private var renderKey: String {
        let settings = (try? JSONEncoder().encode(wallpaper.design)).map { $0.base64EncodedString() } ?? ""
        return "\(ObjectIdentifier(source.image))-\(wallpaper.framing)-\(wallpaper.zoom)-\(wallpaper.pan)-\(settings)-\(WallpaperDesign.setupKey(displays))-"
            + assets.sorted { $0.key < $1.key }.map { "\($0.key):\(ObjectIdentifier($0.value.image))" }.joined()
    }

    var body: some View {
        GeometryReader { geometry in
            let bounds = displays.reduce(CGRect.null) { $0.union($1.frame) }
            let scale = min(max(1, geometry.size.width - 44) / bounds.width,
                            max(1, geometry.size.height - 44) / bounds.height)
            let width = bounds.width * scale
            let height = bounds.height * scale
            ZStack {
                if let image = preview.image {
                    Image(decorative: image, scale: 1).resizable().interpolation(.high)
                        .frame(width: width, height: height)
                } else if preview.failed {
                    Text("Couldn’t render preview").foregroundStyle(.secondary)
                } else { ProgressView() }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .task(id: renderKey) { await preview.render(source: source, wallpaper: wallpaper, displays: displays, assets: assets) }
    }
}
