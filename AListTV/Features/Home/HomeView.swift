import SwiftUI

/// An option in a capsule switcher.
protocol SwitcherOption: Hashable, CaseIterable, Identifiable, RawRepresentable<String> where AllCases == [Self] {
    var title: String { get }
    var systemImage: String { get }
}

extension SwitcherOption {
    var id: String { rawValue }

    /// Position in the switcher, so content slides in from the side it sits on.
    var order: Int { Self.allCases.firstIndex(of: self) ?? 0 }
}

enum HomeMode: String, SwitcherOption {
    case gallery
    case files

    static let storageKey = "com.alist.tv.home-mode"

    var title: String {
        switch self {
        case .gallery: "Gallery"
        case .files: "Files"
        }
    }

    var systemImage: String {
        switch self {
        case .gallery: "film.stack"
        case .files: "folder"
        }
    }
}

/// The two ways to reach files inside the Files view.
enum FilesMode: String, SwitcherOption {
    case recents
    case browse

    static let storageKey = "com.alist.tv.files-mode"

    var title: String {
        switch self {
        case .recents: "Recents"
        case .browse: "Browse"
        }
    }

    var systemImage: String {
        switch self {
        case .recents: "clock.arrow.circlepath"
        case .browse: "folder"
        }
    }
}

/// Signed-in shell: a top bar that switches between the media Gallery and
/// Files, where a second switcher picks recently opened files or the folder
/// browser, with the player presented over all.
struct HomeView: View {
    @ObservedObject var browser: BrowserViewModel
    @ObservedObject var recents: RecentsViewModel
    @ObservedObject var player: PlayerCoordinator
    let gallery: GalleryViewModel
    @ObservedObject var galleryNavigator: GalleryNavigator
    let connection: StoredConnection?
    let onLogout: () -> Void
    let logoutError: String?
    let dismissLogoutError: () -> Void

    @AppStorage(HomeMode.storageKey) private var modeRaw = HomeMode.gallery.rawValue
    @AppStorage(FilesMode.storageKey) private var filesModeRaw = FilesMode.recents.rawValue
    @FocusState private var focusedMode: HomeMode?
    @FocusState private var focusedFilesMode: FilesMode?
    @FocusState private var isSignOutFocused: Bool
    @State private var previousModeOrder = 0
    @State private var previousFilesModeOrder = 0

    var body: some View {
        NavigationStack(path: $galleryNavigator.path) {
            home
                .toolbar(.hidden, for: .navigationBar)
                .navigationDestination(for: GalleryRoute.self, destination: galleryDestination)
        }
        .modifier(GalleryMatchPresentation(presenter: gallery.matchPresenter, viewModel: gallery))
        .onChange(of: player.isPresented) { _, isPresented in
            // The player saves its resume point on dismissal; refresh the bars.
            if !isPresented {
                recents.reload()
                gallery.reloadWatchState()
            }
        }
        .fullScreenCover(isPresented: $player.isPresented) {
            PlayerView(coordinator: player)
        }
    }

    private var home: some View {
        VStack(spacing: 0) {
            topBar
                .padding(.horizontal, Theme.screenPadding)
                .padding(.top, 18)

            ZStack {
                switch mode {
                case .gallery:
                    GalleryView(viewModel: gallery, onReveal: reveal)
                        .transition(slide(forward: mode.order >= previousModeOrder))
                case .files:
                    files
                        .transition(slide(forward: mode.order >= previousModeOrder))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background {
            ZStack {
                AmbientBackground()
                if mode == .gallery {
                    GalleryBackdrop(spotlight: gallery.spotlight)
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.4), value: mode)
        }
        .alert(
            "Unable to sign out",
            isPresented: Binding(
                get: { logoutError != nil },
                set: { if !$0 { dismissLogoutError() } }
            )
        ) {
            Button("OK", role: .cancel, action: dismissLogoutError)
        } message: {
            Text(logoutError ?? "")
        }
        .onExitCommand(perform: exitAction)
    }

    @ViewBuilder
    private func galleryDestination(_ route: GalleryRoute) -> some View {
        switch route {
        case let .title(title, focusPath):
            GalleryDetailView(viewModel: gallery, title: title, focusPath: focusPath, onReveal: reveal)
        case let .collection(collection):
            GalleryCollectionView(viewModel: gallery, collection: collection, onReveal: reveal)
        }
    }

    private var files: some View {
        VStack(spacing: 0) {
            FilesTabs(selection: filesMode, focusedMode: $focusedFilesMode, onSelect: select)
                .padding(.top, 28)

            ZStack {
                switch filesMode {
                case .recents:
                    RecentsView(
                        viewModel: recents,
                        onBrowse: { select(.browse) },
                        onReveal: reveal
                    )
                    .transition(slide(forward: filesMode.order >= previousFilesModeOrder))
                case .browse:
                    BrowserView(viewModel: browser, gallery: gallery)
                        .transition(slide(forward: filesMode.order >= previousFilesModeOrder))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    /// Content slides in from the side its tab sits on.
    private func slide(forward: Bool) -> AnyTransition {
        .asymmetric(
            insertion: .opacity.combined(with: .offset(x: forward ? 40 : -40)),
            removal: .opacity.combined(with: .offset(x: forward ? -40 : 40))
        )
    }

    // MARK: Top bar

    private var topBar: some View {
        ZStack {
            HStack(spacing: 24) {
                if let connection {
                    AccountBadge(connection: connection)
                }
                Spacer(minLength: 24)
                Button(action: onLogout) {
                    Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                }
                .buttonStyle(GlassIconButtonStyle(diameter: 64))
                .focused($isSignOutFocused)
                .accessibilityLabel("Sign Out")
                .accessibilityIdentifier("browser.logout")
            }

            ModePicker(selection: mode, focusedMode: $focusedMode, identifierPrefix: "home.mode", onSelect: select)
        }
        .frame(height: 80)
        .focusSection()
    }

    // MARK: Behavior

    private var mode: HomeMode {
        HomeMode(rawValue: modeRaw) ?? .gallery
    }

    private var filesMode: FilesMode {
        FilesMode(rawValue: filesModeRaw) ?? .recents
    }

    private func select(_ newMode: HomeMode) {
        guard newMode != mode else { return }
        previousModeOrder = mode.order
        withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) {
            modeRaw = newMode.rawValue
        }
    }

    private func select(_ newMode: FilesMode) {
        guard newMode != filesMode else { return }
        previousFilesModeOrder = filesMode.order
        withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) {
            filesModeRaw = newMode.rawValue
        }
    }

    private func reveal(_ object: AListObject) {
        browser.reveal(object)
        galleryNavigator.path.removeAll()
        select(.files)
        select(.browse)
    }

    /// Menu walks back out the way a tvOS tab app does: up a folder first,
    /// then from content to the Files switcher and the top bar, and only
    /// then out of the app.
    private var exitAction: (() -> Void)? {
        // While the player covers this screen, Menu must never fall through
        // to the system, or it would dismiss the player instead of its controls.
        if player.isPresented { return {} }
        let isTopBarFocused = focusedMode != nil || isSignOutFocused
        if mode == .files && !isTopBarFocused {
            if filesMode == .browse && browser.path != "/" { return { browser.moveToParent() } }
            if focusedFilesMode == nil { return { focusedFilesMode = filesMode } }
        }
        if !isTopBarFocused { return { focusedMode = mode } }
        return nil
    }
}

/// Capsule switcher modeled on the tvOS tab bar. The selected segment keeps a
/// soft fill that glides between options; the focused one turns solid white.
private struct ModePicker<Mode: SwitcherOption>: View {
    let selection: Mode
    var focusedMode: FocusState<Mode?>.Binding
    let identifierPrefix: String
    let onSelect: (Mode) -> Void

    @Namespace private var indicator

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Mode.allCases) { mode in
                Button {
                    onSelect(mode)
                } label: {
                    Label(mode.title, systemImage: mode.systemImage)
                }
                .buttonStyle(ModeSegmentStyle(isSelected: selection == mode, indicator: indicator))
                .focused(focusedMode, equals: mode)
                .accessibilityIdentifier("\(identifierPrefix).\(mode.rawValue)")
                .accessibilityAddTraits(selection == mode ? .isSelected : [])
            }
        }
        .padding(6)
        .background(.ultraThinMaterial, in: Capsule())
        .background(Color.black.opacity(0.25), in: Capsule())
        .overlay(Capsule().strokeBorder(Theme.hairline, lineWidth: 1))
        .focusSection()
        .defaultFocus(focusedMode, selection, priority: .userInitiated)
    }
}

private struct ModeSegmentStyle: ButtonStyle {
    let isSelected: Bool
    let indicator: Namespace.ID

    func makeBody(configuration: Configuration) -> some View {
        SegmentBody(configuration: configuration, isSelected: isSelected, indicator: indicator)
    }

    private struct SegmentBody: View {
        let configuration: Configuration
        let isSelected: Bool
        let indicator: Namespace.ID
        @Environment(\.isFocused) private var isFocused

        var body: some View {
            configuration.label
                .labelStyle(SegmentLabelStyle())
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(foreground)
                .padding(.horizontal, 34)
                .frame(height: 60)
                .background {
                    if isSelected {
                        Capsule()
                            .fill(Color.white.opacity(0.16))
                            .matchedGeometryEffect(id: "selection", in: indicator)
                    }
                }
                .background {
                    Capsule()
                        .fill(Color.white)
                        .opacity(isFocused ? 1 : 0)
                }
                .shadow(color: .black.opacity(isFocused ? 0.4 : 0), radius: 16, y: 8)
                .scaleEffect(configuration.isPressed ? 0.96 : (isFocused ? 1.08 : 1))
                .animation(Theme.focusSpring, value: isFocused)
                .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
        }

        private var foreground: Color {
            if isFocused { return .black }
            return isSelected ? .white : Theme.secondaryText
        }
    }

    private struct SegmentLabelStyle: LabelStyle {
        func makeBody(configuration: Configuration) -> some View {
            HStack(spacing: 12) {
                configuration.icon
                    .font(.system(size: 24, weight: .semibold))
                configuration.title
            }
        }
    }
}

/// Text tabs for the views inside Files, quieter than the top bar's capsule.
/// An accent underline glides to the selected tab; focus lifts the title.
private struct FilesTabs: View {
    let selection: FilesMode
    var focusedMode: FocusState<FilesMode?>.Binding
    let onSelect: (FilesMode) -> Void

    @Namespace private var indicator

    var body: some View {
        HStack(spacing: 8) {
            ForEach(FilesMode.allCases) { mode in
                Button {
                    onSelect(mode)
                } label: {
                    Text(mode.title)
                }
                .buttonStyle(FilesTabStyle(isSelected: selection == mode, indicator: indicator))
                .focused(focusedMode, equals: mode)
                .accessibilityIdentifier("files.mode.\(mode.rawValue)")
                .accessibilityAddTraits(selection == mode ? .isSelected : [])
            }
        }
        .padding(.horizontal, Theme.screenPadding)
        // Spans the width, so Down from anywhere in the top bar lands here,
        // on the selected tab rather than the nearest one.
        .frame(maxWidth: .infinity, alignment: .leading)
        .focusSection()
        .defaultFocus(focusedMode, selection, priority: .userInitiated)
    }
}

private struct FilesTabStyle: ButtonStyle {
    let isSelected: Bool
    let indicator: Namespace.ID

    func makeBody(configuration: Configuration) -> some View {
        TabBody(configuration: configuration, isSelected: isSelected, indicator: indicator)
    }

    private struct TabBody: View {
        let configuration: Configuration
        let isSelected: Bool
        let indicator: Namespace.ID
        @Environment(\.isFocused) private var isFocused

        var body: some View {
            configuration.label
                .font(.system(size: 30, weight: isSelected || isFocused ? .bold : .semibold))
                .foregroundStyle(isSelected || isFocused ? Color.white : Theme.secondaryText)
                .padding(.horizontal, 22)
                .padding(.top, 10)
                .padding(.bottom, 16)
                .overlay(alignment: .bottom) {
                    if isSelected {
                        Capsule()
                            .fill(isFocused ? Color.white : Theme.accent)
                            .frame(height: 4)
                            .padding(.horizontal, 22)
                            .matchedGeometryEffect(id: "underline", in: indicator)
                    }
                }
                .background {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.white.opacity(0.12))
                        .opacity(isFocused ? 1 : 0)
                }
                .shadow(color: .black.opacity(isFocused ? 0.35 : 0), radius: 12, y: 6)
                .scaleEffect(configuration.isPressed ? 0.96 : (isFocused ? 1.1 : 1))
                .animation(Theme.focusSpring, value: isFocused)
                .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
        }
    }
}

/// Who is signed in to which server, shown quietly in the corner.
private struct AccountBadge: View {
    let connection: StoredConnection

    var body: some View {
        HStack(spacing: 18) {
            Text(initial)
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .frame(width: 56, height: 56)
                .background(
                    LinearGradient(
                        colors: [Theme.accent, Color(red: 0.30, green: 0.36, blue: 0.95)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    in: Circle()
                )
                .overlay(Circle().strokeBorder(.white.opacity(0.22), lineWidth: 1))

            VStack(alignment: .leading, spacing: 2) {
                Text(connection.username)
                    .font(.system(size: 24, weight: .semibold))
                    .lineLimit(1)
                Text(serverName)
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(Theme.tertiaryText)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: 460, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Signed in as \(connection.username) on \(serverName)")
    }

    private var initial: String {
        connection.username.first.map { String($0).uppercased() } ?? "?"
    }

    private var serverName: String {
        let host = connection.baseURL.host ?? connection.baseURL.absoluteString
        return connection.baseURL.port.map { "\(host):\($0)" } ?? host
    }
}
