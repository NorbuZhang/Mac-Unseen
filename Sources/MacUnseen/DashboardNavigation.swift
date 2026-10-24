import Combine

/// Only navigation and toolbar state invalidate the window shell.
/// Live readings remain observed by the pages that display them.
@MainActor
final class DashboardNavigation: ObservableObject {
    @Published var selectedSection: DashboardSection? = .overview
    @Published var advancedSensorsActive = false
    @Published var isMagicAnglePresented = false
}
