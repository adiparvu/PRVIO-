import SwiftUI

// MARK: - Messages: the wrist inbox
//
// One row per direct thread (the first eight — the full inbox is a phone
// job): an initials avatar in a calm tint, the peer, the last exchange and
// its unread count. A thread opens to its last message, three quick replies
// and a dictated reply; every reply rides the queue with the thread's
// identity, so it lands in THAT conversation on the phone, never in the
// family chat. The family chat itself is one dictation away in the bottom
// toolbar.
//
// Privacy: previews and message bodies are personal mail — `.watchPrivate()`
// keeps them off a resting wrist (redacted in Always On). Names and counts
// stay readable so a glance still says who wrote.

struct MessagesView: View {
    @Environment(WatchStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// When the last family message was handed to the store; drives the
    /// toolbar's brief "sent" glyph.
    @State private var chatSentAt: Date? = nil

    /// Wrist reading stops here; the phone holds the full inbox.
    private static let maxThreads = 8

    init() {}

    private var allThreads: [DMConversationEntry] { store.payload?.dmConversations ?? [] }

    private var threads: [DMConversationEntry] { Array(allThreads.prefix(Self.maxThreads)) }

    var body: some View {
        let shown = threads
        let hidden = allThreads.count - shown.count
        Group {
            if shown.isEmpty {
                AllClearView(systemImage: WatchModule.messages.systemImage)
            } else {
                List {
                    ForEach(shown, id: \.id) { thread in
                        NavigationLink(value: DMThreadRoute(peerId: thread.id)) {
                            DMThreadRow(thread: thread)
                        }
                        .watchRowBackground(thread.unread > 0 ? WatchTheme.Tint.messages : WatchTheme.Tint.neutral)
                    }
                    if hidden > 0 {
                        Text("watch_more_on_iphone \(hidden)")
                            .font(WatchTheme.Typography.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .listRowBackground(Color.clear)
                    }
                }
            }
        }
        .navigationTitle(Text(WatchModule.messages.titleKey))
        // Feature-specific route: the Home stack is shared by every module,
        // and a bare UUID destination would collide with another feature's.
        .navigationDestination(for: DMThreadRoute.self) { route in
            DMThreadDetail(peerId: route.peerId)
        }
        .skyGround()
        .toolbar {
            ToolbarItem(placement: .bottomBar) {
                // Dictation / Scribble / keyboard for the household chat; the
                // phone sends the real message through the same queue
                // notification replies use.
                TextFieldLink(prompt: Text("watch_chat_prompt")) {
                    SentAwareGlyph(idleSystemImage: "person.3.fill",
                                   idleLabelKey: "watch_chat_send",
                                   isSent: chatSentAt != nil)
                } onSubmit: { text in
                    guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                    store.sendChatMessage(text)   // plays .done
                    withAnimation(animation) { chatSentAt = Date() }
                }
            }
        }
        .task(id: chatSentAt) {
            guard chatSentAt != nil else { return }
            // Cancelled (a newer send restarted the clock, or the screen
            // left) → leave the newer state untouched.
            do { try await Task.sleep(for: DMTiming.sentConfirmation) } catch { return }
            withAnimation(animation) { chatSentAt = nil }
        }
    }

    private var animation: Animation {
        WatchTheme.Motion.resolved(WatchTheme.Motion.snappy, reduceMotion: reduceMotion)
    }
}

// MARK: - Route

/// Pushes one thread's detail. Feature-specific so it never collides with
/// another module's destination on the shared Home stack.
struct DMThreadRoute: Hashable {
    let peerId: UUID
}

private enum DMTiming {
    /// How long a reply's "sent" confirmation stays before the control
    /// returns to its idle state.
    static let sentConfirmation: Duration = .seconds(3)
}

// MARK: - Quick replies

/// Three short, context-free answers composed on the wrist. Deliberately
/// static and localized: they must read naturally whatever the last message
/// said, and must work with the phone out of reach. The text sent is the
/// SENDER's localization — the person is speaking in their own language.
private enum QuickReply: CaseIterable, Identifiable {
    case onMyWay, done, later

    var id: Self { self }

    var titleKey: LocalizedStringKey {
        switch self {
        case .onMyWay: return "watch_quick_on_my_way"
        case .done:    return "watch_quick_done"
        case .later:   return "watch_quick_later"
        }
    }

    /// The message body, resolved from the same keys as the chip's title.
    var text: String {
        switch self {
        case .onMyWay: return String(localized: "watch_quick_on_my_way")
        case .done:    return String(localized: "watch_quick_done")
        case .later:   return String(localized: "watch_quick_later")
        }
    }

    var systemImage: String {
        switch self {
        case .onMyWay: return "figure.walk"
        case .done:    return "hand.thumbsup"
        case .later:   return "clock"
        }
    }
}

// MARK: - Avatar

/// The peer's initials on a soft disc. The tint is picked from a calm set by
/// a stable hash of the thread id, so a person keeps their colour across
/// launches (Swift's `Hasher` is seeded per process and cannot be used).
/// A name without letters (emoji, digits) falls back to a person glyph.
private struct InitialsAvatar: View {
    let name: String
    let seed: UUID
    var size: CGFloat = WatchTheme.Size.prominentGlyph

    @Environment(\.isLuminanceReduced) private var isLuminanceReduced
    @Environment(\.colorSchemeContrast) private var contrast

    /// Calm tints only — none of them reads as a warning.
    private static let palette: [Color] = [
        WatchTheme.Tint.calm, WatchTheme.Tint.water, WatchTheme.Tint.messages,
        WatchTheme.Tint.home, WatchTheme.Tint.session, WatchTheme.Tint.plants,
    ]

    private var tint: Color {
        let sum = seed.uuidString.unicodeScalars.reduce(0) { $0 &+ Int($1.value) }
        return Self.palette[sum % Self.palette.count]
    }

    /// First letter of the first and last word ("Ana Maria Pop" → "AP").
    static func initials(for name: String) -> String? {
        let letters = name
            .split(whereSeparator: { $0.isWhitespace || $0 == "-" })
            .compactMap { word in word.first(where: { $0.isLetter }) }
        guard let first = letters.first else { return nil }
        let pair = letters.count > 1 ? [first, letters[letters.count - 1]] : [first]
        return String(pair).localizedUppercase
    }

    var body: some View {
        ZStack {
            if isLuminanceReduced {
                Circle().strokeBorder(tint.opacity(WatchTheme.AlwaysOn.strokeOpacity),
                                      lineWidth: WatchTheme.Stroke.outline(contrast))
            } else {
                Circle().fill(WatchTheme.cardFill(tint, increasedContrast: contrast == .increased))
            }
            if let initials = Self.initials(for: name) {
                Text(verbatim: initials)
                    .font(WatchTheme.Typography.cardTitle)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .padding(WatchTheme.Spacing.xxs)
            } else {
                Image(systemName: "person.fill")
                    .font(WatchTheme.Typography.glyph)
            }
        }
        .foregroundStyle(tint)
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

// MARK: - Row

private struct DMThreadRow: View {
    let thread: DMConversationEntry

    private var unread: Int { max(0, thread.unread) }

    var body: some View {
        HStack(spacing: WatchTheme.Spacing.m) {
            InitialsAvatar(name: thread.peerName, seed: thread.id)
            VStack(alignment: .leading, spacing: WatchTheme.Spacing.xxs) {
                HStack(alignment: .firstTextBaseline, spacing: WatchTheme.Spacing.xs) {
                    Text(verbatim: thread.peerName)
                        .font(unread > 0 ? WatchTheme.Typography.cardTitle : WatchTheme.Typography.rowTitle)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    if let at = thread.lastAt {
                        Text(at, format: .relative(presentation: .named, unitsStyle: .narrow))
                            .font(WatchTheme.Typography.caption)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                            .watchAlwaysOnDimmed()
                    }
                }
                HStack(alignment: .top, spacing: WatchTheme.Spacing.xs) {
                    DMPreviewText(thread: thread)
                        .font(WatchTheme.Typography.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .watchPrivate()
                    if unread > 0 {
                        CountBadge(count: unread, tint: WatchTheme.Tint.messages)
                            .accessibilityLabel(Text("watch_unread_count \(min(unread, 99))"))
                    }
                }
            }
        }
        .padding(.vertical, WatchTheme.Spacing.xxs)
        .accessibilityElement(children: .combine)
    }
}

/// The last message, safely: media becomes a label (never a raw storage
/// path), and the person's own message is prefixed so a glance tells who
/// spoke.
private struct DMPreviewText: View {
    let thread: DMConversationEntry

    var body: some View {
        if thread.isMedia {
            Label("watch_dm_media", systemImage: "paperclip")
        } else if let body = thread.lastBody, !body.isEmpty {
            if thread.lastIsMine {
                // Verbatim, not Text concatenation (deprecated since watchOS 26)
                // nor a "%@: %@" key the catalog would have to carry.
                Text(verbatim: "\(String(localized: "watch_dm_you")): \(body)")
            } else {
                Text(verbatim: body)
            }
        } else {
            Text(verbatim: "—")
        }
    }
}

// MARK: - Thread detail

/// The last exchange, three quick replies and a dictated reply. Reads the
/// thread live from the store, so the optimistic reply shows in the card
/// the moment it is sent.
private struct DMThreadDetail: View {
    let peerId: UUID

    @Environment(WatchStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// When the last reply left; while set, the chips rest so a second tap
    /// cannot send the same answer twice.
    @State private var sentAt: Date? = nil

    private var thread: DMConversationEntry? {
        store.payload?.dmConversations.first { $0.id == peerId }
    }

    private var animation: Animation {
        WatchTheme.Motion.resolved(WatchTheme.Motion.snappy, reduceMotion: reduceMotion)
    }

    var body: some View {
        Group {
            if let thread {
                content(thread)
            } else {
                Color.clear
            }
        }
        .skyGround()
        // The thread left the payload (account change, phone pruned it):
        // there is nothing to answer any more.
        .onChange(of: thread == nil) { _, isGone in
            if isGone { dismiss() }
        }
        .task(id: sentAt) {
            guard sentAt != nil else { return }
            do { try await Task.sleep(for: DMTiming.sentConfirmation) } catch { return }
            withAnimation(animation) { sentAt = nil }
        }
    }

    private func content(_ thread: DMConversationEntry) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: WatchTheme.Spacing.l) {
                LastMessageCard(thread: thread)
                    .watchEntrance(0)

                if sentAt != nil {
                    StateLabel("watch_dm_sent", systemImage: "checkmark.circle.fill",
                               tint: WatchTheme.Tint.success)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .transition(WatchTheme.Motion.transition(reduceMotion: reduceMotion))
                }

                VStack(alignment: .leading, spacing: WatchTheme.Spacing.s) {
                    SectionHeader("watch_quick_replies")
                    ForEach(QuickReply.allCases) { reply in
                        Button {
                            send(reply.text, to: thread)
                        } label: {
                            Label(reply.titleKey, systemImage: reply.systemImage)
                        }
                        .buttonStyle(QuickReplyChipStyle())
                    }
                }
                .disabled(sentAt != nil)
                .watchEntrance(1)
            }
            .padding(.horizontal, WatchTheme.Spacing.xxs)
        }
        .navigationTitle(Text(verbatim: thread.peerName))
        .toolbar {
            ToolbarItem(placement: .bottomBar) {
                // Dictation / Scribble / keyboard — the system's input
                // surface on the wrist.
                TextFieldLink(prompt: Text("watch_dm_reply_prompt")) {
                    SentAwareGlyph(idleSystemImage: "arrowshape.turn.up.left.fill",
                                   idleLabelKey: "watch_dm_reply",
                                   isSent: sentAt != nil)
                } onSubmit: { text in
                    send(text, to: thread)
                }
            }
        }
    }

    /// The store trims, ignores empty text and plays `.done`.
    private func send(_ text: String, to thread: DMConversationEntry) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        withAnimation(animation) {
            store.sendDM(to: thread.id, text: text)
            sentAt = Date()
        }
    }
}

/// Who spoke last, what they said (private), and when.
private struct LastMessageCard: View {
    let thread: DMConversationEntry

    var body: some View {
        WatchCard(tint: WatchTheme.Tint.messages) {
            VStack(alignment: .leading, spacing: WatchTheme.Spacing.xs) {
                HStack(spacing: WatchTheme.Spacing.s) {
                    InitialsAvatar(name: thread.peerName, seed: thread.id, size: WatchTheme.Size.rowIcon)
                    Group {
                        if thread.lastIsMine {
                            Text("watch_dm_you")
                        } else {
                            Text(verbatim: thread.peerName)
                        }
                    }
                    .font(WatchTheme.Typography.captionStrong)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                }

                DMPreviewText(thread: thread)
                    .font(WatchTheme.Typography.body)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                    .watchPrivate()

                if let at = thread.lastAt {
                    Text(at, format: .relative(presentation: .named))
                        .font(WatchTheme.Typography.caption)
                        .foregroundStyle(.tertiary)
                        .watchAlwaysOnDimmed()
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Shared pieces

/// A toolbar compose glyph that briefly becomes a checkmark once sent.
/// The label stays meaningful for VoiceOver in both states.
private struct SentAwareGlyph: View {
    let idleSystemImage: String
    let idleLabelKey: LocalizedStringKey
    let isSent: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Label(isSent ? LocalizedStringKey("watch_dm_sent") : idleLabelKey,
              systemImage: isSent ? "checkmark" : idleSystemImage)
            .labelStyle(.iconOnly)
            .contentTransition(reduceMotion ? ContentTransition.opacity
                                            : ContentTransition.symbolEffect(.replace))
    }
}

/// A quick-reply chip: a full-width tinted capsule (content, never glass),
/// a stroke in Always On, a soft press that only fades under Reduce Motion.
private struct QuickReplyChipStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        configuration.label
            .font(WatchTheme.Typography.rowTitle)
            .lineLimit(2)
            .minimumScaleFactor(0.8)
            .frame(maxWidth: .infinity, minHeight: WatchTheme.Size.actionMinHeight, alignment: .leading)
            .padding(.horizontal, WatchTheme.Spacing.l)
            .background {
                WatchSurface(tint: WatchTheme.Tint.messages, radius: WatchTheme.Radius.row)
            }
            .contentShape(RoundedRectangle(cornerRadius: WatchTheme.Radius.row, style: .continuous))
            .opacity(isEnabled ? (pressed && reduceMotion ? 0.7 : 1) : WatchTheme.AlwaysOn.contentOpacity)
            .scaleEffect(pressed && !reduceMotion ? 0.96 : 1)
            .animation(WatchTheme.Motion.resolved(WatchTheme.Motion.snappy, reduceMotion: reduceMotion),
                       value: pressed)
            .watchAlwaysOnDimmed()
    }
}
