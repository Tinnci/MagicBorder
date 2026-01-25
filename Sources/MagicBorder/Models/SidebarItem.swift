import Foundation

enum SidebarItem: String, CaseIterable, Identifiable {
    case arrangement
    case machines

    var id: String { rawValue }

    var title: String {
        switch self {
        case .arrangement: "Arrangement"
        case .machines: "Discovered Machines"
        }
    }

    var icon: String {
        switch self {
        case .arrangement: "square.grid.2x2"
        case .machines: "laptopcomputer.and.iphone"
        }
    }
}
