import SwiftUI
import AgentPetCore

/// The tamagotchi panel: level + evolution stage, hunger, today's feeding,
/// lifetime totals, and where the food data comes from.
struct CareTabView: View {
    @ObservedObject private var care = PetCareController.shared
    @ObservedObject private var pet = PetController.shared
    @ObservedObject private var imagePets = ImagePetStore.shared

    /// Ticks so hunger and "today" counters stay fresh while the panel is open.
    @State private var now = Date()
    private let tick = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    private static let stageIcons = ["leaf.fill", "pawprint.fill", "binoculars.fill", "shield.fill", "crown.fill"]
    private static let stageColors: [Color] = [.green, .teal, .blue, .purple, .orange]

    private var currentPack: ImagePetPack? {
        pet.selectedPetID.flatMap { imagePets.pack(id: $0) }
    }

    private var currentName: String {
        imagePets.displayName(for: pet.selectedPetID)
    }

    var body: some View {
        Form {
            Section("Companion") {
                HStack(spacing: 14) {
                    Group {
                        if let frame = currentPack?.clip(0).first {
                            Image(nsImage: frame).resizable().interpolation(.none).scaledToFit()
                                .padding(5)
                        } else {
                            Image(systemName: stageIcon)
                                .font(.system(size: 22))
                                .foregroundStyle(stageColor)
                        }
                    }
                    .frame(width: 52, height: 52)
                    .background(RoundedRectangle(cornerRadius: 12).fill(stageColor.opacity(0.16)))
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            Text(verbatim: currentName)
                                .font(.title3).bold()
                            Text(verbatim: "Lv \(care.level)")
                                .font(.title3).foregroundStyle(.secondary)
                            StageBadge(stageIndex: care.stageIndex, size: 22)
                            Text(NSLocalizedString(care.stageKey, comment: "evolution stage"))
                                .font(.caption).bold()
                                .padding(.horizontal, 8).padding(.vertical, 3)
                                .background(Capsule().fill(stageColor.opacity(0.2)))
                                .foregroundStyle(stageColor)
                        }
                        ProgressView(value: care.levelProgress)
                            .tint(stageColor)
                        Text(xpCaption)
                            .font(.caption).foregroundStyle(.secondary)
                        Text(String(format: NSLocalizedString("≈ %@ tokens to Lv %d", comment: ""),
                                    CareFormat.tokens(PetCare.tokensToNextLevel(state: care.current)),
                                    care.level + 1))
                            .font(.caption).foregroundStyle(stageColor)
                    }
                }
                .padding(.vertical, 4)
                Text("Every pet levels up on its own: experience belongs to the companion you raise it with.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Hunger") {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(CareFormat.hunger(care.hunger))
                        Spacer()
                        if let last = care.current.lastFedAt {
                            Text(String(format: NSLocalizedString("Last fed %@", comment: ""),
                                        last.formatted(.relative(presentation: .named))))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    ProgressView(value: fullness)
                        .tint(fullness > 0.5 ? .green : (fullness > 0.25 ? .orange : .red))
                    Text("The pet eats real work: tokens burnt by your agents and finished sessions.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .padding(.vertical, 2)
            }

            Section("Today") {
                LabeledContent("Tokens eaten") {
                    Text(verbatim: CareFormat.plain(care.current.tokensToday))
                }
                LabeledContent("Sessions finished", value: "\(care.current.mealsToday)")
                LabeledContent("Streak") {
                    Text(care.current.streakDays == 1
                         ? NSLocalizedString("1 day", comment: "streak singular")
                         : String(format: NSLocalizedString("%d days", comment: "streak"), care.current.streakDays))
                }
            }

            Section("Lifetime") {
                LabeledContent("Total tokens eaten", value: CareFormat.plain(care.current.totalTokens))
                LabeledContent("Total sessions", value: "\(care.current.totalMeals)")
            }

            AgentUsageSection()

            Section {
                let unlocked = care.achievements
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 5), spacing: 14) {
                    ForEach(Achievement.allCases, id: \.self) { a in
                        let on = unlocked.contains(a)
                        VStack(spacing: 4) {
                            Image(systemName: PetCare.achievementSymbol(a))
                                .font(.system(size: 18))
                                .foregroundStyle(on ? stageColor : Color.secondary.opacity(0.4))
                                .frame(height: 22)
                            Text(PetCare.achievementDisplayName(a))
                                .font(.system(size: 9))
                                .multilineTextAlignment(.center)
                                .foregroundStyle(on ? .primary : .secondary)
                                .lineLimit(2)
                        }
                        .frame(maxWidth: .infinity)
                        .opacity(on ? 1 : 0.5)
                        .help("\(PetCare.achievementDisplayName(a)) — \(PetCare.achievementDescription(a))")
                    }
                }
                .padding(.vertical, 4)
            } header: {
                Text("Achievements")
            } footer: {
                Text(verbatim: "\(care.achievements.count) of \(Achievement.allCases.count) unlocked")
            }

            if care.raisedPetIDs.count > 1 {
                Section("All companions") {
                    ForEach(care.raisedPetIDs, id: \.self) { id in
                        companionRow(id: id)
                    }
                    Text("Each companion keeps its own experience. Switch pets in the Pet tab to raise another one.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            Section("Local data") {
                Text("Pets, settings and growth stay on this Mac. No account or cloud sync is required.")
                LabeledContent("Data folder", value: AgentPetPaths.baseDir)
                    .textSelection(.enabled)
            }

            Section("Food sources") {
                Text("Usage comes from supported local agent logs and session events, not subscription balances.")
                Text("Third-party usage depends on what the client records. Additional client adapters are planned.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear {
            care.refreshDay()
        }
        .onReceive(tick) { date in
            now = date
            care.refreshDay()
        }
    }

    // MARK: - Companions

    @ViewBuilder
    private func companionRow(id: String) -> some View {
        let s = care.state(for: id)
        let lv = PetCare.displayLevel(forXP: s.xp)
        let idx = PetCare.stageIndex(forLevel: PetCare.level(forXP: s.xp))
        let color = Self.stageColors[min(idx, Self.stageColors.count - 1)]
        HStack(spacing: 10) {
            Group {
                if let frame = imagePets.pack(id: id)?.clip(0).first {
                    Image(nsImage: frame).resizable().interpolation(.none).scaledToFit()
                } else {
                    Image(systemName: Self.stageIcons[min(idx, Self.stageIcons.count - 1)])
                        .font(.system(size: 13))
                        .foregroundStyle(color)
                }
            }
            .frame(width: 24, height: 24)
            .overlay(alignment: .bottomTrailing) {
                StageBadge(stageIndex: idx, size: 13).offset(x: 3, y: 3)
            }
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(verbatim: imagePets.displayName(for: id))
                        .font(.system(size: 13, weight: .semibold))
                    if id == care.currentPetID {
                        Text("Raising").font(.caption2).bold()
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Capsule().fill(Color.systemAccent.opacity(0.2)))
                            .foregroundStyle(Color.systemAccent)
                    }
                }
                ProgressView(value: PetCare.progress(forXP: s.xp))
                    .tint(color)
                    .controlSize(.small)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(verbatim: "Lv \(lv)").font(.system(size: 12, weight: .bold))
                Text(verbatim: "\(CareFormat.plain(s.xp)) XP")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    // MARK: - Derived display

    private var stageIcon: String { Self.stageIcons[min(care.stageIndex, Self.stageIcons.count - 1)] }
    private var stageColor: Color { Self.stageColors[min(care.stageIndex, Self.stageColors.count - 1)] }

    private var xpCaption: String {
        let (inLevel, span) = PetCare.xpWithinLevel(forXP: care.current.xp)
        return String(format: NSLocalizedString("%@ / %@ XP to next level", comment: ""),
                      CareFormat.plain(inLevel), CareFormat.plain(span))
    }

    /// Continuous fullness 0…1 from the time since the last feeding (48h → empty).
    private var fullness: Double {
        guard let last = care.current.lastFedAt else { return 0.5 }
        let hours = now.timeIntervalSince(last) / 3600
        return max(0, min(1, 1 - hours / 48))
    }
}
