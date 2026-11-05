import SwiftUI
import AgentPetCore

/// Native macOS-style settings: a preferences-style toolbar of tabs over
/// grouped forms (dark).
struct SetupView: View {
    @ObservedObject private var model = SettingsModel.shared
    @ObservedObject private var pet = PetController.shared
    @ObservedObject private var imagePets = ImagePetStore.shared
    @ObservedObject private var appLang = AppLanguage.shared
    var onClose: () -> Void
    /// Asks the window to resize to a target content width so the live-preview
    /// panel can slide in on the right. Provided by SettingsWindowController.
    var onResize: (CGFloat) -> Void = { _ in }

    enum Tab { case general, pet, care, bubble, relay, history, about }
    var initialTab: Tab = .general
    @State private var tab: Tab = .general
    @State private var demoOpen = false

    private let baseWidth: CGFloat = 640
    private let demoWidth: CGFloat = 740

    private var selectedPack: ImagePetPack? {
        pet.selectedPetID.flatMap { imagePets.pack(id: $0) }
    }

    private func setDemo(_ open: Bool) {
        demoOpen = open
        onResize(open ? baseWidth + demoWidth : baseWidth)
    }

    var body: some View {
        HStack(spacing: 0) {
            settingsColumn.frame(width: baseWidth)
            if demoOpen {
                Divider()
                SettingsDemoPanel(onClose: { setDemo(false) }).frame(width: demoWidth)
            }
        }
        .frame(width: demoOpen ? baseWidth + demoWidth : baseWidth, height: 600)
        .preferredColorScheme(.dark)
        .noFocusRing()
        .environment(\.locale, appLang.locale)
        .id(appLang.lang.rawValue)   // recreate the tree so every Text re-resolves on language change
        .onAppear { tab = initialTab; model.refresh() }
    }

    private var settingsColumn: some View {
        VStack(spacing: 0) {
            tabBar
            Divider()
            Group {
                switch tab {
                case .general:
                    GeneralTab(model: model, pet: pet)
                case .pet:
                    PetTab(pet: pet, imagePets: imagePets, model: model, selectedPack: selectedPack)
                case .care:
                    CareTabView()
                case .bubble:
                    BubbleSettingsView()
                case .relay:
                    PetRelaySettingsView()
                case .history:
                    HistoryTabView()
                case .about:
                    AboutTab()
                }
            }
            .frame(maxHeight: .infinity)
            Divider()
            bottomBar
        }
    }

    private var bottomBar: some View {
        HStack(spacing: 10) {
            Button { setDemo(!demoOpen) } label: {
                Label(demoOpen ? "Hide live preview" : "Live preview", systemImage: "sparkles.tv")
            }
            .buttonStyle(.borderedProminent).tint(Color.systemAccent).controlSize(.large)
            Text("Fire webhooks for many agents with your current settings")
                .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            Spacer()
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .background(.bar)
    }

    private var tabBar: some View {
        HStack(spacing: 8) {
            TabButton(icon: "gearshape.fill", label: "General", selected: tab == .general) { tab = .general }
            TabButton(icon: "pawprint.fill", label: "Pet", selected: tab == .pet) { tab = .pet }
            TabButton(icon: "fork.knife", label: "Care", selected: tab == .care) { tab = .care }
            TabButton(icon: "bubble.left.and.bubble.right.fill", label: "Bubble", selected: tab == .bubble) { tab = .bubble }
            TabButton(icon: "envelope.fill", label: "Pet messages", selected: tab == .relay) { tab = .relay }
            TabButton(icon: "clock.arrow.circlepath", label: "History", selected: tab == .history) { tab = .history }
            TabButton(icon: "heart.fill", label: "About", selected: tab == .about) { tab = .about }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
    }
}

private struct TabButton: View {
    let icon: String
    let label: LocalizedStringKey
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon).font(.system(size: 19))
                Text(label).font(.system(size: 11))
            }
            .frame(width: 78, height: 48)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(selected ? Color.systemAccent.opacity(0.22) : .clear))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(selected ? Color.systemAccent.opacity(0.55) : .clear, lineWidth: 1))
            .foregroundStyle(selected ? Color.systemAccent : Color.primary)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - About

private struct AboutTab: View {
    var body: some View {
        Form {
            Section {
                VStack(spacing: 10) {
                    Image(systemName: "pawprint.fill")
                        .font(.system(size: 40)).foregroundStyle(Color.systemAccent)
                    Text(verbatim: LocalConfiguration.displayName).font(.title2.bold())
                    Text("A local companion for your AI coding work.")
                        .font(.callout).foregroundStyle(.secondary)
                    Text("Check and download GitHub releases here. Pet messaging is optional.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity).padding(.vertical, 8)
            }
            AppUpdateView()
            Section("Local data") {
                LabeledContent("Data folder", value: AgentPetPaths.baseDir)
                    .textSelection(.enabled)
                LabeledContent("Preferences", value: LocalConfiguration.preferencesSuite)
                    .textSelection(.enabled)
            }
            Section("Acknowledgements") {
                Link("LuMate · 噜伴 · GitHub", destination: LocalConfiguration.repositoryURL)
                Link("Original AgentPet project (MIT)", destination: URL(string: "https://github.com/ntd4996/agentpet")!)
                Text("Pet artwork keeps its own creator and license information.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

private struct SoundRow: View {
    let title: LocalizedStringKey
    @Binding var enabled: Bool
    let customPath: String
    let onPlay: () -> Void
    let onUpload: () -> Void
    let onReset: () -> Void

    private var sourceLabel: String {
        customPath.isEmpty ? "Default" : (customPath as NSString).lastPathComponent
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                Spacer()
                ColorSwitch(isOn: $enabled)
            }
            HStack(spacing: 8) {
                Text(sourceLabel)
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                Spacer()
                Button { onPlay() } label: { Image(systemName: "play.circle") }.buttonStyle(.plain)
                Button("Upload…") { onUpload() }.controlSize(.small)
                if !customPath.isEmpty {
                    Button("Default") { onReset() }.controlSize(.small)
                }
            }
            .disabled(!enabled)
            .opacity(enabled ? 1 : 0.5)
        }
    }
}

// MARK: - General (merged setup + general)

private struct GeneralTab: View {
    @ObservedObject var model: SettingsModel
    @ObservedObject var pet: PetController
    @ObservedObject private var sound = SoundSettings.shared
    @ObservedObject private var appLang = AppLanguage.shared
    @ObservedObject private var breaks = BreakReminderSettings.shared
    // Local mirror of the system login-item state so the toggle re-renders
    // reliably (the SMAppService status isn't observable on its own).
    @State private var launchAtLogin = LoginItem.isEnabled
    @State private var showCodexHelp = false

    var body: some View {
        Form {
            Section("Language") {
                Picker("Language", selection: $appLang.lang) {
                    ForEach(AppLanguage.Lang.allCases) { l in
                        Text(l.label).tag(l)
                    }
                }
                .pickerStyle(.menu)
            }

            Section("Launch") {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Launch at login")
                        Text("LuMate starts automatically when you sign in.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    ColorSwitch(isOn: Binding(
                        get: { launchAtLogin },
                        set: { newValue in
                            LoginItem.setEnabled(newValue)
                            launchAtLogin = LoginItem.isEnabled
                        }))
}
            }

            Section("Pet display") {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Animate pets")
                        Text("Turn off to freeze pet/bubble animation (lower CPU).")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    ColorSwitch(isOn: $pet.animationsEnabled)
                }
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Animation speed")
                        Text("Quiet animations use 1–2 fps; sleepy uses 1 fps.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    HStack(spacing: 8) {
                        Slider(value: $pet.animationFPS, in: 1...2, step: 1)
                            .frame(width: 120)
                        Text("\(Int(pet.animationFPS)) 帧/秒")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .fixedSize()
                    }
                }
                .disabled(!pet.animationsEnabled)
                .opacity(pet.animationsEnabled ? 1 : 0.5)
            }

            Section("Break reminder") {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Remind me to take breaks")
                        Text("The home pet nudges you to rest after a work stretch.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    ColorSwitch(isOn: $breaks.enabled)
                }
                Stepper(InterfaceText.format("Work for: %d min", breaks.workIntervalMinutes),
                        value: $breaks.workIntervalMinutes, in: 15...240, step: 15)
                    .disabled(!breaks.enabled)
                    .opacity(breaks.enabled ? 1 : 0.5)
                Stepper(InterfaceText.format("Break length: %d min", breaks.breakLengthMinutes),
                        value: $breaks.breakLengthMinutes, in: 1...30, step: 1)
                    .disabled(!breaks.enabled)
                    .opacity(breaks.enabled ? 1 : 0.5)
            }

            Section("Notifications") {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(notificationTitle)
                        Text(notificationDetail).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    notificationButton
                }
            }

            Section("Sounds") {
                SoundRow(title: "When an agent finishes",
                         enabled: $sound.doneEnabled,
                         customPath: sound.doneCustomPath,
                         onPlay: { sound.play(.done) },
                         onUpload: { sound.upload(for: .done) },
                         onReset: { sound.resetToDefault(.done) })
                SoundRow(title: "When an agent needs input",
                         enabled: $sound.waitingEnabled,
                         customPath: sound.waitingCustomPath,
                         onPlay: { sound.play(.waiting) },
                         onUpload: { sound.upload(for: .waiting) },
                         onReset: { sound.resetToDefault(.waiting) })
            }

            Section("Agent integrations") {
                Text("启动时自动检测并配置已安装的受支持客户端。已有设置会先备份；未收到事件前，不会显示已连接。")
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button("重新检测并连接") { model.autoConnectDetectedClients() }
                    Button("Codex 连接说明") { showCodexHelp = true }
                }
                ForEach(model.agents) { agent in
                    AgentConnectionRow(agent: agent)
                }
                if let err = model.installError {
                    Text(err).font(.caption).foregroundStyle(.red).textSelection(.enabled)
                }
            }

            Section("Bash approval gate") {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Approve Bash from the bubble")
                        Text("Claude Code Bash requests show Allow/Deny in the bubble instead of the terminal.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    ColorSwitch(isOn: $model.approvalGateEnabled)
                }
            }

            Section("About") {
                LabeledContent("Version", value: appVersion)
            }

            Section {
                Button("Quit LuMate") { NSApplication.shared.terminate(nil) }
            }
        }
        .formStyle(.grouped)
        .sheet(isPresented: $showCodexHelp) { CodexHelpView() }
    }



    private var appVersion: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(v) (\(b))"
    }

    private var notificationTitle: String {
        switch model.notificationState {
        case .enabled: return model.notificationsEnabled ? NSLocalizedString("Notifications on", comment: "") : NSLocalizedString("Notifications muted", comment: "")
        case .denied: return NSLocalizedString("Notifications denied", comment: "")
        case .unavailable: return NSLocalizedString("Notifications unavailable", comment: "")
        case .notDetermined: return NSLocalizedString("Enable notifications", comment: "")
        }
    }

    private var notificationDetail: String {
        switch model.notificationState {
        case .unavailable: return NSLocalizedString("Available once installed as LuMate.app", comment: "")
        case .denied: return NSLocalizedString("Turn on in System Settings to get alerts", comment: "")
        case .enabled: return model.notificationsEnabled
            ? NSLocalizedString("Alerts when an agent finishes or needs input", comment: "")
            : NSLocalizedString("Muted, the toggle turns alerts back on", comment: "")
        case .notDetermined: return NSLocalizedString("Alerts when an agent finishes or needs input", comment: "")
        }
    }

    @ViewBuilder private var notificationButton: some View {
        switch model.notificationState {
        case .enabled:
            // Permission granted: an in-app toggle lets the user mute without
            // revoking the system permission.
            ColorSwitch(isOn: $model.notificationsEnabled)
        case .denied:
            Button("Open Settings") { model.openSystemNotificationSettings() }
        case .notDetermined:
            Button("Enable") { model.enableNotifications() }
        case .unavailable:
            EmptyView()
        }
    }
}

// MARK: - Pet tab

private struct PetTab: View {
    @ObservedObject var pet: PetController
    @ObservedObject var imagePets: ImagePetStore
    @ObservedObject var model: SettingsModel
    let selectedPack: ImagePetPack?
    @ObservedObject private var projectSettings = ProjectPetSettings.shared
    @ObservedObject private var care = PetCareController.shared
    @State private var showingNewCompanion = false
    @State private var newCompanionName = ""
    @State private var browsing = false
    @State private var creating = false
    @State private var petQuery = ""
    @State private var renameText = ""

    private enum PetSlot: Hashable {
        case defaultPet
        case project(String)
    }
    @State private var selectedSlot: PetSlot = .defaultPet

    private var selectedSlotPetID: String? {
        switch selectedSlot {
        case .defaultPet: return pet.selectedPetID
        case .project(let path): return projectSettings.petID(forProject: path)
        }
    }

    private var selectedSlotPack: ImagePetPack? {
        selectedSlotPetID.flatMap { imagePets.pack(id: $0) }
    }

    private var filteredPacks: [ImagePetPack] {
        guard !petQuery.isEmpty else { return imagePets.packs }
        let q = petQuery.lowercased()
        return imagePets.packs.filter { $0.displayName.lowercased().contains(q) }
    }

    var body: some View {
        Form {
            // Hero card for selected slot
            Section {
                heroCard
            }

            // Split pet toggle
            Section {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Split pet")
                        Text("Spawn one pet per active project instead of one shared pet.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    ColorSwitch(isOn: $pet.splitPet)
                }
                if pet.splitPet {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Hide idle project pets")
                            Text("Show a configured project's pet only while it's working; hide it when idle.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        ColorSwitch(isOn: $pet.hideIdleProjectPets)
                    }
                }
            }

            // Slot selector grid
            Section {
                slotGrid
            }

            // Config panel for selected slot
            configPanel
        }
        .formStyle(.grouped)
        .onChange(of: pet.splitPet) { _ in
            if !pet.splitPet, case .project = selectedSlot {
                selectedSlot = .defaultPet
            }
        }
        .onChange(of: projectSettings.mappings) { _ in
            if case .project(let path) = selectedSlot,
               !projectSettings.mappings.contains(where: { $0.projectPath == path }) {
                selectedSlot = .defaultPet
            }
        }
        .alert("New companion", isPresented: $showingNewCompanion) {
            TextField("Pet name", text: $newCompanionName)
            Button("Cancel", role: .cancel) {}
            Button("Create companion") {
                if let appearance = pet.selectedPetID,
                   care.createCompanion(appearanceID: appearance, name: newCompanionName) != nil {
                    pet.selectedPetID = care.currentAppearanceID
                    renameText = imagePets.displayName(for: pet.selectedPetID)
                }
            }
        } message: {
            Text("Start a separate companion at level 0 using the current appearance. Your existing companions and their progress are kept.")
        }
        .sheet(isPresented: $browsing) { BrowsePetsView(onClose: { browsing = false }) }
        .sheet(isPresented: $creating) {
            CreatePetView(onCreate: { id in creating = false; imagePets.reload(); pet.selectedPetID = id },
                          onCancel: { creating = false })
        }
    }

    // MARK: - Hero card

    @ViewBuilder private var heroCard: some View {
        HStack(spacing: 14) {
            slotPetPreview
                .frame(width: 84, height: 84)
                .background(RoundedRectangle(cornerRadius: 12).fill(.quaternary))
            VStack(alignment: .leading, spacing: 4) {
                switch selectedSlot {
                case .defaultPet:
                    HStack(spacing: 8) {
                        Text(imagePets.displayName(for: pet.selectedPetID))
                            .font(.title3.weight(.semibold))
                        if let pack = selectedPack {
                            levelBadge(for: pack.id)
                        }
                    }
                    if let desc = selectedPack?.description {
                        Text(desc).font(.callout).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                case .project(let path):
                    Text((path as NSString).lastPathComponent)
                        .font(.title3.weight(.semibold))
                    if let pack = selectedSlotPack {
                        HStack(spacing: 8) {
                            Text(pack.displayName).font(.callout).foregroundStyle(.secondary)
                            levelBadge(for: pack.id)
                        }
                    }
                    Text(path).font(.caption).foregroundStyle(.secondary)
                        .lineLimit(1).truncationMode(.middle)
                }
            }
            Spacer()
        }
    }

    // MARK: - Slot grid

    private var slotGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 4),
                  alignment: .leading, spacing: 12) {
            slotButton(for: .defaultPet, petID: pet.selectedPetID,
                       label: NSLocalizedString("Default", comment: "default pet slot"))
            if pet.splitPet {
                ForEach(projectSettings.mappings, id: \.projectPath) { mapping in
                    slotButton(for: .project(mapping.projectPath), petID: mapping.petID,
                               label: (mapping.projectPath as NSString).lastPathComponent)
                }
                addProjectSlot
            }
        }
        .padding(.vertical, 4)
    }

    private func slotButton(for slot: PetSlot, petID: String?, label: String) -> some View {
        let isSelected = selectedSlot == slot
        return Button { selectedSlot = slot } label: {
            VStack(spacing: 4) {
                Group {
                    if let petID, let pack = imagePets.pack(id: petID), let frame = pack.clip(0).first {
                        Image(nsImage: frame).resizable().interpolation(.high).scaledToFit()
                    } else {
                        Image(systemName: "pawprint.fill").font(.system(size: 20)).foregroundStyle(.secondary)
                    }
                }
                .frame(width: 48, height: 48)
                Text(label).font(.caption).lineLimit(1).frame(width: 64)
            }
            .padding(6)
            .background(RoundedRectangle(cornerRadius: 10)
                .fill(isSelected ? Color.systemAccent.opacity(0.2) : .clear))
            .overlay(RoundedRectangle(cornerRadius: 10)
                .strokeBorder(isSelected ? Color.systemAccent : .secondary.opacity(0.3),
                              lineWidth: isSelected ? 2 : 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .topLeading) {
            if let petID {
                let level = PetCare.displayLevel(forXP: care.state(for: petID).xp)
                Text(verbatim: "等级 \(level)")
                    .font(.system(size: 9, weight: .bold))
                    .padding(.horizontal, 5).padding(.vertical, 1.5)
                    .background(Capsule().fill(level > 0 ? Color.systemAccent.opacity(0.85) : Color.secondary.opacity(0.45)))
                    .foregroundStyle(.white)
                    .offset(x: -3, y: -3)
            }
        }
        // Project slots get a direct remove button so deleting a project is one
        // click (the "Remove project" button at the bottom of its config panel
        // was easy to miss).
        .overlay(alignment: .topTrailing) {
            if case .project(let path) = slot {
                Button {
                    if selectedSlot == slot { selectedSlot = .defaultPet }
                    projectSettings.remove(projectPath: path)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 15))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, .black.opacity(0.45))
                }
                .buttonStyle(.plain)
                .offset(x: 5, y: -5)
                .help("Remove project")
            }
        }
    }

    private var addProjectSlot: some View {
        Button { addProject() } label: {
            VStack(spacing: 4) {
                Image(systemName: "plus")
                    .font(.system(size: 20)).foregroundStyle(.secondary)
                    .frame(width: 48, height: 48)
                Text("Add…").font(.caption).lineLimit(1).frame(width: 64)
            }
            .padding(6)
            .overlay(RoundedRectangle(cornerRadius: 10)
                .strokeBorder(.secondary.opacity(0.3), style: StrokeStyle(lineWidth: 1, dash: [5, 3])))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Config panel (switches on selected slot)

    @ViewBuilder private var configPanel: some View {
        switch selectedSlot {
        case .defaultPet:
            defaultPetConfig
        case .project(let path):
            projectPetConfig(path: path)
        }
    }

    @ViewBuilder private var defaultPetConfig: some View {
        Section("Companion") {
            if let error = care.persistenceError {
                Text(verbatim: error).foregroundStyle(.red)
            } else {
                Picker("Current companion", selection: Binding(
                    get: { care.currentPetID ?? "" },
                    set: { id in
                        care.selectCompanion(id)
                        pet.selectedPetID = care.currentAppearanceID
                        renameText = imagePets.displayName(for: pet.selectedPetID)
                    }
                )) {
                    ForEach(care.companions) { companion in
                        Text(verbatim: care.name(forCompanionID: companion.id) + " · " +
                             InterfaceText.format("Lv %d", PetCare.displayLevel(forXP: care.state(forCompanionID: companion.id).xp)))
                            .tag(companion.id)
                    }
                }
                Button {
                    newCompanionName = ""
                    showingNewCompanion = true
                } label: {
                    Label("New companion…", systemImage: "plus.circle")
                }
                .disabled(pet.selectedPetID == nil)
                Text("Changing appearance keeps this companion's level, name and care history. Only a new companion starts from zero.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        if let id = pet.selectedPetID {
            Section {
                HStack {
                    TextField("Pet name", text: $renameText)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { imagePets.rename(id, to: renameText) }
                    Button("Save") { imagePets.rename(id, to: renameText) }
                }
            } header: {
                Text("Name")
            } footer: {
                Text("Give your companion a custom name. Clear it to use the original.")
            }
            .onAppear { renameText = imagePets.displayName(for: id) }
            .onChange(of: pet.selectedPetID) { _ in
                renameText = imagePets.displayName(for: pet.selectedPetID)
            }
            .onChange(of: care.currentPetID) { _ in
                renameText = imagePets.displayName(for: pet.selectedPetID)
            }
            .disabled(care.persistenceError != nil)
        }

        Section("Change appearance") {
            if imagePets.packs.isEmpty {
                Text("No pets yet. Tap Browse to add one.").foregroundStyle(.secondary)
            } else {
                if imagePets.packs.count > 4 {
                    NativeSearchField(text: $petQuery, placeholder: "Search your pets")
                }
                PetPager(packs: filteredPacks, selectedID: pet.selectedPetID,
                         onSelect: { if care.persistenceError == nil { pet.selectedPetID = $0 } },
                         onDelete: { pack in
                             let wasSelected = pet.selectedPetID == pack.id
                             imagePets.delete(pack)
                             if wasSelected, imagePets.pack(id: pack.id) == nil { pet.selectedPetID = imagePets.packs.first?.id }
                         })
            }
            HStack {
                Button { browsing = true } label: {
                    Label("Browse appearances…", systemImage: "square.grid.2x2")
                }
                Button { creating = true } label: {
                    Label("Create appearance…", systemImage: "square.and.pencil")
                }
            }
        }

        if let pack = selectedPack {
            Section("Animations") {
                QuietAnimationPreview(pack: pack)
            }
        }

        Section("Size on screen") {
            HStack(spacing: 8) {
                Slider(value: $pet.petPoint, in: PetController.minPoint...PetController.maxPoint)
                Text("\(Int(pet.petPoint))")
                    .monospacedDigit().foregroundStyle(.secondary).fixedSize()
                ForEach(PetController.presets, id: \.0) { preset in
                    Button(NSLocalizedString(preset.0, comment: "pet size")) { pet.animateSize(to: preset.1) }
                        .buttonStyle(.bordered)
                }
            }
        }
    }

    @ViewBuilder private func projectPetConfig(path: String) -> some View {
        Section("Change appearance") {
            if imagePets.packs.isEmpty {
                Text("No pets installed.").foregroundStyle(.secondary)
            } else {
                PetPager(packs: imagePets.packs,
                         selectedID: projectSettings.petID(forProject: path),
                         onSelect: { projectSettings.setPet(projectPath: path, petID: $0) })
            }
        }

        if let pack = selectedSlotPack {
            Section("Animations") {
                QuietAnimationPreview(pack: pack)
            }
        }

        Section {
            Button(role: .destructive) {
                projectSettings.remove(projectPath: path)
            } label: {
                Label("Remove project", systemImage: "trash")
                    .foregroundStyle(.red)
            }
        }
    }

    // MARK: - Helpers

    @ViewBuilder private var slotPetPreview: some View {
        if let pack = selectedSlotPack {
            ImageSpriteView(frames: pack.restingFrames,
                            fps: pet.spriteFPS(forMood: .idle), size: 78, frameDurations: pack.restingFrameDurations)
        } else {
            Image(systemName: "pawprint.fill").font(.system(size: 40)).foregroundStyle(.secondary)
        }
    }

    private func levelBadge(for packID: String) -> some View {
        Text(verbatim: "等级 \(PetCare.displayLevel(forXP: care.state(for: packID).xp))")
            .font(.caption.weight(.bold))
            .padding(.horizontal, 7).padding(.vertical, 2)
            .background(Capsule().fill(Color.systemAccent.opacity(0.2)))
            .foregroundStyle(Color.systemAccent)
    }

    private func addProject() {
        let panel = NSOpenPanel()
        panel.title = NSLocalizedString("Choose Project Folder", comment: "")
        panel.prompt = NSLocalizedString("Add", comment: "")
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let petID = pet.selectedPetID ?? imagePets.packs.first?.id ?? ""
        guard !petID.isEmpty else { return }
        projectSettings.setPet(projectPath: url.path, petID: petID)
    }
}

// MARK: - Components

/// A single static sprite frame (no TimelineView), for grids where animating
/// every cell would be janky. Only the hero preview animates.
private struct StaticFrame: View {
    let image: NSImage?
    var size: CGFloat

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image).resizable().interpolation(.high).scaledToFit()
            } else {
                Image(systemName: "pawprint.fill").foregroundStyle(.secondary)
            }
        }
        .frame(width: size, height: size)
    }
}

private struct PetPager: View {
    let packs: [ImagePetPack]
    let selectedID: String?
    let onSelect: (String) -> Void
    var onDelete: ((ImagePetPack) -> Void)? = nil
    @State private var page = 0

    private let perPage = 8

    var body: some View {
        let pageCount = max(1, Int(ceil(Double(packs.count) / Double(perPage))))
        let current = min(page, pageCount - 1)

        VStack(spacing: 10) {
            GeometryReader { geo in
                HStack(alignment: .top, spacing: 0) {
                    ForEach(0..<pageCount, id: \.self) { p in
                        grid(for: p).frame(width: geo.size.width, alignment: .top)
                    }
                }
                .offset(x: -CGFloat(current) * geo.size.width)
                .animation(.easeInOut(duration: 0.28), value: current)
            }
            .frame(height: 188)
            .clipped()

            if pageCount > 1 {
                HStack(spacing: 14) {
                    arrow("chevron.left", enabled: current > 0) { page = max(0, current - 1) }
                    HStack(spacing: 5) {
                        ForEach(0..<pageCount, id: \.self) { i in
                            Circle()
                                .fill(i == current ? Color.systemAccent : .secondary.opacity(0.4))
                                .frame(width: 6, height: 6)
                        }
                    }
                    arrow("chevron.right", enabled: current < pageCount - 1) { page = min(pageCount - 1, current + 1) }
                }
            }
        }
        .padding(.vertical, 4)
        .onChange(of: packs.count) { _ in page = 0 }
    }

    private func grid(for pageIndex: Int) -> some View {
        let slice = Array(packs.dropFirst(pageIndex * perPage).prefix(perPage))
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 4),
                         alignment: .leading, spacing: 12) {
            ForEach(slice) { pack in
                PetThumb(pack: pack, selected: selectedID == pack.id,
                         select: { onSelect(pack.id) },
                         onDelete: pack.isBuiltin ? nil : onDelete.map { d in { d(pack) } })
            }
        }
    }

    private func arrow(_ icon: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .frame(width: 30, height: 30)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(enabled ? Color.secondary : Color.secondary.opacity(0.3))
        .disabled(!enabled)
    }
}

private struct PetThumb: View {
    let pack: ImagePetPack
    let selected: Bool
    let select: () -> Void
    var onDelete: (() -> Void)? = nil
    @State private var hovering = false

    var body: some View {
        Button(action: select) {
            VStack(spacing: 4) {
                StaticFrame(image: pack.clip(0).first, size: 48)
                    .frame(width: 56, height: 48)
                Text(pack.displayName).font(.caption).lineLimit(1).frame(width: 64)
            }
            .padding(6)
            .background(RoundedRectangle(cornerRadius: 10).fill(selected ? Color.systemAccent.opacity(0.2) : .clear))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(selected ? Color.systemAccent : .secondary.opacity(0.3), lineWidth: selected ? 2 : 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .topLeading) {
            if pack.isBuiltin {
                Text("Built-in")
                    .font(.system(size: 9, weight: .bold))
                    .padding(.horizontal, 5).padding(.vertical, 1.5)
                    .background(Capsule().fill(Color.systemAccent.opacity(0.85)))
                    .foregroundStyle(.white)
                    .offset(x: -3, y: -3)
            }
        }
        .overlay(alignment: .topTrailing) {
            if hovering, let onDelete {
                Button(action: onDelete) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(.white, .black.opacity(0.55))
                }
                .buttonStyle(.plain)
                .offset(x: 4, y: -4)
            }
        }
        .onHover { hovering = $0 }
    }
}

/// One consistent preview, with no controls that can silently re-enable running.
private struct QuietAnimationPreview: View {
    let pack: ImagePetPack
    @ObservedObject private var pet = PetController.shared

    var body: some View {
        HStack(spacing: 12) {
            ImageSpriteView(frames: pack.restingFrames,
                            fps: pet.spriteFPS(forMood: .idle), size: 64, frameDurations: pack.restingFrameDurations)
                .environment(\.animationsEnabled, pet.animationsEnabled)
            VStack(alignment: .leading, spacing: 4) {
                Text("Quiet companion").font(.headline)
                Text("Only in-place idle and blinking, even when tasks finish. No running, jumping, or tap bouncing.")
                    .font(.caption).foregroundStyle(.secondary)
                Text("Task tracking and status messages stay active. Sleepy playback is slower.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Codex connection help

/// Explains the one-time `/hooks` trust step Codex requires before AgentPet's
/// hook runs (Codex blocks unknown command hooks for security). Other agents
/// need no such step.
private struct CodexHelpView: View {
    @Environment(\.dismiss) private var dismiss

    private struct Step: Identifiable { let n: Int; let text: String; var id: Int { n } }
    private let steps: [Step] = [
        .init(n: 1, text: "确认 Codex 一栏显示“已配置，等待客户端事件”。如有错误，先按提示处理，不要覆盖已有配置。"),
        .init(n: 2, text: "在 Codex 中新建会话。如果未加载新的连接配置，保存当前工作后重新打开客户端。"),
        .init(n: 3, text: "如果客户端要求确认外部命令，请核对路径确实指向本机的 LuMate · 噜伴，再按客户端提示确认这一项。"),
        .init(n: 4, text: "在 Codex 中执行一个正常任务。桌宠收到事件后，这里会显示事件时间，并展示对应会话状态。"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: "checkmark.shield")
                    .font(.title2).foregroundStyle(.blue)
                Text("Connect Codex").font(.title3.bold())
                Spacer()
            }

            Text("桌宠通过本地事件回调接收 Codex 的工作状态，不会读取登录凭证，也不会替你确认客户端的信任提示。")
                .font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 10) {
                ForEach(steps) { s in
                    HStack(alignment: .top, spacing: 10) {
                        Text("\(s.n)")
                            .font(.caption.bold()).foregroundStyle(.white)
                            .frame(width: 20, height: 20)
                            .background(Circle().fill(.blue))
                        Text(s.text)
                            .font(.callout)
                            .fixedSize(horizontal: false, vertical: true)
                            .textSelection(.enabled)
                    }
                }
            }

            Text("不同版本的 Codex 对事件回调的支持可能不同。若一直没有事件，请检查客户端的连接提示和回调支持；仅写入配置不代表已建立实时连接。")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Link("Codex hooks docs", destination: URL(string: "https://learn.chatgpt.com/docs/hooks")!)
                    .font(.caption)
                Spacer()
                Button("Got it") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 460)
    }
}
