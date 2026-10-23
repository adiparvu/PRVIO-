import SwiftUI

// MARK: - Messages: the wrist inbox
//
// One row per direct-message thread (the first eight — more is a phone
// job): peer, last exchange, unread count. A thread opens to its last
// message and a dictated reply that rides the queue with the thread's
// identity, so it lands in THAT conversation on the phone, never in the
// family chat. The family chat itself is one dictation away in the bottom
// toolbar.
//
// Thread detail is a feature-specific route: the Home stack is shared by
// every module, and a bare UUID destination would collide with another
// feature's.

struct MessagesView: View {
    @Environment(WatchStore.self) private var store

    /// When the last family message was handed to the store; drives the
    /// toolbar's brief "sent" glyph.
    @State private var chatSentAt: Date?

    /// Wrist reading stops here; the phone holds the full inbox.
    private static let maxThreads = 8

    init() {}

    private var threads: [DMConversationEntry] {
        Array((store.payload?.dmConversations ?? []).prefix(Self.maxThreads))
    }

    var body: some View {
        Group {
            if threads.isEmpty {
                AllClearView(systemImage: WatchModule.messages.systemImage)
            } else {
                List(threads, id: \.id) { thread in
                    NavigationLink(value: DMThreadRoute(peerId: thread.id)) {
                        DMThreadRow(thread: thread)
                    }
                    .watchRowBackground(thread.unread > 0 ? WatchTheme.Tint.messages : WatchTheme.Tint.neutral)
                }
            }
        }
        .navigationTitle(Text(WatchModule.messages.titleKey))
        .navigationDestination(for: DMThreadRoute.self) { route in
            DMThreadDetail(peerId: route.peerId)
        }
        .watchPageGround(WatchTheme.Tint.messages)
        .toolbar {
            ToolbarItem(placement: .bottomBar) {
                // Dictate for the household chat; the phone sends the real
                // message through the same queue notification replies use.
                TextFieldLink(prompt: Text("watch_chat_prompt")) {
                    Label(chatSentAt == nil ? LocalizedStringKey("watch_chat_send")
                                            : LocalizedStringKey("watch_dm_sent"),
                          systemImage: chatSentAt == nil ? "person.3.fill" : "checkmark")
                        .labelStyle(.iconOnly)
                        .contentTransition(.symbolEffect(.replace))
                } onSubmit: { text in
                    guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                    store.sendChatMessage(text)
                    withAnimation(WatchTheme.Motion.snappy) { chatSentAt = Date() }
                }
            }
        }
        .task(id: chatSentAt) {
            guard chatSentAt != nil else { return }
            // Cancelled (a newer send restarted the clock, or the screen
            // left) → keep the newer state untouched.
            do { try await Task.sleep(for: DMTiming.sentConfirmation) } catch { return }
            withAnimation(WatchTheme.Motion.smooth) { chatSentAt = nil }
        }
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

// MARK: - Row

private struct DMThreadRow: View {
    let thread: DMConversationEntry

    private var unread: Int { max(0, thread.unread) }

    var body: some View {
        HStack(spacing: WatchTheme.Spacing.s) {
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: thread.peerName)
                    .font(unread > 0 ? WatchTheme.Typography.cardTitle : WatchTheme.Typography.rowTitle)
                    .lineLimit(1)
                DMPreviewText(thread: thread)
                    .font(WatchTheme.Typography.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
            if unread > 0 {
                CountBadge(count: unread, tint: WatchTheme.Tint.messages)
                    .accessibilityLabel(Text("watch_unread_count \(min(unread, 99))"))
            }
        }
        .accessibilityElement(children: .combine)
        // Mail is not for whoever glances at a resting wrist.
        .privacySensitive()
    }
}

/// The last message, safely: media becomes a label (never a raw storage
/// path), the user's own message is prefixed so a glance tells who spoke.
private struct DMPreviewText: View {
    let thread: DMConversationEntry

    var body: some View {
        if thread.isMedia {
            Text("watch_dm_media")
        } else if let body = thread.lastBody, !body.isEmpty {
            if thread.lastIsMine {
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

/// The last exchange plus a dictated reply. Reads the thread live from the
/// store, so the optimistic reply shows in the card the moment it is sent.
private struct DMThreadDetail: View {
    let peerId: UUID

    @Environment(WatchStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var sentAt: Date?

    private var thread: DMConversationEntry? {
        store.payload?.dmConversations.first { $0.id == peerId }
    }

    var body: some View {
        Group {
            if let thread {
                content(thread)
            } else {
                Color.clear
            }
        }
        .watchPageGround(WatchTheme.Tint.messages)
        // The thread left the payload (account change, phone pruned it):
        // there is nothing to answer any more.
        .onChange(of: thread == nil) {
            if thread == nil { dismiss() }
        }
        .task(id: sentAt) {
            guard sentAt != nil else { return }
            do { try await Task.sleep(for: DMTiming.sentConfirmation) } catch { return }
            withAnimation(WatchTheme.Motion.smooth) { sentAt = nil }
        }
    }

    private func content(_ thread: DMConversationEntry) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: WatchTheme.Spacing.m) {
                WatchCard(tint: WatchTheme.Tint.messages) {
                    VStack(alignment: .leading, spacing: WatchTheme.Spacing.xxs) {
                        Group {
                            if thread.lastIsMine {
                                Text("watch_dm_you")
                            } else {
                                Text(verbatim: thread.peerName)
                            }
                        }
                        .font(WatchTheme.Typography.captionStrong)
                        .foregroundStyle(.secondary)

                        DMPreviewText(thread: thread)
                            .font(WatchTheme.Typography.body)
                            .foregroundStyle(.primary)

                        if let at = thread.lastAt {
                            Text(at, format: .relative(presentation: .named))
                                .font(WatchTheme.Typography.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
                .accessibilityElement(children: .combine)
                .privacySensitive()

                if sentAt != nil {
                    Label {
                        Text("watch_dm_sent")
                    } icon: {
                        Image(systemName: "checkmark.circle.fill")
                            .accessibilityHidden(true)
                    }
                    .font(WatchTheme.Typography.captionStrong)
                    .foregroundStyle(WatchTheme.Tint.success)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .transition(.opacity)
                    .watchAlwaysOnDimmed()
                }
            }
        }
        .navigationTitle(Text(verbatim: thread.peerName))
        .toolbar {
            ToolbarItem(placement: .bottomBar) {
                // Dictation / Scribble / keyboard — the system's input
                // surface on the wrist.
                TextFieldLink(prompt: Text("watch_dm_reply_prompt")) {
                    Label(sentAt == nil ? LocalizedStringKey("watch_dm_reply")
                                        : LocalizedStringKey("watch_dm_sent"),
                          systemImage: sentAt == nil ? "arrowshape.turn.up.left.fill" : "checkmark")
                        .labelStyle(.iconOnly)
                        .contentTransition(.symbolEffect(.replace))
                } onSubmit: { text in
                    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { return }
                    withAnimation(WatchTheme.Motion.snappy) {
                        store.sendDM(to: thread.id, text: trimmed)
                        sentAt = Date()
                    }
                }
                .watchAlwaysOnDimmed()
            }
        }
    }
}
