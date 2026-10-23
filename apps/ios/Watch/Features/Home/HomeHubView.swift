import SwiftUI

// MARK: - Home hub
//
// Every surface beyond Today, Tasks and Plants, as one list — only the
// modules with something to show, in the owner's order, family surfaces only
// in family scope (WatchRoute.visibleModules). Rows push `WatchDestination`
// values; the destinations are registered on this stack by RootView.

struct HomeHubView: View {
    @Environment(WatchStore.self) private var store

    var body: some View {
        Group {
            if let payload = store.payload, !store.visibleModules.isEmpty {
                List {
                    ForEach(store.visibleModules) { module in
                        NavigationLink(value: WatchDestination.module(module)) {
                            ModuleRow(module: module, payload: payload)
                        }
                        .watchRowBackground(module.tint)
                    }
                }
            } else {
                AllClearView(systemImage: WatchPage.home.systemImage)
            }
        }
        .navigationTitle(Text(WatchPage.home.titleKey))
        .watchPageGround(WatchTheme.Tint.home)
    }
}
