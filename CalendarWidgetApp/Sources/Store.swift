import SwiftUI
import StoreKit

/// The one-time Ahead Plus purchase (StoreKit 2).
/// The result is saved in the App Group so the widget knows whether Plus applies.
@MainActor
final class Store: ObservableObject {
    /// Must match the Product ID created in App Store Connect.
    static let productID = "com.ralphgeb.calendarwidgetapp.unlock"

    @Published var product: Product?
    @Published var isPro = SharedSettings.isPro
    @Published var isBusy = false
    @Published var message: String?

    private var updates: Task<Void, Never>?

    init() {
        updates = Task { [weak self] in
            for await result in StoreKit.Transaction.updates {
                await self?.handle(result)
            }
        }
        Task { await refresh() }
    }

    deinit { updates?.cancel() }

    /// TestFlight only: "Reset to free version" makes the app act as if Ahead Plus wasn't bought,
    /// until it is bought or restored again. Never set in an App Store download.
    private static let forcedFreeKey = "testflight.forcedFree"
    static var forcedFree: Bool {
        get { SharedSettings.defaults.bool(forKey: forcedFreeKey) }
        set { SharedSettings.defaults.set(newValue, forKey: forcedFreeKey) }
    }

    func refresh() async {
        product = try? await Product.products(for: [Self.productID]).first
        var owned = false
        for await result in StoreKit.Transaction.currentEntitlements {
            if case .verified(let t) = result, t.productID == Self.productID, t.revocationDate == nil {
                owned = true
            }
        }
        #if targetEnvironment(simulator)
        owned = true   // the simulator (Appetize) can't buy: everything is unlocked to look at
        #endif
        if Self.forcedFree { owned = false }
        setPro(owned)
    }

    /// TestFlight: back to the free version, to test what free users see.
    func resetToFree() {
        Self.forcedFree = true
        setPro(false)
    }

    /// Simulator only: Ahead Plus back on after "Reset to free version".
    func simulatorUnlock() async {
        Self.forcedFree = false
        await refresh()
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
        Self.forcedFree = false
        try? await AppStore.sync()
        await refresh()
        if !isPro { message = "No previous purchase was found for this Apple ID." }
    }

    private func handle(_ result: VerificationResult<StoreKit.Transaction>) async {
        guard case .verified(let t) = result, t.productID == Self.productID else { return }
        Self.forcedFree = false
        await t.finish()
        setPro(t.revocationDate == nil)
    }

    private func setPro(_ value: Bool) {
        let changed = SharedSettings.isPro != value
        isPro = value
        SharedSettings.isPro = value
        if changed {
            SharedSettings.reloadWidgets()
            NotificationCenter.default.post(name: .colorsChanged, object: nil)   // free and Plus look different
        }
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

                Text("Ahead Plus")
                    .font(.title2.bold())

                VStack(alignment: .leading, spacing: 12) {
                    Label("Choose which calendars to show", systemImage: "calendar")
                    Label("All themes, plus your own colors", systemImage: "paintpalette")
                    Label("Use the medium and Lock Screen widgets", systemImage: "lock.rectangle")
                    Label("One payment, yours forever", systemImage: "checkmark.seal")
                }
                .font(.body)

                Spacer()

                if store.isPro {
                    Label("Ahead Plus is unlocked", systemImage: "checkmark.circle.fill")
                        .font(.headline)
                        .foregroundStyle(.green)
                } else {
                    Button {
                        Task { await store.buy() }
                    } label: {
                        Group {
                            if store.isBusy { ProgressView() }
                            else { Text("Get Ahead Plus for \(store.product?.displayPrice ?? "£1.99")") }
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(store.isBusy || store.product == nil)

                    Button("Restore purchase") { Task { await store.restore() } }
                        .disabled(store.isBusy)
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
