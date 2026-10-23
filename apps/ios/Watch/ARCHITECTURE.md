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
