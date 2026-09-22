import CloudKit
import PhotosUI
import SwiftUI
import UIKit

struct ContentView: View {
    @StateObject private var service = CloudKitService()
    @Environment(\.scenePhase) private var scenePhase

    @State private var selectedItem: PhotosPickerItem?
    @State private var draftImageData: Data?
    @State private var caption = ""
    @State private var shareToPresent: CKShare?
    @State private var showingShare = false

    var body: some View {
        NavigationStack {
            Group {
                if service.isConnected {
                    connectedView
                } else {
                    setupView
                }
            }
            .navigationTitle("WidgetWidget")
            .overlay {
                if service.isBusy {
                    ProgressView()
                        .controlSize(.large)
                        .padding(24)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
                }
            }
        }
        .sheet(isPresented: $showingShare) {
            if let shareToPresent {
                CloudSharingView(share: shareToPresent, container: service.container)
            }
        }
        .alert(
            "Something went wrong",
            isPresented: Binding(
                get: { service.errorMessage != nil },
                set: { if !$0 { service.errorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {
                service.errorMessage = nil
            }
        } message: {
            Text(service.errorMessage ?? "")
        }
        .onReceive(NotificationCenter.default.publisher(for: .pairDidChange)) { _ in
            service.reloadFromStore()
            Task { await service.refreshLatest() }
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            service.reloadFromStore()
            Task { await service.refreshLatest() }
        }
        .onChange(of: service.displayName) { _, _ in
            service.persistDisplayName()
        }
        .onChange(of: selectedItem) { _, newValue in
            guard let newValue else { return }
            Task {
                draftImageData = try? await newValue.loadTransferable(type: Data.self)
            }
        }
        .task {
            if service.isConnected {
                await service.refreshLatest()
            }
        }
    }

    private var setupView: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "rectangle.stack.badge.person.crop")
                .font(.system(size: 64))
                .symbolRenderingMode(.hierarchical)

            VStack(spacing: 10) {
                Text("A meme on both home screens")
                    .font(.title2.bold())

                Text("Create one shared iCloud widget, invite a friend, and either of you can replace the meme.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            }

            TextField("Your name", text: $service.displayName)
                .textFieldStyle(.roundedBorder)
                .textContentType(.name)
                .autocorrectionDisabled()
                .padding(.horizontal, 24)

            Button {
                Task {
                    service.persistDisplayName()
                    if let share = await service.createPair() {
                        shareToPresent = share
                        showingShare = true
                    }
                }
            } label: {
                Label("Create Shared Widget", systemImage: "person.2.badge.plus")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.horizontal, 24)
            .disabled(
                service.isBusy
                || service.displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            )

            Text("Your friend joins from the iCloud share link.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            Spacer()
        }
        .padding()
    }

    private var connectedView: some View {
        ScrollView {
            VStack(spacing: 24) {
                latestCard
                composer

                HStack {
                    Button {
                        Task { await service.refreshLatest() }
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }

                    Spacer()

                    if service.isOwner {
                        Button {
                            Task {
                                if let share = await service.fetchShare() {
                                    shareToPresent = share
                                    showingShare = true
                                }
                            }
                        } label: {
                            Label("Invite", systemImage: "person.badge.plus")
                        }
                    }
                }
                .buttonStyle(.bordered)

                Button("Disconnect This Device", role: .destructive) {
                    service.disconnect()
                }
                .font(.footnote)
            }
            .padding()
        }
    }

    private var latestCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("On the widget")
                    .font(.headline)
                Spacer()
                if let sentAt = service.latest?.sentAt {
                    Text(sentAt, style: .relative)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if let meme = service.latest, let image = UIImage(data: meme.imageData) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 18))

                if !meme.caption.isEmpty {
                    Text(meme.caption)
                        .font(.title3.weight(.semibold))
                }

                Text("from \(meme.senderName)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ContentUnavailableView(
                    "No meme yet",
                    systemImage: "photo",
                    description: Text("Send the first one below.")
                )
                .frame(minHeight: 220)
            }
        }
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Send a meme")
                .font(.headline)

            TextField("Your name", text: $service.displayName)
                .textFieldStyle(.roundedBorder)
                .textContentType(.name)
                .autocorrectionDisabled()

            PhotosPicker(selection: $selectedItem, matching: .images) {
                Label(
                    draftImageData == nil ? "Choose Meme" : "Change Meme",
                    systemImage: "photo.on.rectangle"
                )
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)

            if let draftImageData, let image = UIImage(data: draftImageData) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 280)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
            }

            TextField("Caption (optional)", text: $caption, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(1...3)

            Button {
                guard let draftImageData else { return }
                Task {
                    let didSend = await service.sendMeme(
                        imageData: draftImageData,
                        caption: caption
                    )
                    if didSend {
                        self.draftImageData = nil
                        selectedItem = nil
                        caption = ""
                    }
                }
            } label: {
                Label("Send to Widget", systemImage: "paperplane.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(
                draftImageData == nil
                || service.isBusy
                || service.displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            )
        }
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 22))
    }
}
