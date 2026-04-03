import SwiftUI

// MARK: - Toast Model

enum ToastStyle {
    case success
    case error

    var backgroundColor: Color {
        switch self {
        case .success: Color(hexString: "#CEFAC8")
        case .error: Color(hexString: "#FFD2D2")
        }
    }

    var textColor: Color {
        switch self {
        case .success: Color.successGreen
        case .error: Color(hexString: "#AC1010")
        }
    }
}

struct ToastItem: Equatable {
    let id = UUID()
    let message: String
    let style: ToastStyle

    static func success(_ message: String) -> ToastItem {
        ToastItem(message: message, style: .success)
    }

    static func error(_ message: String) -> ToastItem {
        ToastItem(message: message, style: .error)
    }

    static func == (lhs: ToastItem, rhs: ToastItem) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Toast View

struct CarryToastView: View {
    let toast: ToastItem

    var body: some View {
        Text(toast.message)
            .font(.system(size: 14, weight: .medium))
            .foregroundColor(toast.style.textColor)
            .lineLimit(2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 17)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(toast.style.backgroundColor)
            )
            .padding(.horizontal, 23)
    }
}

// MARK: - Toast Manager

@MainActor
final class ToastManager: ObservableObject {
    static let shared = ToastManager()

    @Published var currentToast: ToastItem?
    private var dismissTask: Task<Void, Never>?

    private init() {}

    func show(_ toast: ToastItem, duration: TimeInterval = 2.5) {
        dismissTask?.cancel()
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            currentToast = toast
        }
        dismissTask = Task {
            try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.25)) {
                currentToast = nil
            }
        }
    }

    func success(_ message: String) {
        show(.success(message))
    }

    func error(_ message: String) {
        show(.error(message))
    }
}

// MARK: - Toast Overlay Modifier

struct ToastOverlay: ViewModifier {
    @ObservedObject var manager = ToastManager.shared

    @State private var dragOffset: CGFloat = 0

    func body(content: Content) -> some View {
        content.overlay(alignment: .top) {
            if let toast = manager.currentToast {
                CarryToastView(toast: toast)
                    .offset(y: dragOffset)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .padding(.top, 8)
                    .zIndex(999)
                    .onTapGesture {
                        withAnimation(.easeOut(duration: 0.2)) {
                            manager.currentToast = nil
                        }
                    }
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                if value.translation.height < 0 {
                                    dragOffset = value.translation.height
                                }
                            }
                            .onEnded { value in
                                if value.translation.height < -30 {
                                    withAnimation(.easeOut(duration: 0.2)) {
                                        manager.currentToast = nil
                                    }
                                }
                                withAnimation(.spring(response: 0.3)) {
                                    dragOffset = 0
                                }
                            }
                    )
            }
        }
    }
}

extension View {
    func carryToastOverlay() -> some View {
        modifier(ToastOverlay())
    }
}
