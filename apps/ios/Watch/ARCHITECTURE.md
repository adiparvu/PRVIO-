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
2. **One map, one way back.** One list of sections (the sidebar of a
   collapsed `NavigationSplitView`); the app opens on Today, not on the list.
   Back is always the system button in the top leading corner (or the left
   edge swipe): one level up inside a section, the list from a section root.
   At most two levels below the list.
3. **HIG, current cycle.** No primary double-tap action in lists or scroll
   views (only on fixed, non-scrolling screens). No Liquid
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
    WatchRoute.swift           sections (pages + modules), deep links, Handoff mapping, visibility
    WatchSensorAlerts.swift    critical-sensor haptics + local notifications
  Design/
    WatchTheme.swift           tokens: tints, spacing, radii, strokes, type, motion, Always On, sky palette + warmth
    WatchComponents.swift      sky ground, cards, Home Pulse dial, corners, Next Up, state label, action glyph,
                               celebration, Crown stepper, rows, empty / all-clear states
    WatchHaptics.swift         the haptic vocabulary (DESIGN.md) — every haptic goes through it
  Features/
    Root/RootView.swift        waiting screen, split view (list + section stacks), deep links, Handoff, fresh start
    Today/TodayView.swift      Home Pulse: dial + corners + headline, Next Up / celebration, brief, cards
    Tasks/…                    list, detail, new-task dictation, work session
    Plants/…                   thirsty list, detail, water all
    Sections/SectionsView.swift the sections list: Today · everyday lists · house systems, live status + badges
    Shopping/ Pantry/ Deliveries/ Messages/ Map/ Controls/ Sensors/ Emergency/
  Intents/
    WatchAppShortcuts.swift    Siri shortcuts + App Entities for tasks and plants
  Widgets/                     complications extension (separate target)
```

## Navigation

- Root: `NavigationSplitView(preferredCompactColumn:)`, collapsed by watchOS
  into one stack. Sidebar: `SectionsView`, a `List(selection:)` of
  `WatchSection` (`.page(WatchPage)` = today / tasks / plants,
  `.module(WatchModule)` = shopping, pantry, deliveries, messages, map,
  controls, sensors, emergency) in three groups — Today; the everyday lists
  (Messages first, then Tasks / Plants / modules in the phone's `pageOrder`);
  the house's systems (controls, sensors, emergency; family scope only).
  A section is listed only when its data exists (`WatchRoute.sectionGroups`).
- Detail: the selected section's root inside its own `NavigationStack`
  (`.id(section)`); each section keeps its own path, so returning to a
  section finds it where it was. The launch selection is Today with the
  detail column preferred — the app never opens on the list.
- Back: the system's top-leading button and edge swipe only — never a custom
  back button. Inside a section it pops; at a section root it returns to
  the list. Depth: list → section → detail (→ work session from a task).
- Fresh start: after 10 minutes in the background every stack is reset and
  the app reopens on Today at the top.
- Today's corners and cards push `WatchDestination.page/.module/.workSession`
  on Today's own stack, so back returns to Today.
- The selection is clamped to the visible sections; a deep link or a vanished
  section can never land on a missing screen.
- Deep links `prvio://<host>`: `tasks`, `plants`, `shopping`/`supplies`,
  `pantry`, `deliveries`/`packages`, `messages`, `emergency` select that
  section at its root; anything else → Today.
- Handoff: `com.prvio.page` with `userInfo["tab"]` (today→home,
  tasks→tasks, plants→plants, shopping→supplies, messages→chat, map→map,
  others→home) — the module on screen wins over its page.

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
  section root (`TodayView`, `TasksPage`, `PlantsPage`, `ShoppingView` …
  `EmergencyView`) in its own stack; `WorkSessionView` and details are always
  *pushed* onto one of those stacks. Never add a custom back button.
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
- Selecting sections is RootView's job (deep links, fresh start); feature
  views push `WatchDestination` values instead, so back always returns.
- Every page root and pushed screen applies `.skyGround()` (Emergency:
  `.signalGround(WatchTheme.Tint.emergency)`) and sets
  `.navigationTitle(Text(<key>))` — module titles: `Text(module.titleKey)`.
  (`.watchPageGround(_:)` / `.watchSignalGround(_:)` still compile and forward
  to these; new code uses the new names.)
- HIG: no `handGestureShortcut(.primaryAction)` in lists or scroll views —
  only on a fixed, non-scrolling screen (e.g. `WorkSessionView` when
  its layout fits; fall back to a `ScrollView` without it via `ViewThatFits`).
  Primary actions go in `ToolbarItem(placement: .bottomBar)`, secondary ones
  in `.topBarTrailing`. No `glassEffect` in content.
- Privacy: message bodies, DM previews, emergency details, budget and
  insights get `.watchPrivate()` (privacy-sensitive + redacted in Always On).

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
var sectionGroups: [[WatchSection]]       // the sections list, grouped
var visibleSections: [WatchSection]
func isVisible(_ page: WatchPage) -> Bool
func isVisible(_ module: WatchModule) -> Bool
func isVisible(_ section: WatchSection) -> Bool
var openTasks: [TaskCatalogEntry]         // open only, overdue first
var thirstyPlants: [PlantCatalogEntry]    // needsWatering
var pendingSupplies: [SupplyCatalogEntry] // !isCompleted
var canAlertFamily: Bool                  // family scope + property name known
var householdState: WatchHouseholdState   // .calm / .attention / .alarm (sky warmth, dial)
var attentionCount: Int                   // overdue tasks + thirsty plants + alerting sensors (family)
var openItemCount: Int                    // open tasks + thirsty plants + unbought shopping
var isAllClear: Bool                      // payload present && openItemCount == 0
var nextUp: WatchNextUp?                  // overdue task → thirsty plant → parcel out for delivery → next task
private(set) var allClearEvent: WatchAllClearEvent?   // set only by a LOCAL edit that empties a list
```

`allClearEvent` is in memory only: payloads from the phone, reloads and
relaunches never set it, so a celebration plays once per clear and never on
reload. Pages celebrate with `.watchAllClearCelebration(.tasks / .plants /
.shopping)`; Today celebrates `.household` inline.

Intents (each mutates optimistically, persists, repaints complications,
plays the `WatchHaptic` in brackets and queues the frozen action):

```swift
func completeTask(_ id: UUID)                          // [done]
func createTask(title: String)                         // [done] trims; empty ignored; inserted at top
func waterPlant(_ id: UUID)                            // [done]
func waterAllPlants()                                  // [done once] every thirsty plant
func checkSupply(_ id: UUID)                           // [tick]
func consumePantry(_ id: UUID)                         // [tick] one unit; no-op at quantity 0
func addPantryItemToShoppingList(_ id: UUID)           // [tick] no optimistic row
func markDeliveryReceived(_ id: UUID)                  // [done]
func sendChatMessage(_ text: String)                   // [done] household chat
func sendDM(to peerId: UUID, text: String)             // [done] peerId = DMConversationEntry.id
func alertFamily()                                     // [alarm] guarded by canAlertFamily — confirm in UI first
func startEmergency()                                  // [alarm] family scope only
func sendCommand(actuatorId: UUID, command: String)    // [tick] only commands in ActuatorCatalogEntry.commands
func startSession(task: TaskCatalogEntry)              // [sessionStart] replaces any running session
func pauseSession()                                    // [sessionStop]
func resumeSession()                                   // [sessionStart]
func toggleSessionPause()
func endSession(completingTask: Bool)                  // true [done] completes the task; false [sessionStop]
func requestRefresh()                                  // [tick] on reply, [retry] empty reply, [unreachable] no phone
func reloadFromCache()                                 // RootView calls it on scene activation
func ingest(_ data: Data, source: WatchIngestSource = .push)   // connector only
```

A store intent already plays its haptic — never play another one for the
same tap (leave `ActionGlyphButton.haptic` nil when the action is an intent).
Pantry with the Crown: `CrownStepper` commits a lower quantity; call
`consumePantry` once per unit of the difference (the wire only knows "one
unit"); increases are not on the wire — clamp the stepper's range to
`0...quantity`.

Animate list changes at the call site:
`withAnimation(WatchTheme.Motion.resolved(WatchTheme.Motion.snappy, reduceMotion: reduceMotion)) { store.checkSupply(id) }`
(`ActionGlyphButton` already does this for its action).

Payload vocabulary feature views need: `WatchRoute.isDeliveryActive(_:)`
(status `expected`/`out_for_delivery`); delivery statuses `expected`,
`out_for_delivery`, `delivered`, `missed`, `returned` (localized with the
existing catalog keys `Expected`, `Out for delivery`, `Delivered`, `Missed`,
`Returned`); weather advisory tokens `frost`/`rain`.

### Routes (Core/WatchRoute.swift)

```swift
enum WatchPage: String, CaseIterable, Hashable, Identifiable, Codable { case today, tasks, plants
    var titleKey: LocalizedStringKey; var systemImage: String; var tint: Color }

enum WatchModule: String, CaseIterable, Hashable, Identifiable, Codable {
    case shopping, pantry, deliveries, messages, map, controls, sensors, emergency
    var titleKey: LocalizedStringKey; var systemImage: String; var tint: Color
    var requiresFamilyScope: Bool                    // controls, sensors, emergency
    func hasContent(in payload: WatchPayload) -> Bool
    func badge(in payload: WatchPayload) -> WatchBadge?   // nil when nothing needs the user
}
struct WatchBadge: Equatable { let count: Int; let isUrgent: Bool }

enum WatchHouseholdState: Equatable, Sendable { case calm, attention, alarm
    var tint: Color; var systemImage: String; var titleKey: LocalizedStringKey }   // extension in WatchTheme
enum WatchNextUp: Identifiable {
    case task(TaskCatalogEntry, isOverdue: Bool); case plant(PlantCatalogEntry); case delivery(DeliveryCatalogEntry)
    var id: String }
enum WatchClearScope: Hashable, Sendable { case tasks, plants, shopping, household }
struct WatchAllClearEvent: Equatable, Sendable { let serial: Int; let scopes: Set<WatchClearScope> }

enum WatchSection: Hashable, Identifiable, Codable { case page(WatchPage); case module(WatchModule)
    static let today; var titleKey; var systemImage; var tint }
enum WatchDestination: Hashable, Codable { case page(WatchPage); case module(WatchModule); case workSession }
enum WatchDeepLink: Equatable { case page(WatchPage); case module(WatchModule); init(url: URL) }

enum WatchRoute {
    static let defaultOrder: [String]
    static func pageOrder(for payload: WatchPayload) -> [String]
    static func visiblePages(for payload: WatchPayload?) -> [WatchPage]
    static func visibleModules(for payload: WatchPayload?) -> [WatchModule]
    static func sectionGroups(for payload: WatchPayload?) -> [[WatchSection]]
    static func visibleSections(for payload: WatchPayload?) -> [WatchSection]
    static func canAlertFamily(_ payload: WatchPayload) -> Bool
    static func isDeliveryActive(_ parcel: DeliveryCatalogEntry) -> Bool
    static func isOutForDelivery(_ parcel: DeliveryCatalogEntry) -> Bool   // status out_for_delivery
    static func householdState(for payload: WatchPayload?) -> WatchHouseholdState
    static func attentionCount(for payload: WatchPayload?) -> Int
    static func openItemCount(for payload: WatchPayload?) -> Int
    static func nextUp(for payload: WatchPayload?) -> WatchNextUp?     // only from visible pages/modules
    static let handoffActivityType: String            // "com.prvio.page"
    static func handoffTab(section: WatchSection, pushed: WatchModule?) -> String
}
```

Visibility: Today always; Tasks while enabled in `pageOrder` (even with no
open task — the all-clear and dictation live there); Plants when enabled and
at least one plant exists. Modules: Messages
(DMs exist) first, then shopping (open items) / pantry (items) / deliveries
(any) / map (coordinates) in `pageOrder` order and only if listed, then
controls (actuators), sensors (sensors), emergency (property name, contacts
or steps) — the last three in family scope only. Badges: shopping open
items, pantry items at 0, active deliveries, total DM unread, alerting
sensors (urgent when one is critical).

### Theme (Design/WatchTheme.swift) — "the sky of the house"

```swift
WatchTheme.Tint.{today, tasks, plants, water, home, shopping, pantry, deliveries, messages,
                 map, controls, sensors, emergency, session, weather, insight, streak,
                 critical, warning, success, neutral,
                 calm, attention, alarm}                           // Color (system colours)
WatchTheme.Spacing.{xxs 2, xs 4, s 6, m 8, l 10, xl 12, xxl 16}    // CGFloat
WatchTheme.Radius.{small 10, row 12, card 14, hero 18}             // CGFloat, style: .continuous
WatchTheme.Size.{healthRing 54, rowIcon 24, urgentDot 5, actionMinHeight 36,
                 dial 84, prominentGlyph 36, celebrationGlyph 44}
WatchTheme.Stroke.{ring 7, hairline 1, hairlineIncreased 1.5}
static func WatchTheme.Stroke.outline(_ contrast: ColorSchemeContrast) -> CGFloat
WatchTheme.Opacity.{cardTop, cardBottom, cardTopIncreased, cardBottomIncreased, ground, skyTop,
                    skyBottom, signalGround, alwaysOnGround, alwaysOnContent, glyphFill,
                    ringTrack, outline}                            // Double
WatchTheme.Typography.{hero, headline, brief, metric, temperature, cardTitle, body, rowTitle,
                       caption, captionStrong, badge, glyph, clockLarge, clockInline,
                       sectionHeader, numeralHero, numeral, numeralSmall, dialGlyph}  // Font
    // text styles only (Dynamic Type); SF Rounded for every numeral — add
    // .monospacedDigit() where the value ticks
WatchTheme.Motion.{snappy (0.30 s), smooth (0.35 s), entrance, ringFill, crossfade}   // Animation
WatchTheme.Motion.actionConfirmDelay: Duration                     // 300 ms
WatchTheme.Motion.celebrationHold: Duration                        // 2.6 s
WatchTheme.Motion.entranceStagger: Double
static func WatchTheme.Motion.resolved(_ animation: Animation, reduceMotion: Bool) -> Animation  // cross-fade under RM
static func WatchTheme.Motion.transition(reduceMotion: Bool) -> AnyTransition                  // fade+scale / fade
WatchTheme.AlwaysOn.{groundOpacity 0.25, contentOpacity 0.6, strokeOpacity 0.7}
WatchTheme.Warmth.{amber, alarm, attentionTop, attentionBottom, alarmTop, alarmBottom}
static func WatchTheme.cardFill(_ tint: Color, increasedContrast: Bool = false) -> LinearGradient
static func WatchTheme.harmonized(_ tint: Color, with skyAccent: Color?) -> Color   // leans 18 % to the sky
static func WatchTheme.scoreColor(_ score: Int) -> Color

struct WatchSkyPalette: Equatable {                    // top, bottom, topOpacity, bottomOpacity
    static let fallback: WatchSkyPalette                // night blue (no sky, no mood)
    static func resolve(sky: WatchSky?, mood: WatchMood?) -> WatchSkyPalette   // sky > mood > fallback
    static func signal(_ tint: Color) -> WatchSkyPalette                       // Emergency
    func warmed(for state: WatchHouseholdState) -> WatchSkyPalette            // calm / amber / red
    func gradient(dim: Double = 1) -> LinearGradient
    var accent: Color
}
enum WatchMood: String { case morning, day, sunset, night, rain, winter, event
    var palette: WatchSkyPalette; var pageWash: LinearGradient }
struct WatchSky: Equatable { init?(payload: WatchPayload?); var pageWash: LinearGradient }
EnvironmentValues.watchSkyAccent: Color?               // set by skyGround; surfaces harmonize with it
```

Motion rules: nothing longer than 0.35 s; symbol effects carry meaning —
`breathe` calm, `wiggle` needs you, `bounce` done, `drawOn` celebration,
`pulse` live session. Reduce Motion: no symbol effects, no scale — wrap
animations in `Motion.resolved(_:reduceMotion:)`, insert/remove with
`Motion.transition(reduceMotion:)`.

Always On (`@Environment(\.isLuminanceReduced)`): animations and symbol
effects stop (gate `isActive:` on it), fills become strokes (`WatchSurface`,
`WatchCard`, rows, `ActionGlyphButton(.prominent)` do it for you), the
ground dims, secondary content uses `.watchAlwaysOnDimmed()`, seconds
disappear (`TimelineView` cadence — `SessionClockText` handles it), and
`.watchPrivate()` redacts. Increase Contrast (`\.colorSchemeContrast ==
.increased`): surfaces get stronger fills and an outline automatically.

### Haptics (Design/WatchHaptics.swift)

```swift
enum WatchHaptic: CaseIterable, Sendable {
    case done          // .success      task done, plant watered, delivery received, message sent
    case tick          // .click        shopping checked, pantry unit, command, refresh answered
    case sessionStart  // .start        session start / resume
    case sessionStop   // .stop         session stop / pause / end without completing
    case retry         // .retry        command failed (empty reply)
    case unreachable   // .failure      phone unreachable
    case alarm         // .notification critical sensor, emergency raised
    case celebration   // .success      all-clear (once)
    var type: WKHapticType
    @MainActor func play()          // identical haptics within 0.8 s coalesce (never .alarm)
    @MainActor static var isEnabled: Bool   // false in previews
}
```

Never call `WKInterfaceDevice.current().play` directly. Crown detents click
by themselves (`isHapticFeedbackEnabled: true`) — no extra haptic.

### Components (Design/WatchComponents.swift)

```swift
// Grounds and modifiers
extension View {
    func skyGround() -> some View                         // the house sky, warmed by householdState; AOD dim
    func signalGround(_ tint: Color = WatchTheme.Tint.emergency) -> some View   // Emergency only
    func watchPageGround(_ tint: Color) -> some View      // legacy → skyGround()
    func watchSignalGround(_ tint: Color) -> some View    // legacy → signalGround(_:)
    func watchAlwaysOnDimmed() -> some View
    func watchPrivate() -> some View                      // privacySensitive + redacted in Always On
    func watchRowBackground(_ tint: Color) -> some View   // List row surface (sky-harmonized, AOD stroke)
    func watchEntrance(_ index: Int) -> some View         // staggered entrance; off under Reduce Motion
    func watchScrollDepth() -> some View                  // ScrollView cards recede at the edges
    func watchAllClearCelebration(_ scope: WatchClearScope) -> some View
        // overlays CelebrationView when store.allClearEvent contains `scope`, for Motion.celebrationHold
}

WatchSurface(tint: Color, radius: CGFloat = WatchTheme.Radius.card)   // fill / outline / AOD stroke
WatchCard(tint: Color = WatchTheme.Tint.neutral, radius: CGFloat = WatchTheme.Radius.card) { content }

PulseDial(score: Int?, state: WatchHouseholdState, attentionCount: Int, summary: Text,
          size: CGFloat = WatchTheme.Size.dial)
    // house glyph in the health ring (number under the glyph); breathes when .calm, one wiggle
    // when attentionCount rises; static under RM; outline in AOD; VoiceOver reads `summary` only

CornerReadout(systemImage: String, labelKey: LocalizedStringKey, tint: Color,
              alignment: HorizontalAlignment = .leading, isUrgent: Bool = false, isLive: Bool = false,
              accessibilityValue: Text, @ViewBuilder value: () -> Value)
CornerReadout(count: Int, systemImage: String, labelKey: LocalizedStringKey, tint: Color,
              alignment: HorizontalAlignment = .leading, isUrgent: Bool = false)   // Value == Text
    // display only — wrap in Button/NavigationLink (.plain) only when the target is visible;
    // pass the base symbol name (".fill" is added outside Always On)

StateLabel(_ titleKey: LocalizedStringKey, systemImage: String, tint: Color)   // symbol + word
StateLabel(state: WatchHouseholdState)

ActionGlyphButton(systemImage: String, actedSystemImage: String, tint: Color,
                  labelKey: LocalizedStringKey, isRepeatable: Bool = false,
                  prominence: ActionGlyphButton.Prominence = .row,   // .row | .prominent (filled circle)
                  haptic: WatchHaptic? = nil,                        // nil when `action` is a store intent
                  action: @escaping () -> Void)
    // one-shot: symbol replaced + bounce, action after 300 ms in withAnimation (RM: immediately,
    // cross-faded); repeatable: acts on every tap with no delay

NextUpCard(title: String, detail: String? = nil, state: StateLabel? = nil, tint: Color,
           actionSystemImage: String, actedSystemImage: String,
           actionLabelKey: LocalizedStringKey, action: @escaping () -> Void)
NextUpCard(_ nextUp: WatchNextUp, action: @escaping () -> Void)   // action = the matching store intent

CelebrationView(serial: Int, tint: Color = WatchTheme.Tint.success)
    // checkmark drawOn (RM: fade) + WatchHaptic.celebration once + rotating line
    // (watch_celebrate_1…4 by serial); give the host .id(serial)

CrownStepper(value: Double, in range: ClosedRange<Double>, step: Double = 1, unit: String? = nil,
             tint: Color, labelKey: LocalizedStringKey, onCommit: @escaping (Double) -> Void)
    // Digital Crown detents (system click per step), commit on idle; − / + buttons;
    // VoiceOver adjustable; Crown disabled when the range is a single value

CountBadge(count: Int, tint: Color = WatchTheme.Tint.messages, isUrgent: Bool = false)  // urgent adds "!"
ModuleRow(titleKey: LocalizedStringKey, systemImage: String, tint: Color, badge: WatchBadge? = nil)
ModuleRow(module: WatchModule, payload: WatchPayload)
HealthRing(score: Int, size: CGFloat = WatchTheme.Size.healthRing)
AllClearView(systemImage: String, messageKey: LocalizedStringKey = "watch_all_good")   // breathing glyph
EmptyStateView(systemImage: String, titleKey: LocalizedStringKey, messageKey: LocalizedStringKey? = nil)
SectionHeader(_ titleKey: LocalizedStringKey)                         // naked text header
SessionClockText(session: WatchWorkSession, font: Font = WatchTheme.Typography.clockInline)
extension TimeInterval { var watchClockText: String; var watchClockMinutesText: String }
```

Typical row:

```swift
List(store.pendingSupplies, id: \.id) { item in
    HStack(spacing: WatchTheme.Spacing.m) {
        ActionGlyphButton(systemImage: "circle", actedSystemImage: "checkmark.circle.fill",
                          tint: WatchTheme.Tint.shopping, labelKey: "watch_tap_check") {
            store.checkSupply(item.id)          // the intent plays .tick
        }
        Text(verbatim: item.name).font(WatchTheme.Typography.body).lineLimit(2)
    }
    .watchRowBackground(WatchTheme.Tint.shopping)
}
.navigationTitle(Text(WatchModule.shopping.titleKey))
.skyGround()
.watchAllClearCelebration(.shopping)
```

Copy: encouraging, never pressure — "3 open", not "3 OVERDUE"; overdue is
`StateLabel("watch_overdue", systemImage: "exclamationmark.circle.fill",
tint: WatchTheme.Tint.attention)`, never red shouting. Every state is a
symbol + a word.

Localization: reuse the existing `watch_*` / `emg_*` keys; new user-facing
strings get a new `watch_` key added to `Resources/Localizable.xcstrings`
(en + ro). Payload text (names, titles) renders with `Text(verbatim:)`.
