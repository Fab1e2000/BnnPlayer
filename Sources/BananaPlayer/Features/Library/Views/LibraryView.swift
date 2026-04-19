import SwiftUI
#if os(macOS)
import AppKit
import ImageIO
#endif

struct LibraryView: View {
    @ObservedObject var viewModel: LibraryViewModel
    @ObservedObject var playerViewModel: PlayerViewModel
    @StateObject private var sceneTransitionController = SceneTransitionController()
    @State private var spaceKeyMonitor: Any?
    @State private var albumGridKeyMonitor: Any?
    @State private var keyboardFocusedAlbumID: String?
    @State private var albumGridColumnCount = 1
    @Namespace private var albumCoverTransition

    private let gridItems = [GridItem(.adaptive(minimum: 170), spacing: 16)]
    private let basePlayerBarHorizontalPadding: CGFloat = 16
    private let albumSidebarWidth: CGFloat = 160
    private let sceneTransitionAnimation = Animation.spring(response: 0.58, dampingFraction: 0.92, blendDuration: 0.2)
    private let sceneTransitionSettlingDuration: TimeInterval = 0.72
    private let focusScrollAnimation = Animation.easeInOut(duration: 0.24)

    var body: some View {
        NavigationStack {
            ZStack {
                if let album = viewModel.selectedAlbum {
                    AlbumTracksView(
                        albums: viewModel.albums,
                        album: album,
                        tracks: viewModel.tracks(for: album),
                        currentTrackID: playerViewModel.currentTrack?.id,
                        coverTransitionNamespace: albumCoverTransition,
                        isSceneTransitioning: sceneTransitionController.isTransitioning,
                        sceneTransitionGeneration: sceneTransitionController.currentGeneration,
                        isCurrentSceneTransitionGeneration: sceneTransitionController.isCurrentGeneration,
                        onBack: closeAlbumWithTransition,
                        isSecondaryActive: { viewModel.selectedAlbumID != nil },
                        onSelectAlbum: viewModel.openAlbum,
                        onPlayTrack: { track in
                            viewModel.play(track: track, in: album)
                        }
                    )
                    .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .move(edge: .trailing).combined(with: .opacity)))
                } else {
                    albumGrid
                        .allowsHitTesting(!sceneTransitionController.isTransitioning)
                        .transition(.asymmetric(insertion: .move(edge: .leading).combined(with: .opacity), removal: .move(edge: .leading).combined(with: .opacity)))
                }
            }
            .navigationTitle("Banana Player")
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    Button {
                        viewModel.addFolderFromDialog()
                    } label: {
                        Image(systemName: "folder.badge.plus")
                    }
                    .hoverInteractive()
                    .accessibilityLabel("添加文件夹")

                    Button {
                        viewModel.scanLibrary()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(viewModel.libraryFolders.isEmpty || viewModel.isScanning)
                    .hoverInteractive(enabled: !(viewModel.libraryFolders.isEmpty || viewModel.isScanning))
                    .accessibilityLabel("重新扫描")
                }
            }
            .overlay(alignment: .topLeading) {
                if viewModel.isScanning {
                    ProgressView("正在扫描音乐库…")
                        .padding(10)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
                        .padding()
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            PlayerControlBar(viewModel: playerViewModel)
                .padding(.leading, viewModel.selectedAlbum == nil ? basePlayerBarHorizontalPadding : basePlayerBarHorizontalPadding + albumSidebarWidth)
                .padding(.trailing, basePlayerBarHorizontalPadding)
                .padding(.bottom, 10)
                .animation(sceneTransitionAnimation, value: viewModel.selectedAlbumID)
        }
        .alert("提示", isPresented: Binding(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.errorMessage = nil } }
        )) {
            Button("知道了", role: .cancel) {}
        } message: {
            Text(viewModel.errorMessage ?? "发生未知错误")
        }
        .onAppear {
            viewModel.bootstrap()
            installSpaceKeyMonitorIfNeeded()
            syncAlbumGridKeyboardState()
        }
        .onChange(of: viewModel.selectedAlbumID) { _ in
            syncAlbumGridKeyboardState()
        }
        .onChange(of: viewModel.filteredAlbums.map(\.id)) { _ in
            syncAlbumGridKeyboardState()
            refreshAlbumGridKeyMonitor()
        }
        .onChange(of: albumGridColumnCount) { _ in
            refreshAlbumGridKeyMonitor()
        }
        .onDisappear {
            sceneTransitionController.cancelPendingCompletion()
            removeSpaceKeyMonitorIfNeeded()
            removeAlbumGridKeyMonitorIfNeeded()
        }
    }

    private func installSpaceKeyMonitorIfNeeded() {
        #if os(macOS)
        guard spaceKeyMonitor == nil else {
            return
        }

        spaceKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let modifierFlags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            let isPureSpace = event.keyCode == 49 && modifierFlags.isEmpty

            guard isPureSpace else {
                return event
            }

            playerViewModel.togglePlayPause()
            return nil
        }
        #endif
    }

    private func removeSpaceKeyMonitorIfNeeded() {
        #if os(macOS)
        guard let spaceKeyMonitor else {
            return
        }

        NSEvent.removeMonitor(spaceKeyMonitor)
        self.spaceKeyMonitor = nil
        #endif
    }

    private func syncAlbumGridKeyboardState() {
        guard viewModel.selectedAlbum == nil else {
            removeAlbumGridKeyMonitorIfNeeded()
            return
        }

        if let keyboardFocusedAlbumID,
           viewModel.filteredAlbums.contains(where: { $0.id == keyboardFocusedAlbumID }) {
            // Keep the current focus if it still exists.
        } else {
            keyboardFocusedAlbumID = viewModel.filteredAlbums.first?.id
        }

        installAlbumGridKeyMonitorIfNeeded()
    }

    private func installAlbumGridKeyMonitorIfNeeded() {
        #if os(macOS)
        guard albumGridKeyMonitor == nil else {
            return
        }

        albumGridKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard viewModel.selectedAlbum == nil, !sceneTransitionController.isTransitioning else {
                return event
            }

            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            let unsupportedModifiers: NSEvent.ModifierFlags = [.command, .option, .control, .shift]
            guard flags.intersection(unsupportedModifiers).isEmpty else {
                return event
            }

            switch event.keyCode {
            case 123:
                moveAlbumGridFocus(step: -1)
                return nil
            case 0:
                moveAlbumGridFocus(step: -1)
                return nil
            case 38:
                moveAlbumGridFocus(step: -1)
                return nil
            case 124:
                moveAlbumGridFocus(step: 1)
                return nil
            case 2:
                moveAlbumGridFocus(step: 1)
                return nil
            case 37:
                moveAlbumGridFocus(step: 1)
                return nil
            case 126:
                moveAlbumGridFocus(step: -max(albumGridColumnCount, 1))
                return nil
            case 13:
                moveAlbumGridFocus(step: -max(albumGridColumnCount, 1))
                return nil
            case 34:
                moveAlbumGridFocus(step: -max(albumGridColumnCount, 1))
                return nil
            case 125:
                moveAlbumGridFocus(step: max(albumGridColumnCount, 1))
                return nil
            case 1:
                moveAlbumGridFocus(step: max(albumGridColumnCount, 1))
                return nil
            case 40:
                moveAlbumGridFocus(step: max(albumGridColumnCount, 1))
                return nil
            case 36, 76, 14, 31:
                openFocusedAlbumFromKeyboard()
                return nil
            default:
                return event
            }
        }
        #endif
    }

    private func refreshAlbumGridKeyMonitor() {
        #if os(macOS)
        guard viewModel.selectedAlbum == nil else {
            return
        }
        removeAlbumGridKeyMonitorIfNeeded()
        installAlbumGridKeyMonitorIfNeeded()
        #endif
    }

    private func removeAlbumGridKeyMonitorIfNeeded() {
        #if os(macOS)
        guard let albumGridKeyMonitor else {
            return
        }
        NSEvent.removeMonitor(albumGridKeyMonitor)
        self.albumGridKeyMonitor = nil
        #endif
    }

    private func moveAlbumGridFocus(step: Int) {
        let albums = viewModel.filteredAlbums
        guard !albums.isEmpty else {
            keyboardFocusedAlbumID = nil
            return
        }

        let currentIndex = albums.firstIndex(where: { $0.id == keyboardFocusedAlbumID }) ?? 0
        let nextIndex = min(max(currentIndex + step, 0), albums.count - 1)
        keyboardFocusedAlbumID = albums[nextIndex].id
    }

    private func openFocusedAlbumFromKeyboard() {
        guard
            let keyboardFocusedAlbumID,
            let album = viewModel.filteredAlbums.first(where: { $0.id == keyboardFocusedAlbumID })
        else {
            return
        }

        openAlbumWithTransition(album)
    }

    private func openAlbumWithTransition(_ album: Album) {
        beginSceneTransitionWindow()
        withAnimation(sceneTransitionAnimation) {
            viewModel.openAlbum(album)
        }
    }

    private func closeAlbumWithTransition() {
        keyboardFocusedAlbumID = viewModel.selectedAlbumID
        beginSceneTransitionWindow()
        withAnimation(sceneTransitionAnimation) {
            viewModel.closeAlbum()
        }
    }

    private func beginSceneTransitionWindow() {
        sceneTransitionController.begin(duration: sceneTransitionSettlingDuration)
    }

    private var albumGrid: some View {
        Group {
            if viewModel.filteredAlbums.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "music.note.list")
                        .font(.system(size: 42))
                        .foregroundStyle(.secondary)
                    Text("暂无专辑")
                        .font(.title3)
                    Text("添加音乐文件夹并扫描后，这里会显示专辑封面。")
                        .foregroundStyle(.secondary)
                }
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        GeometryReader { geometry in
                            Color.clear
                                .onAppear {
                                    updateAlbumGridColumnCount(containerWidth: geometry.size.width)
                                }
                                .onChange(of: geometry.size.width) { newWidth in
                                    updateAlbumGridColumnCount(containerWidth: newWidth)
                                }
                        }
                        .frame(height: 0)

                        LazyVGrid(columns: gridItems, spacing: 18) {
                            ForEach(viewModel.filteredAlbums) { album in
                                let isKeyboardFocused = album.id == keyboardFocusedAlbumID

                                Button {
                                    openAlbumWithTransition(album)
                                } label: {
                                    AlbumCardView(
                                        album: album,
                                        isKeyboardFocused: isKeyboardFocused,
                                        coverTransitionNamespace: albumCoverTransition
                                    )
                                }
                                .buttonStyle(.plain)
                                .hoverInteractive(brightness: 0.07, scale: 1.01)
                                .accessibilityLabel("打开专辑 \(album.title)")
                                .id(album.id)
                            }
                        }
                        .padding(18)
                    }
                    .onAppear {
                        if keyboardFocusedAlbumID == nil {
                            keyboardFocusedAlbumID = viewModel.filteredAlbums.first?.id
                        }
                    }
                    .onChange(of: keyboardFocusedAlbumID) { newValue in
                        guard let newValue else {
                            return
                        }

                        withAnimation(focusScrollAnimation) {
                            proxy.scrollTo(newValue, anchor: .center)
                        }
                    }
                }
            }
        }
    }

    private func updateAlbumGridColumnCount(containerWidth: CGFloat) {
        let contentWidth = max(containerWidth - 36, 1)
        let effectiveItemWidth: CGFloat = 170 + 16
        let columns = max(1, Int((contentWidth + 16) / effectiveItemWidth))
        if albumGridColumnCount != columns {
            albumGridColumnCount = columns
        }
    }
}

private struct AlbumCardView: View {
    let album: Album
    var isKeyboardFocused = false
    let coverTransitionNamespace: Namespace.ID

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.secondary.opacity(0.12))
                .aspectRatio(1, contentMode: .fit)
                .matchedGeometryEffect(id: "album-cover-\(album.id)", in: coverTransitionNamespace)
                .overlay {
                    if let coverURL = album.coverURL {
                        AlbumArtworkView(url: coverURL)
                    } else {
                        Image(systemName: "opticaldisc")
                            .font(.system(size: 30))
                            .foregroundStyle(.secondary)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay {
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(
                            isKeyboardFocused ? Color.blue : Color.clear,
                            lineWidth: isKeyboardFocused ? 2 : 0
                        )
                }

            Text(album.title)
                .font(.headline)
                .lineLimit(1)
        }
    }
}

private struct AlbumArtworkView: View {
    let url: URL

    #if os(macOS)
    private static let artworkThumbnailMaxPixelSize = 512

    private static let localArtworkCache: NSCache<NSURL, NSImage> = {
        let cache = NSCache<NSURL, NSImage>()
        cache.countLimit = 160
        cache.totalCostLimit = 80 * 1024 * 1024
        return cache
    }()
    #endif

    var body: some View {
        if url.isFileURL {
            if let localImage = localArtwork {
                localImage
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                placeholder
            }
        } else {
            AsyncImage(url: url) { image in
                image
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } placeholder: {
                placeholder
            }
        }
    }

    private var placeholder: some View {
        Image(systemName: "opticaldisc")
            .font(.system(size: 30))
            .foregroundStyle(.secondary)
    }

    #if os(macOS)
    private var localArtwork: Image? {
        let cacheKey = url as NSURL

        if let cachedImage = Self.localArtworkCache.object(forKey: cacheKey) {
            return Image(nsImage: cachedImage)
        }

        if let thumbnail = Self.loadThumbnailImage(from: url, maxPixelSize: Self.artworkThumbnailMaxPixelSize) {
            Self.localArtworkCache.setObject(thumbnail.image, forKey: cacheKey, cost: thumbnail.cost)
            return Image(nsImage: thumbnail.image)
        }

        guard let loadedImage = NSImage(contentsOf: url) else {
            return nil
        }

        Self.localArtworkCache.setObject(loadedImage, forKey: cacheKey, cost: Self.estimatedCost(for: loadedImage))
        return Image(nsImage: loadedImage)
    }

    private static func loadThumbnailImage(from url: URL, maxPixelSize: Int) -> (image: NSImage, cost: Int)? {
        guard
            let source = CGImageSourceCreateWithURL(url as CFURL, nil),
            let cgImage = CGImageSourceCreateThumbnailAtIndex(
                source,
                0,
                [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceShouldCacheImmediately: true,
                    kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
                ] as CFDictionary
            )
        else {
            return nil
        }

        let image = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        let cost = max(1, cgImage.width * cgImage.height * 4)
        return (image, cost)
    }

    private static func estimatedCost(for image: NSImage) -> Int {
        guard let representation = image.representations.first else {
            return 1
        }

        let width = max(1, representation.pixelsWide)
        let height = max(1, representation.pixelsHigh)
        return width * height * 4
    }
    #else
    private var localArtwork: Image? {
        nil
    }
    #endif
}

private struct AlbumTracksView: View {
    private static let estimatedTrackRowHeight: CGFloat = 56
    private static let bottomBarOcclusionHeight: CGFloat = 30
    private static let trackListTopAnchorID = "track-list-top-anchor"

    let albums: [Album]
    let album: Album
    let tracks: [Track]
    let currentTrackID: String?
    let coverTransitionNamespace: Namespace.ID
    let isSceneTransitioning: Bool
    let sceneTransitionGeneration: Int
    let isCurrentSceneTransitionGeneration: (Int) -> Bool
    let onBack: () -> Void
    let isSecondaryActive: () -> Bool
    let onSelectAlbum: (Album) -> Void
    let onPlayTrack: (Track) -> Void
    @State private var highlightedTrackID: String?
    @State private var albumArrowKeyMonitor: Any?
    @State private var keyboardSelectedAlbumID: String?
    @State private var keyboardSelectionMode: KeyboardSelectionMode = .album
    @State private var trackListViewportHeight: CGFloat = 0
    @State private var trackListTopVisibleIndex = 0
    @State private var pendingTrackScrollTargetID: String?
    private let albumSelectionAnimation = Animation.spring(response: 0.5, dampingFraction: 0.9, blendDuration: 0.2)
    private let trackScrollAnimation = Animation.easeInOut(duration: 0.24)

    var body: some View {
        HStack(spacing: 0) {
            albumSidebar

            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Button {
                        onBack()
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.primary)
                            .frame(width: 32, height: 32)
                            .background(
                                Circle()
                                    .fill(Color.secondary.opacity(0.14))
                            )
                            .overlay(
                                Circle()
                                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                            )
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .frame(width: 40, height: 40)
                    .hoverInteractive(brightness: 0.1, scale: 1.02)
                    .accessibilityLabel("返回专辑")

                    VStack(alignment: .leading, spacing: 2) {
                        Text(album.title)
                            .font(.headline)
                            .lineLimit(1)
                        Text("\(album.trackCount) 首")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 18)
                .padding(.top, 12)
                .padding(.bottom, 4)

                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 6) {
                            Color.clear
                                .frame(height: 0)
                                .id(Self.trackListTopAnchorID)

                            ForEach(tracks) { track in
                                let isHighlighted = keyboardSelectionMode == .track && track.id == highlightedTrackID
                                let isPlayingTrack = track.id == currentTrackID
                                let trackNumberText = track.trackNumber.map(String.init) ?? "-"
                                let primaryColor: Color = isPlayingTrack ? .accentColor : .primary
                                let secondaryColor: Color = isPlayingTrack ? .accentColor : .secondary

                                HStack(spacing: 12) {
                                    Text(trackNumberText)
                                        .foregroundStyle(secondaryColor)
                                        .frame(width: 28, alignment: .trailing)

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(track.title)
                                            .foregroundStyle(primaryColor)
                                        Text(track.format.uppercased())
                                            .font(.caption)
                                            .foregroundStyle(secondaryColor)
                                    }

                                    Spacer()

                                    Text(durationText(track.duration))
                                        .foregroundStyle(secondaryColor)
                                        .font(.caption)
                                }
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, 8)
                                .padding(.horizontal, 12)
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(isHighlighted ? Color.accentColor.opacity(0.18) : .clear)
                                )
                                .contentShape(Rectangle())
                                .hoverInteractive(brightness: 0.06)
                                .onTapGesture {
                                    setKeyboardSelectionMode(.track)
                                    #if os(macOS)
                                    if NSApp.currentEvent?.clickCount == 2 {
                                        highlightedTrackID = nil
                                        onPlayTrack(track)
                                    } else {
                                        highlightedTrackID = track.id
                                    }
                                    #else
                                    highlightedTrackID = track.id
                                    #endif
                                }
                                .id(track.id)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        .padding(.horizontal, 10)
                        .padding(.top, 6)
                        .padding(.bottom, Self.bottomBarOcclusionHeight)
                    }
                    .id(album.id)
                    .background(
                        GeometryReader { geometry in
                            Color.clear
                                .onAppear {
                                    trackListViewportHeight = geometry.size.height
                                }
                                .onChange(of: geometry.size.height) { newValue in
                                    trackListViewportHeight = newValue
                                }
                        }
                    )
                    .onAppear {
                        trackListTopVisibleIndex = 0
                        scrollTracksToTop(with: proxy)
                    }
                    .onChange(of: album.id) { _ in
                        trackListTopVisibleIndex = 0
                        pendingTrackScrollTargetID = nil
                        scrollTracksToTop(with: proxy)
                    }
                    .onChange(of: tracks.map(\.id)) { _ in
                        trackListTopVisibleIndex = min(trackListTopVisibleIndex, max(tracks.count - 1, 0))
                        scrollTracksToTop(with: proxy)
                    }
                    .onChange(of: pendingTrackScrollTargetID) { targetID in
                        guard let targetID else {
                            return
                        }

                        if isSceneTransitioning {
                            proxy.scrollTo(targetID, anchor: .top)
                        } else {
                            withAnimation(trackScrollAnimation) {
                                proxy.scrollTo(targetID, anchor: .top)
                            }
                        }
                        pendingTrackScrollTargetID = nil
                    }
                }
            }
            .compositingGroup()
        }
        .navigationTitle(album.title)
        .onAppear {
            keyboardSelectedAlbumID = album.id
            keyboardSelectionMode = .album
            installAlbumArrowKeyMonitorIfNeeded()
        }
        .onChange(of: album.id) { newValue in
            keyboardSelectedAlbumID = newValue
            refreshAlbumArrowKeyMonitor()
        }
        .onChange(of: tracks.map(\.id)) { _ in
            refreshAlbumArrowKeyMonitor()
            if keyboardSelectionMode == .track {
                ensureTrackSelectionSeeded()
            } else if let highlightedTrackID, !tracks.contains(where: { $0.id == highlightedTrackID }) {
                self.highlightedTrackID = nil
            }
        }
        .onChange(of: keyboardSelectionMode) { _ in
            refreshAlbumArrowKeyMonitor()
            if keyboardSelectionMode == .track {
                ensureTrackSelectionSeeded()
            }
        }
        .onDisappear {
            removeAlbumArrowKeyMonitorIfNeeded()
        }
    }

    private func installAlbumArrowKeyMonitorIfNeeded() {
        #if os(macOS)
        guard albumArrowKeyMonitor == nil else {
            return
        }

        albumArrowKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard isSecondaryActive() else {
                return event
            }

            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            let unsupportedModifiers: NSEvent.ModifierFlags = [.command, .option, .control, .shift]
            guard flags.intersection(unsupportedModifiers).isEmpty else {
                return event
            }

            switch event.keyCode {
            case 124:
                setKeyboardSelectionMode(.track)
                ensureTrackSelectionSeeded()
                return nil
            case 2:
                setKeyboardSelectionMode(.track)
                ensureTrackSelectionSeeded()
                return nil
            case 37:
                setKeyboardSelectionMode(.track)
                ensureTrackSelectionSeeded()
                return nil
            case 123:
                setKeyboardSelectionMode(.album)
                return nil
            case 0:
                setKeyboardSelectionMode(.album)
                return nil
            case 38:
                setKeyboardSelectionMode(.album)
                return nil
            case 126:
                if keyboardSelectionMode == .track {
                    selectAdjacentTrack(step: -1)
                } else {
                    selectAdjacentAlbum(step: -1)
                }
                return nil
            case 13:
                if keyboardSelectionMode == .track {
                    selectAdjacentTrack(step: -1)
                } else {
                    selectAdjacentAlbum(step: -1)
                }
                return nil
            case 34:
                if keyboardSelectionMode == .track {
                    selectAdjacentTrack(step: -1)
                } else {
                    selectAdjacentAlbum(step: -1)
                }
                return nil
            case 125:
                if keyboardSelectionMode == .track {
                    selectAdjacentTrack(step: 1)
                } else {
                    selectAdjacentAlbum(step: 1)
                }
                return nil
            case 1:
                if keyboardSelectionMode == .track {
                    selectAdjacentTrack(step: 1)
                } else {
                    selectAdjacentAlbum(step: 1)
                }
                return nil
            case 40:
                if keyboardSelectionMode == .track {
                    selectAdjacentTrack(step: 1)
                } else {
                    selectAdjacentAlbum(step: 1)
                }
                return nil
            case 36, 76, 14, 31:
                if keyboardSelectionMode == .track {
                    playHighlightedTrack()
                    return nil
                }
                return event
            case 53, 12, 32:
                onBack()
                return nil
            default:
                return event
            }
        }
        #endif
    }

    private func setKeyboardSelectionMode(_ mode: KeyboardSelectionMode) {
        guard keyboardSelectionMode != mode else {
            return
        }
        keyboardSelectionMode = mode
    }

    private func refreshAlbumArrowKeyMonitor() {
        #if os(macOS)
        removeAlbumArrowKeyMonitorIfNeeded()
        installAlbumArrowKeyMonitorIfNeeded()
        #endif
    }

    private func removeAlbumArrowKeyMonitorIfNeeded() {
        #if os(macOS)
        guard let albumArrowKeyMonitor else {
            return
        }

        NSEvent.removeMonitor(albumArrowKeyMonitor)
        self.albumArrowKeyMonitor = nil
        #endif
    }

    private func selectAdjacentAlbum(step: Int) {
        let baseAlbumID = keyboardSelectedAlbumID ?? album.id
        guard
            let currentIndex = albums.firstIndex(where: { $0.id == baseAlbumID }),
            !albums.isEmpty
        else {
            return
        }

        let albumCount = albums.count
        let normalizedStep = step % albumCount
        let nextIndex = (currentIndex + normalizedStep + albumCount) % albumCount

        keyboardSelectedAlbumID = albums[nextIndex].id
        withAnimation(albumSelectionAnimation) {
            onSelectAlbum(albums[nextIndex])
        }
    }

    private func ensureTrackSelectionSeeded() {
        guard !tracks.isEmpty else {
            highlightedTrackID = nil
            return
        }

        if let highlightedTrackID, tracks.contains(where: { $0.id == highlightedTrackID }) {
            return
        }

        if let currentTrackID, tracks.contains(where: { $0.id == currentTrackID }) {
            highlightedTrackID = currentTrackID
        } else {
            highlightedTrackID = tracks.first?.id
        }
    }

    private func selectAdjacentTrack(step: Int) {
        guard !tracks.isEmpty else {
            return
        }

        ensureTrackSelectionSeeded()
        guard let baseTrackID = highlightedTrackID,
              let currentIndex = tracks.firstIndex(where: { $0.id == baseTrackID })
        else {
            return
        }

        let trackCount = tracks.count
        let normalizedStep = step % trackCount
        let nextIndex = (currentIndex + normalizedStep + trackCount) % trackCount

        guard tracks.indices.contains(nextIndex) else {
            return
        }

        highlightedTrackID = tracks[nextIndex].id

        let wrappedToTop = step > 0 && nextIndex <= currentIndex
        if wrappedToTop {
            trackListTopVisibleIndex = 0
            pendingTrackScrollTargetID = tracks[0].id
            return
        }

        let wrappedToBottom = step < 0 && nextIndex >= currentIndex
        if wrappedToBottom {
            let bottomTopIndex = max(trackCount - visibleTrackCapacity, 0)
            trackListTopVisibleIndex = bottomTopIndex
            pendingTrackScrollTargetID = tracks[bottomTopIndex].id
            return
        }

        if step > 0 {
            let visibleCapacity = visibleTrackCapacity
            let bottomVisibleIndex = trackListTopVisibleIndex + visibleCapacity - 1
            if nextIndex > bottomVisibleIndex {
                let nextTopIndex = min(trackListTopVisibleIndex + 1, max(tracks.count - 1, 0))
                trackListTopVisibleIndex = nextTopIndex
                pendingTrackScrollTargetID = tracks[nextTopIndex].id
            }
        } else if step < 0 {
            if nextIndex < trackListTopVisibleIndex {
                let nextTopIndex = max(trackListTopVisibleIndex - 1, 0)
                trackListTopVisibleIndex = nextTopIndex
                pendingTrackScrollTargetID = tracks[nextTopIndex].id
            }
        }
    }

    private func playHighlightedTrack() {
        ensureTrackSelectionSeeded()

        guard
            let highlightedTrackID,
            let track = tracks.first(where: { $0.id == highlightedTrackID })
        else {
            return
        }

        onPlayTrack(track)
    }

    private func scrollTracksToTop(with proxy: ScrollViewProxy) {
        let generation = sceneTransitionGeneration
        DispatchQueue.main.async {
            guard isCurrentSceneTransitionGeneration(generation) else {
                return
            }
            proxy.scrollTo(Self.trackListTopAnchorID, anchor: .top)
            DispatchQueue.main.async {
                guard isCurrentSceneTransitionGeneration(generation) else {
                    return
                }
                proxy.scrollTo(Self.trackListTopAnchorID, anchor: .top)
            }
        }
    }

    private var visibleTrackCapacity: Int {
        let effectiveHeight = max(0, trackListViewportHeight - Self.bottomBarOcclusionHeight)
        let capacity = Int(effectiveHeight / Self.estimatedTrackRowHeight)
        return max(1, capacity)
    }

    private var albumSidebar: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 18) {
                    ForEach(albums) { sideAlbum in
                        let isSelected = sideAlbum.id == album.id
                        let showSelectedAlbumBorder = keyboardSelectionMode == .album && isSelected
                        let baseItemSize: CGFloat = 106
                        let selectedScale: CGFloat = 126 / 106

                        Button {
                            keyboardSelectedAlbumID = sideAlbum.id
                                withAnimation(albumSelectionAnimation) {
                                onSelectAlbum(sideAlbum)
                            }
                        } label: {
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.secondary.opacity(0.12))
                                .aspectRatio(1, contentMode: .fit)
                                .frame(width: baseItemSize, height: baseItemSize)
                                    .matchedGeometryEffect(id: "album-cover-\(sideAlbum.id)", in: coverTransitionNamespace)
                                .overlay {
                                    if let coverURL = sideAlbum.coverURL {
                                        AlbumArtworkView(url: coverURL)
                                    } else {
                                        Image(systemName: "opticaldisc")
                                            .font(.system(size: 20))
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(
                                            showSelectedAlbumBorder ? Color.blue : Color.primary.opacity(0.08),
                                            lineWidth: showSelectedAlbumBorder ? 2 : 1
                                        )
                                }
                                .scaleEffect(isSelected ? selectedScale : 1)
                                .frame(maxWidth: .infinity)
                                .zIndex(isSelected ? 1 : 0)
                        }
                        .buttonStyle(.plain)
                        .hoverInteractive(brightness: 0.08, scale: 1.02)
                        .accessibilityLabel("切换到专辑 \(sideAlbum.title)")
                        .id(sideAlbum.id)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.top, 12)
                .padding(.bottom, Self.bottomBarOcclusionHeight)
            }
            .frame(width: 160)
            .frame(maxHeight: .infinity, alignment: .top)
            .ignoresSafeArea(.container, edges: .bottom)
            .background(Color.secondary.opacity(0.05))
            .onAppear {
                proxy.scrollTo(album.id, anchor: .center)
            }
            .onChange(of: album.id) { newValue in
                if isSceneTransitioning {
                    proxy.scrollTo(newValue, anchor: .center)
                } else {
                    withAnimation(trackScrollAnimation) {
                        proxy.scrollTo(newValue, anchor: .center)
                    }
                }
            }
        }
    }

    private func durationText(_ seconds: Double) -> String {
        let totalSeconds = max(0, Int(seconds.rounded(.down)))
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let secs = totalSeconds % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }

        return String(format: "%02d:%02d", minutes, secs)
    }
}

@MainActor
private final class SceneTransitionController: ObservableObject {
    @Published private(set) var isTransitioning = false

    private(set) var currentGeneration = 0
    private var pendingCompletionWorkItem: DispatchWorkItem?

    func begin(duration: TimeInterval) {
        currentGeneration += 1
        isTransitioning = true

        pendingCompletionWorkItem?.cancel()

        let generation = currentGeneration
        let workItem = DispatchWorkItem { [weak self] in
            guard let self, self.currentGeneration == generation else {
                return
            }
            self.isTransitioning = false
            self.pendingCompletionWorkItem = nil
        }

        pendingCompletionWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: workItem)
    }

    func cancelPendingCompletion() {
        pendingCompletionWorkItem?.cancel()
        pendingCompletionWorkItem = nil
        isTransitioning = false
    }

    func isCurrentGeneration(_ generation: Int) -> Bool {
        currentGeneration == generation
    }
}

private enum KeyboardSelectionMode {
    case album
    case track
}
