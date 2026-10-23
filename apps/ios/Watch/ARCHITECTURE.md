# PRVIO for Apple Watch — architecture (watchOS 27 baseline)

Rebuilt from zero in October 2026 on the watchOS 27 SDK. The deployment
target is **watchOS 27.0** (owner's decision): every current-cycle API is
used directly, with no availability branches for older systems.

The rules in `apps/ios/CLAUDE.md` apply here too. Where they reference the
phone-only design system (`AppFont`, `AppSpacing`…), the watch uses its own
`WatchTheme` tokens (Design/WatchTheme.swift) — `DesignSystem.swift` is not
compiled into the watch targets.

## Principles

1. **Glance first.** The watch answers "what needs me now?" in one look and
   acts in one tap. Anything deeper belongs on the phone.
2. **Few top-level pages.** A vertical pager of at most four pages — Today,
   Tasks, Plants, Home — instead of the old ten. Everything else is a row in
   the Home hub, pushed in a `NavigationStack`.
3. **HIG, current cycle.** No primary double-tap action in lists, scroll views
   or the vertical pager (only on fixed, non-scrolling screens). No Liquid
   Glass in the content layer — glass is for system chrome only. Text ≥ 11 pt
   in complications; system text styles everywhere in the app. Always On:
   respect `isLuminanceReduced` and `TimelineView` cadence. Primary actions
   live in the bottom toolbar (`.bottomBar`), secondary ones top trailing.
4. **One source of truth.** `WatchStore` (`@MainActor @Observable`) owns the
   payload, the work session and every optimistic edit. Views never touch
   `WCSession` or `UserDefaults` directly.
5. **Stable contract.** The payload, action and persistence formats shared
   with the phone (listed below) are frozen. The rewrite changes the watch,
   not the wire.

## Layout

```
Watch/
  App/
    PRVIOWatchApp.swift        @main, scene, WKApplicationDelegate adaptor
    WatchCrashRecorder.swift   uncaught-exception + launch-death recorder
  Core/
    WatchStore.swift           @MainActor @Observable — state, ingest, persistence, optimistic edits
    WatchConnector.swift       WCSessionDelegate (nonisolated → hops to MainActor)
    WatchAction.swift          typed actions → userInfo dictionaries (frozen keys)
    WatchRoute.swift           pages, hub modules, deep links, Handoff mapping, visibility
    WatchSensorAlerts.swift    critical-sensor haptics + local notifications
  Design/
    WatchTheme.swift           tokens: tints per module, spacing, radii, mood/sky ground
    WatchComponents.swift      reusable views (cards, rows, metric tile, health ring, all-clear, action button)
  Features/
    Root/RootView.swift        waiting screen, pager, deep links, Handoff
    Today/TodayView.swift      hero, metrics, session/weather/unread/insight/focus cards
    Tasks/…                    list, detail, new-task dictation, work session
    Plants/…                   thirsty list, detail, water all
    Home/HomeHubView.swift     hub list → Shopping, Pantry, Deliveries, Messages, Map, Controls, Sensors, Emergency
    Shopping/ Pantry/ Deliveries/ Messages/ Map/ Controls/ Sensors/ Emergency/
  Intents/
    WatchAppShortcuts.swift    Siri shortcuts + App Entities for tasks and plants
  Widgets/                     complications extension (separate target)
```

## Navigation

- Root: `TabView(selection:)` with `.tabViewStyle(.verticalPage)` over
  `WatchPage` = `.today`, `.tasks`, `.plants`, `.home`. A page is present only
  when its data exists (`WatchRoute.visiblePages(for:)`); the selection is
  clamped to the visible set, so a deep link can never land on a missing page.
- Each page owns its own `NavigationStack`.
- Home hub rows (`WatchModule`): shopping, pantry, deliveries, messages, map,
  controls, sensors, emergency — ordered by the phone's `pageOrder`, shown
  only when they have data, and emergency/controls/sensors only in family
  scope (`isFamilyScope`).
- Deep links `prvio://<host>`: `tasks`, `plants` select their page;
  `shopping`/`supplies`, `pantry`, `deliveries`/`packages`, `messages`,
  `emergency` select Home and push the module; anything else → Today.
- Handoff: `com.prvio.page` with `userInfo["tab"]` (today→home,
  tasks→tasks, plants→plants, shopping→supplies, messages→chat, map→map,
  others→home).

## Frozen contract (do not change)

- Bundle ids `com.prvio.app.watchkitapp`, `com.prvio.app.watchkitapp.widgets`;
  App Group `group.com.prvio.app`.
- `WatchPayload` and every nested type in `Sources/Services/SharedDataStore.swift`
  (shared with the phone; decoded tolerantly).
- applicationContext key `payload`; refresh message `{"action":"refresh"}` →
  reply `{"payload": Data}`.
- userInfo actions and keys: `completeTask`, `waterPlant`, `checkSupply`,
  `consumePantry`, `deliveryReceived`, `pantryToList` (`id`); `createTask`
  (`title`); `sendMessage` (`text`, `target` = `group` | `dm:<uuid>`);
  `alertFamily`; `sessionStart` (`id`, `title`, `startedAt` epoch string);
  `sessionPause`, `sessionResume`, `sessionEnd` (+ new optional `complete`
  = "1"/"0"); `iotCommand` (`actuatorId`, `command`); `startEmergency`;
  `watchCrash` (`text`). De-duplication key `actionId` (UUID string).
- Defaults keys `prvio.watch.payload`, `.mood`, `.session`,
  `.criticalSensorIds`, `.lastCrash`, `.launchInFlight`, `.launchDeathCount`;
  the `WatchActionRelay` queue used by complications and Siri.
- Widget kinds `PRVIOWatchStatus`, `PRVIOWatchTasks`, `PRVIOWatchWater`,
  `PRVIOWatchShopping`, `PRVIOWatchDeliveries`, `PRVIOWatchHealth`,
  `PRVIOWatchWeather`, `PRVIOWatchBudget`, `PRVIOWatchSession`,
  `PRVIOWatchChoice` (renaming removes them from watch faces).
- Intent type names `CompleteTopTaskIntent(taskId)`,
  `PRVIODomainConfigIntent(domain)`, `WatchDomainOption` raw values,
  `CompleteNextTaskSiriIntent`, `WaterAllPlantsSiriIntent`.
- Notification id prefix `prvio.sensor.`.

## Defects fixed on purpose (from the inventory of the old app)

1. Outsiders saw the Emergency page whenever a property name existed → family scope only.
2. Today tiles, the module grid and deep links could select pages missing from the pager → selection is clamped to visible routes.
3. The watch only checked `accountId == nil`; a different account's cached payload survived → the stored account is compared and everything (payload, session, mood, alerts) is cleared on change.
4. "End session" always completed the task on the phone → `sessionEnd` carries `complete`.
5. Actuator `commands` were ignored; buttons were hard-coded by kind → buttons come from `commands`.
6. Redundant mood probing and stale comments → removed.
7. Strings that existed only in legacy `.lproj` tables → moved into the string catalog.

## Core API (for feature views)

Everything a feature view needs is below. Feature views are plain SwiftUI
`View`s with no-argument initializers, read the store from the environment,
and never touch `WCSession`, `UserDefaults` or `WidgetCenter`.

### Getting the store

```swift
struct ShoppingView: View {
    @Environment(WatchStore.self) private var store
    var body: some View { … }
}
```

`RootView` injects the single `WatchStore` (`.environment(store)` in
`PRVIOWatchApp`). For `#Preview`, use `WatchStore(preview:session:)`:

```swift
#Preview { NavigationStack { ShoppingView() }.environment(WatchStore(preview: samplePayload)) }
```

### Navigation rules

- **Never create a `NavigationStack`** in a feature view. `RootView` wraps each
  pager page (`TodayView`, `TasksPage`, `PlantsPage`, `HomeHubView`) in its own
  stack, and module views (`ShoppingView` … `EmergencyView`) and
  `WorkSessionView` are always *pushed* onto one of those stacks.
- Shared routes are `WatchDestination` values, registered once per stack by
  `RootView` (`.watchDestinations`). Push them with
  `NavigationLink(value: WatchDestination.workSession) { … }` or
  `NavigationLink(value: WatchDestination.module(.messages)) { … }`.
  **Do not** register `navigationDestination(for: WatchDestination.self)` again.
- Feature-internal detail screens: register your own destination on your
  view's root with a **feature-specific Hashable type** (e.g.
  `struct TaskRoute: Hashable { let id: UUID }`), never a bare `UUID`/`String`
  — several features share the Home stack and a shared key type collides.
- Leave a pushed screen with `@Environment(\.dismiss)`. `WorkSessionView` must
  `dismiss()` itself when `store.session` becomes nil.
- Switching pager pages is RootView's job (Today tiles do it through a
  binding); feature views do not select pages.
- Every page root and pushed screen applies `.watchPageGround(<tint>)`
  (Emergency: `.watchSignalGround(WatchTheme.Tint.emergency)`) and sets
  `.navigationTitle(Text(<key>))` — module titles: `Text(module.titleKey)`.
- HIG: no `handGestureShortcut(.primaryAction)` in lists, scroll views or the
  pager — only on a fixed, non-scrolling screen (e.g. `WorkSessionView` when
  its layout fits; fall back to a `ScrollView` without it via `ViewThatFits`).
  Primary actions go in `ToolbarItem(placement: .bottomBar)`, secondary ones
  in `.topBarTrailing`. No `glassEffect` in content.
- Privacy: message bodies, DM previews and anything personal get
  `.privacySensitive()`.

### `WatchStore` — `@MainActor @Observable final class` (Core/WatchStore.swift)

State (all `private(set)`, observe by reading):

| Property | Type | Meaning |
|---|---|---|
| `payload` | `WatchPayload?` | Phone payload, deduplicated by id. `nil` → RootView shows the waiting screen, so feature views can treat it as present but must still unwrap. |
| `session` | `WatchWorkSession?` | Running/paused work session (`isPaused`, `elapsed(at:)`, `clockText(at:)`, `taskId`, `title`, `startedAt`). |
| `mood` | `WatchMood?` | Phone mood (used by the page ground). |
| `sky` | `WatchSky?` | Phone sky (used by the page ground). |
| `crashNote` | `String?` | Previous launch's crash report. |
| `connectivity` | `WatchConnectivityState` | `.unsupported`, `.activating`, `.inactive`, `.reachable`, `.unreachable`. |
| `isRefreshing` | `Bool` | A live refresh is in flight. |

Derived (read-only):

```swift
var lastUpdated: Date?                    // payload?.snapshot.updatedAt
var accountId: String?
var isFamilyScope: Bool                   // true when no payload
var visiblePages: [WatchPage]
var visibleModules: [WatchModule]
func isVisible(_ page: WatchPage) -> Bool
func isVisible(_ module: WatchModule) -> Bool
var openTasks: [TaskCatalogEntry]         // open only, overdue first
var thirstyPlants: [PlantCatalogEntry]    // needsWatering
var pendingSupplies: [SupplyCatalogEntry] // !isCompleted
var canAlertFamily: Bool                  // family scope + property name known
```

Intents (each mutates optimistically, persists, repaints complications,
plays the haptic in brackets and queues the frozen action):

```swift
func completeTask(_ id: UUID)                          // [success]
func createTask(title: String)                         // [success] trims; empty ignored; inserted at top
func waterPlant(_ id: UUID)                            // [directionUp]
func waterAllPlants()                                  // [directionUp once] every thirsty plant
func checkSupply(_ id: UUID)                           // [click]
func consumePantry(_ id: UUID)                         // [click] no-op at quantity 0
func addPantryItemToShoppingList(_ id: UUID)           // [click] no optimistic row
func markDeliveryReceived(_ id: UUID)                  // [success]
func sendChatMessage(_ text: String)                   // [success] household chat
func sendDM(to peerId: UUID, text: String)             // [success] peerId = DMConversationEntry.id
func alertFamily()                                     // [notification] guarded by canAlertFamily — confirm in UI first
func startEmergency()                                  // [notification] family scope only
func sendCommand(actuatorId: UUID, command: String)    // [click] only commands in ActuatorCatalogEntry.commands
func startSession(task: TaskCatalogEntry)              // [start] replaces any running session
func pauseSession()                                    // [click]
func resumeSession()                                   // [start]
func toggleSessionPause()
func endSession(completingTask: Bool)                  // true [success] completes the task; false [stop] leaves it open
func requestRefresh()                                  // [click] on reply, [retry] when unreachable/failed
func reloadFromCache()                                 // RootView calls it on scene activation
func ingest(_ data: Data, source: WatchIngestSource = .push)   // connector only
```

Animate list changes at the call site: `withAnimation(WatchTheme.Motion.snappy) { store.checkSupply(id) }`
(`ActionGlyphButton` already does this for its action).

Payload vocabulary feature views need: `WatchRoute.isDeliveryActive(_:)`
(status `expected`/`out_for_delivery`); delivery statuses `expected`,
`out_for_delivery`, `delivered`, `missed`, `returned` (localized with the
existing catalog keys `Expected`, `Out for delivery`, `Delivered`, `Missed`,
`Returned`); weather advisory tokens `frost`/`rain`.

### Routes (Core/WatchRoute.swift)

```swift
enum WatchPage: String, CaseIterable, Hashable, Identifiable { case today, tasks, plants, home
    var titleKey: LocalizedStringKey; var systemImage: String; var tint: Color }

enum WatchModule: String, CaseIterable, Hashable, Identifiable, Codable {
    case shopping, pantry, deliveries, messages, map, controls, sensors, emergency
    var titleKey: LocalizedStringKey; var systemImage: String; var tint: Color
    var requiresFamilyScope: Bool                    // controls, sensors, emergency
    func hasContent(in payload: WatchPayload) -> Bool
    func badge(in payload: WatchPayload) -> WatchBadge?   // nil when nothing needs the user
}
struct WatchBadge: Equatable { let count: Int; let isUrgent: Bool }

enum WatchDestination: Hashable, Codable { case module(WatchModule); case workSession }
enum WatchDeepLink: Equatable { case page(WatchPage); case module(WatchModule); init(url: URL) }

enum WatchRoute {
    static let defaultOrder: [String]
    static func pageOrder(for payload: WatchPayload) -> [String]
    static func visiblePages(for payload: WatchPayload?) -> [WatchPage]
    static func visibleModules(for payload: WatchPayload?) -> [WatchModule]
    static func canAlertFamily(_ payload: WatchPayload) -> Bool
    static func isDeliveryActive(_ parcel: DeliveryCatalogEntry) -> Bool
    static let handoffActivityType: String            // "com.prvio.page"
    static func handoffTab(page: WatchPage, module: WatchModule?) -> String
}
```

Visibility: Today always; Tasks while enabled in `pageOrder` (even with no
open task — the all-clear and dictation live there); Plants when enabled and
at least one plant exists; Home when any module is visible. Modules: Messages
(DMs exist) first, then shopping (open items) / pantry (items) / deliveries
(any) / map (coordinates) in `pageOrder` order and only if listed, then
controls (actuators), sensors (sensors), emergency (property name, contacts
or steps) — the last three in family scope only. Badges: shopping open
items, pantry items at 0, active deliveries, total DM unread, alerting
sensors (urgent when one is critical).

### Theme (Design/WatchTheme.swift)

```swift
WatchTheme.Tint.{today, tasks, plants, water, home, shopping, pantry, deliveries, messages,
                 map, controls, sensors, emergency, session, weather, insight, streak,
                 critical, warning, success, neutral}              // Color
WatchTheme.Spacing.{xxs 2, xs 4, s 6, m 8, l 10, xl 12, xxl 16}    // CGFloat
WatchTheme.Radius.{small 10, row 12, card 14}                      // CGFloat, use style: .continuous
WatchTheme.Size.{healthRing 54, rowIcon 24, urgentDot 5, actionMinHeight 36}
WatchTheme.Opacity.{cardTop, cardBottom, ground, signalGround, alwaysOnGround,
                    alwaysOnContent, glyphFill}                    // Double
WatchTheme.Typography.{hero, metric, temperature, cardTitle, body, rowTitle, caption,
                       captionStrong, badge, glyph, clockLarge, clockInline, sectionHeader}  // Font
WatchTheme.Motion.{snappy, smooth, entrance, ringFill}             // Animation
WatchTheme.Motion.actionConfirmDelay: Duration                     // 380 ms
WatchTheme.Motion.entranceStagger: Double
static func WatchTheme.cardFill(_ tint: Color) -> LinearGradient
static func WatchTheme.scoreColor(_ score: Int) -> Color

enum WatchMood: String { case morning, day, sunset, night, rain, winter, event; var pageWash: LinearGradient }
struct WatchSky: Equatable { init?(payload: WatchPayload?); var pageWash: LinearGradient }

extension View {
    func watchPageGround(_ tint: Color) -> some View     // sky > mood > tint; dims in Always On
    func watchSignalGround(_ tint: Color) -> some View   // never adopts mood/sky (Emergency)
    func watchAlwaysOnDimmed() -> some View              // secondary content in Always On
}
```

Always On: read `@Environment(\.isLuminanceReduced)`; stop symbol effects and
dim secondary controls (`.watchAlwaysOnDimmed()`); `TimelineView` drops to
minute cadence (`SessionClockText` already handles it).

### Components (Design/WatchComponents.swift)

```swift
WatchCard(tint: Color = WatchTheme.Tint.neutral) { content }        // tinted fill card, no glass
MetricTile(count: Int, titleKey: LocalizedStringKey, systemImage: String, tint: Color,
           isUrgent: Bool = false)                                   // display only; wrap to act
CountBadge(count: Int, tint: Color = WatchTheme.Tint.messages, isUrgent: Bool = false)
ModuleRow(titleKey: LocalizedStringKey, systemImage: String, tint: Color, badge: WatchBadge? = nil)
ModuleRow(module: WatchModule, payload: WatchPayload)
HealthRing(score: Int, size: CGFloat = WatchTheme.Size.healthRing)
AllClearView(systemImage: String, messageKey: LocalizedStringKey = "watch_all_good")
EmptyStateView(systemImage: String, titleKey: LocalizedStringKey, messageKey: LocalizedStringKey? = nil)
ActionGlyphButton(systemImage: String, actedSystemImage: String, tint: Color,
                  labelKey: LocalizedStringKey, isRepeatable: Bool = false,
                  action: @escaping () -> Void)
    // one-shot: glyph fills + bounces, action after 380 ms (immediately with Reduce
    // Motion), wrapped in withAnimation(.snappy); repeatable: acts on every tap.
SectionHeader(_ titleKey: LocalizedStringKey)                         // naked text header
SessionClockText(session: WatchWorkSession, font: Font = WatchTheme.Typography.clockInline)

extension View {
    func watchRowBackground(_ tint: Color) -> some View   // tinted List row background
    func watchEntrance(_ index: Int) -> some View         // staggered entrance, off with Reduce Motion
}
extension TimeInterval { var watchClockText: String; var watchClockMinutesText: String }
```

Typical row:

```swift
List(store.pendingSupplies, id: \.id) { item in
    HStack(spacing: WatchTheme.Spacing.m) {
        ActionGlyphButton(systemImage: "circle", actedSystemImage: "checkmark.circle.fill",
                          tint: WatchTheme.Tint.shopping, labelKey: "watch_tap_check") {
            store.checkSupply(item.id)
        }
        Text(verbatim: item.name).font(WatchTheme.Typography.body).lineLimit(2)
    }
    .watchRowBackground(WatchTheme.Tint.shopping)
}
.navigationTitle(Text(WatchModule.shopping.titleKey))
.watchPageGround(WatchTheme.Tint.shopping)
```

Localization: reuse the existing `watch_*` / `emg_*` keys; new user-facing
strings get a new `watch_` key added to `Resources/Localizable.xcstrings`
(en + ro). Payload text (names, titles) renders with `Text(verbatim:)`.
