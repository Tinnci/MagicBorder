import Foundation

enum SidebarItem: String, CaseIterable, Identifiable {
    case arrangement
    case settings
    case machines

    var id: String { self.rawValue }

    var title: String {
        switch self {
        case .arrangement: return "Arrangement"
        case .settings: return "Settings"
        case .machines: return "Discovered Machines"
        }
    }

    var icon: String {
        switch self {
        case .arrangement: return "square.grid.2x2"
        case .settings: return "gearshape"
        case .machines: return "laptopcomputer.and.iphone"
        }
    }
}
