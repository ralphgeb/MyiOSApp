import SwiftUI
import StoreKit
import WidgetKit

/// One-time "Unlock" purchase (StoreKit 2). Unlocks the Calendars and Colors settings.
/// The result is saved in the App Group so the widget knows whether custom settings apply.
@MainActor
final class Store: ObservableObject {
    /// Must match the Product ID created in App Store Connect.
    static let productID = "com.ralphgeb.calendarwidgetapp.unlock"

    @Published var product: Product?
    @Published var isPro = SharedSettings.isPro
    @Published var isBusy = false
    @Published var message: String?

    private var updates: Task<Void, Never>?

    /// TestFlight builds use Apple's sandbox, where purchases cost nothing.
    var isSandbox: Bool { Bundle.main.appStoreReceiptURL?.lastPathComponent == "sandboxReceipt" }

    /// Lets you test the locked/unlocked behaviour before the product exists in App Store Connect.
    /// Only shown in TestFlight, and only while the real product can't be loaded.
    var canTestUnlock: Bool { isSandbox && product == nil }

    init() {
        updates = Task { [weak self] in
            for await result in StoreKit.Transaction.updates {
                await self?.handle(result)
            }
        }
        Task { await refresh() }
    }

    deinit { updates?.cancel() }

    func refresh() async {
        product = try? await Product.products(for: [Self.productID]).first
        var owned = false
        for await result in StoreKit.Transaction.currentEntitlements {
            if case .verified(let t) = result, t.productID == Self.productID, t.revocationDate == nil {
                owned = true
            }
        }
        setPro(owned || SharedSettings.testUnlock)
    }

    func buy() async {
        guard let product else {
            message = "The purchase isn't available right now. Please try again later."
            return
        }
        isBusy = true
        defer { isBusy = false }
        do {
            switch try await product.purchase() {
            case .success(let result): await handle(result)
            case .pending: message = "Your purchase is waiting for approval."
            default: break
            }
        } catch {
            message = error.localizedDescription
        }
    }

    func restore() async {
        isBusy = true
        defer { isBusy = false }
        try? await AppStore.sync()
        await refresh()
        if !isPro { message = "No previous purchase was found for this Apple ID." }
    }

    /// TestFlight only, and only while the product isn't set up yet.
    func testUnlock() {
        SharedSettings.testUnlock = true
        setPro(true)
    }

    private func handle(_ result: VerificationResult<StoreKit.Transaction>) async {
        guard case .verified(let t) = result, t.productID == Self.productID else { return }
        await t.finish()
        setPro(t.revocationDate == nil)
    }

    private func setPro(_ value: Bool) {
        let changed = SharedSettings.isPro != value
        isPro = value
        SharedSettings.isPro = value
        if changed { SharedSettings.reloadWidgets() }
    }
}

/// The "upgrade" window.
struct PaywallView: View {
    @ObservedObject var store: Store
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 22) {
                Image(systemName: "lock.open.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(.tint)
                    .padding(.top, 24)

                Text("Unlock Customisation")
                    .font(.title2.bold())

                VStack(alignment: .leading, spacing: 12) {
                    Label("Choose which calendars to show", systemImage: "calendar")
                    Label("Change background, text and highlight colors", systemImage: "paintpalette")
                    Label("Use the small, medium and Lock Screen widgets", systemImage: "lock.rectangle")
                    Label("One payment, yours forever", systemImage: "checkmark.seal")
                }
                .font(.body)

                Spacer()

                if store.isPro {
                    Label("All widgets unlocked", systemImage: "checkmark.circle.fill")
                        .font(.headline)
                        .foregroundStyle(.green)
                } else {
                    Button {
                        Task { await store.buy() }
                    } label: {
                        Group {
                            if store.isBusy { ProgressView() }
                            else { Text("Unlock for \(store.product?.displayPrice ?? "£1.99")") }
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(store.isBusy || store.product == nil)

                    Button("Restore Purchase") { Task { await store.restore() } }
                        .disabled(store.isBusy)

                    if store.canTestUnlock {
                        Button("Unlock for Testing (TestFlight only)") { store.testUnlock() }
                            .font(.footnote)
                    }
                }

                if let message = store.message {
                    Text(message).font(.footnote).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 16)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .task { await store.refresh() }
    }
}
