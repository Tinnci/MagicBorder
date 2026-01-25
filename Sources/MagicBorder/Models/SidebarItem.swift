import Foundation

enum SidebarItem: String, CaseIterable, Identifiable {
    case arrangement
    case machines

    var id: String { self.rawValue }

    var title: String {
        switch self {
        case .arrangement: return "Arrangement"
        case .machines: return "Discovered Machines"
        }
    }

    var icon: String {
        switch self {
        case .arrangement: return "square.grid.2x2"
        case .machines: return "laptopcomputer.and.iphone"
        }
    }
}
