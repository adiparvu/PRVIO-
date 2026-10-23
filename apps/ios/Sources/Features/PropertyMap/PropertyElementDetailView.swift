import SwiftUI
import PhotosUI
import CoreLocation
import Supabase

struct PropertyElementDetailView: View {
    let element: PropertyElement

    @Environment(PropertyElementService.self) var elementService
    @Environment(CurrencyService.self) var currencyService
    @Environment(AppSettings.self) var appSettings
    @Environment(DocumentService.self) var documentService
    @Environment(TaskService.self) var taskService
    @Environment(PropertyService.self) var propertyService
    @Environment(\.dismiss) private var dismiss

    @State private var selectedTab: DetailTab = .info
    @State var showAddRecord = false
    @State private var showEditElement = false
    @State var localElement: PropertyElement
    @State private var showDeleteConfirm = false
    @State private var exportURL: ShareURL?
    @State var showLocationPicker = false
    @State var showLinkDocument = false
    @State var showLinkTask = false
    @State var photoItems: [PhotosPickerItem] = []
    @State var isUploading = false

    init(element: PropertyElement) {
        self.element = element
        _localElement = State(initialValue: element)
    }

    enum DetailTab: String, CaseIterable {
        case info      = "Info"
        case records   = "History"
        case documents = "Documents"
        case tasks     = "Tasks"

        var icon: String {
            switch self {
            case .info:      return "info.circle"
            case .records:   return "clock.arrow.circlepath"
            case .documents: return "doc.fill"
            case .tasks:     return "checklist"
            }
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                appBackground.ignoresSafeArea()

                VStack(spacing: 0) {
                    coverHero
                        .padding(.horizontal, AppSpacing.xl)
                        .padding(.top, AppSpacing.sm)

                    elementHeader
                        .padding(.horizontal, AppSpacing.xl)
                        .padding(.top, AppSpacing.md)
                        .padding(.bottom, AppSpacing.md)

                    healthSection
                        .padding(.horizontal, AppSpacing.xl)
                        .padding(.bottom, AppSpacing.lg)

                    DetailTabBar(selected: $selectedTab)
                        .padding(.horizontal, AppSpacing.xl)
                        .padding(.bottom, AppSpacing.sm)

                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 16) {
                            switch selectedTab {
                            case .info:      infoTab
                            case .records:   recordsTab
                            case .documents: documentsTab
                            case .tasks:     tasksTab
                            }
                            Spacer(minLength: 60)
                        }
                        .padding(.horizontal, AppSpacing.xl)
                        .padding(.top, AppSpacing.xxs)
                    }
                }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                            .font(AppFont.scaled(22))
                    }
                    .accessibilityLabel("Close")
                }
                ToolbarItem(placement: .pageMenu) {
                    Menu {
                        Button { showEditElement = true } label: {
                            Label("Edit", systemImage: "pencil")
                        }
                        Button {
                            Task { await elementService.toggleFavorite(elementId: localElement.id) }
                            localElement.isFavorite.toggle()
                            HapticFeedback.selection()
                        } label: {
                            Label(localElement.isFavorite ? "Remove from favorites" : "Add to favorites",
                                  systemImage: localElement.isFavorite ? "star.slash" : "star")
                        }
                        Button {
                            let element = localElement
                            Task {
                                if let u = await Task.detached(priority: .userInitiated, operation: { ElementPDFExporter.makePDF(for: element) }).value {
                                    exportURL = ShareURL(url: u)
                                }
                            }
                        } label: {
                            Label("Export PDF", systemImage: "square.and.arrow.up")
                        }
                        Button(role: .destructive) { showDeleteConfirm = true } label: {
                            Label("Delete element", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .foregroundStyle(.secondary)
                            .font(AppFont.scaled(20))
                    }
                }
            }
        }
        .sheet(isPresented: $showAddRecord) {
            AddElementRecordView(element: localElement) { payload in
                Task { await elementService.addRecord(payload) }
            }
        }
        .sheet(isPresented: $showEditElement) {
            EditPropertyElementView(element: $localElement) {
                Task { await elementService.update(localElement) }
            }
        }
        .sheet(item: $exportURL) { share in
            ActivityShareView(items: [share.url])
        }
        .sheet(isPresented: $showLocationPicker) {
            ObjectLocationPicker(
                element: localElement,
                propertyCenter: propertyService.primary.flatMap {
                    guard let lat = $0.latitude, let lon = $0.longitude
                    else { return nil }
                    return CLLocationCoordinate2D(latitude: lat, longitude: lon)
                }
            )
        }
        .sheet(isPresented: $showLinkDocument) {
            DocumentLinkPicker(elementId: localElement.id)
                .environment(documentService)
        }
        .sheet(isPresented: $showLinkTask) {
            TaskLinkPicker(elementId: localElement.id)
                .environment(taskService)
        }
        .onChange(of: photoItems) { _, items in
            Task { await uploadPhotos(items) }
        }
        .confirmationDialog("Delete \(localElement.name)?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                Task {
                    await elementService.delete(localElement)
                    dismiss()
                }
            }
        }
        .task {
            await elementService.loadRecords(elementId: localElement.id)
        }
        .onChange(of: elementService.elements) { _, updated in
            if let fresh = updated.first(where: { $0.id == localElement.id }) {
                localElement = fresh
            }
        }
    }

    // MARK: - Header

    private var heroImageURLs: [String] {
        var arr: [String] = []
        if let c = localElement.coverPhotoUrl { arr.append(c) }
        arr.append(contentsOf: localElement.photos.filter { $0 != localElement.coverPhotoUrl })
        return arr
    }

    @ViewBuilder
    private var coverHero: some View {
        let urls = heroImageURLs
        if !urls.isEmpty {
            TabView {
                ForEach(urls, id: \.self) { u in
                    StorageImage(source: u) { phase in
                        if case .success(let img) = phase { img.resizable().scaledToFill() }
                        else { Color.primary.opacity(AppOpacity.hairline) }
                    }
                    .clipped()
                }
            }
            .tabViewStyle(.page(indexDisplayMode: urls.count > 1 ? .automatic : .never))
            .frame(height: 200)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
        }
    }

    private var elementHeader: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(localElement.elementType.accentColor.opacity(0.2))
                    .frame(width: 60, height: 60)
                Image(systemName: localElement.elementType.icon)
                    .font(AppFont.scaled(24, weight: .semibold))
                    .foregroundStyle(localElement.elementType.accentColor)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(localElement.name)
                    .font(.title3.weight(.bold))
                HStack(spacing: 8) {
                    Text(localElement.elementType.displayName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("•")
                        .foregroundStyle(.tertiary)
                        .font(.caption)
                    conditionBadge
                }
                if let brand = localElement.brand, let model = localElement.model {
                    Text("\(brand) \(model)")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                } else if let brand = localElement.brand {
                    Text(brand)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            Spacer()
            warrantyBadge
        }
    }

    private var conditionBadge: some View {
        Text(localElement.technicalCondition.displayName)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(localElement.technicalCondition.color)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Capsule().fill(localElement.technicalCondition.color.opacity(0.15)))
    }

    private var warrantyBadge: some View {
        let status = localElement.warrantyStatus
        return VStack(spacing: 2) {
            Image(systemName: status == .none ? "shield.slash" : "shield.fill")
                .font(AppFont.scaled(16))
                .foregroundStyle(status.color)
            Text(status.label)
                .font(AppFont.scaled(9, weight: .medium))
                .foregroundStyle(status.color)
                .multilineTextAlignment(.center)
        }
        .frame(width: 60)
    }

    // MARK: - Health

    private var healthSection: some View {
        GlassCard(padding: 14) {
            VStack(spacing: 8) {
                HStack {
                    Text("Technical condition")
                        .font(.subheadline.weight(.medium))
                    Spacer()
                    Text("\(localElement.healthScore)/100")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(localElement.healthColor)
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.primary.opacity(0.08)).frame(height: 8)
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [localElement.healthColor.opacity(0.7), localElement.healthColor],
                                    startPoint: .leading, endPoint: .trailing
                                )
                            )
                            .frame(width: geo.size.width * CGFloat(localElement.healthScore) / 100, height: 8)
                    }
                }
                .frame(height: 8)
            }
        }
    }
}
