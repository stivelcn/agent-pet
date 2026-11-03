import SwiftUI
import AgentPetCore

/// A quiet, persistent, single-click completion reminder. Multiple completions open a picker.
struct CompletionBubble: View {
    let notices: [CompletionNotice]
    @ObservedObject var store: CompletionNoticeStore
    @ObservedObject private var settings = BubbleSettings.shared
    @ObservedObject private var names = ProjectNameStore.shared
    @State private var showingList = false

    private var heading: String {
        if notices.count == 1 { return NSLocalizedString("Done ✅", comment: "persistent completion") }
        return String(format: NSLocalizedString("%d tasks are done", comment: "completion count"), notices.count)
    }

    private func subtitle(_ notice: CompletionNotice) -> String {
        let target = notice.target
        let client = AgentCatalog.all.first { $0.kind == target.agentKind }?.displayName
            ?? target.agentName ?? target.agentKind.rawValue
        let label = target.title.flatMap { $0.isEmpty ? nil : $0 }
            ?? target.project.map { names.label(for: $0) }
            ?? NSLocalizedString("Conversation", comment: "completion session")
        return "\(client) · \(label) · \(target.sessionID.suffix(8))"
    }

    private var background: Color {
        switch settings.theme {
        case .light: return Color.white.opacity(settings.opacity)
        case .dark: return Color(red: 0.11, green: 0.12, blue: 0.15).opacity(settings.opacity)
        case .system: return Color(nsColor: .textBackgroundColor).opacity(settings.opacity)
        }
    }

    private var foreground: Color {
        switch settings.theme {
        case .light: return .black
        case .dark: return .white
        case .system: return .primary
        }
    }

    var body: some View {
        VStack(spacing: 5) {
            HStack(spacing: 8) {
                Button {
                    if notices.count == 1, let notice = notices.first { open(notice) }
                    else { showingList.toggle() }
                } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(heading).font(.system(size: settings.fontSize.primaryPt, weight: .semibold))
                        Text(notices.count == 1 ? subtitle(notices[0]) : NSLocalizedString("Click to choose a conversation", comment: "completion picker"))
                            .font(.system(size: settings.fontSize.secondaryPt))
                            .foregroundStyle(foreground.opacity(0.65))
                            .lineLimit(1).truncationMode(.middle)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(notices.count == 1 && store.openingIDs.contains(notices[0].id))
                .help(NSLocalizedString("Open the completed conversation", comment: "completion action"))
                .accessibilityIdentifier("completion-open")
                if notices.count == 1, let notice = notices.first {
                    dismissButton(notice)
                } else {
                    Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold))
                        .allowsHitTesting(false)
                }
            }
            if let first = notices.first, notices.count == 1, let message = store.messages[first.id] {
                Text(message).font(.system(size: 11)).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
            }
            if let message = store.persistenceError {
                Text(message).font(.system(size: 11)).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
            }
        }
        .foregroundStyle(foreground)
        .padding(.horizontal, 12).padding(.vertical, 9)
        .frame(width: 270)
        .background(RoundedRectangle(cornerRadius: 15).fill(background))
        .overlay(RoundedRectangle(cornerRadius: 15).strokeBorder(Color.green.opacity(0.32), lineWidth: 1))
        .shadow(color: .black.opacity(0.14), radius: 4, y: 2)
        .popover(isPresented: $showingList, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 10) {
                Text(NSLocalizedString("Completed conversations", comment: "completion picker title")).font(.headline)
                ScrollView {
                    VStack(spacing: 10) {
                        ForEach(notices) { notice in
                            VStack(alignment: .leading, spacing: 5) {
                                HStack {
                                    Button { open(notice) } label: {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(NSLocalizedString("Done ✅", comment: "completion"))
                                            Text(subtitle(notice)).font(.caption).foregroundStyle(.secondary)
                                                .lineLimit(2).truncationMode(.middle)
                                        }
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                    .disabled(store.openingIDs.contains(notice.id))
                                    dismissButton(notice)
                                }
                                if let message = store.messages[notice.id] {
                                    Text(message).font(.caption).foregroundStyle(.orange)
                                }
                            }
                            .padding(8)
                            .background(RoundedRectangle(cornerRadius: 9).fill(Color.primary.opacity(0.04)))
                        }
                    }
                }.frame(maxHeight: 300)
            }.padding(14).frame(width: 340)
        }
    }

    private func open(_ notice: CompletionNotice) {
        Task { @MainActor in await store.open(notice.id) }
    }

    private func dismissButton(_ notice: CompletionNotice) -> some View {
        Button { store.dismiss(notice.id) } label: {
            Image(systemName: "xmark").font(.system(size: 10, weight: .semibold))
                .padding(5).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(NSLocalizedString("Dismiss this completion reminder", comment: "completion action"))
        .accessibilityLabel(NSLocalizedString("Dismiss this completion reminder", comment: "completion action"))
        .accessibilityIdentifier("completion-dismiss")
    }
}
