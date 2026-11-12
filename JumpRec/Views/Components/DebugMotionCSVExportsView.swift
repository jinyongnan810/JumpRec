//
//  DebugMotionCSVExportsView.swift
//  JumpRec
//

#if DEBUG
    import SwiftUI

    /// Shows saved debug motion CSV status and quick-share actions inside Settings.
    struct DebugMotionCSVSettingsSection: View {
        @State private var store = DebugMotionCSVStore.shared
        @State private var isShowingExportsSheet = false

        var body: some View {
            VStack(alignment: .leading, spacing: 14) {
                Text(String(localized: "Debug"))
                    .font(AppFonts.badgeLabel)
                    .tracking(2)
                    .foregroundStyle(AppColors.textMuted)

                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Text(String(localized: "Motion CSV Exports"))
                            .font(AppFonts.bodyLabelStrong)
                            .foregroundStyle(AppColors.textPrimary)
                        Spacer()
                        Text(store.items.count.formatted())
                            .font(AppFonts.bodyLabelStrong)
                            .foregroundStyle(AppColors.accent)
                    }

                    if let latest = store.items.first {
                        HStack(spacing: 10) {
                            Image(systemName: latest.source.systemImageName)
                                .font(AppFonts.bodyRegular)
                                .foregroundStyle(AppColors.accent)
                                .frame(width: 24)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(latest.source.localizedTitle)
                                    .font(AppFonts.bodyLabelStrong)
                                    .foregroundStyle(AppColors.textPrimary)

                                Text("\(latest.createdAt.formatted(date: .abbreviated, time: .shortened)) • \(latest.formattedSize)")
                                    .font(AppFonts.bodySmall)
                                    .foregroundStyle(AppColors.textSecondary)
                            }
                            Spacer()
                        }

                        ShareLink(item: latest.url) {
                            HStack(spacing: 8) {
                                Image(systemName: "square.and.arrow.up")
                                Text(String(localized: "Share Latest CSV"))
                            }
                            .font(AppFonts.primaryButtonLabel)
                            .foregroundStyle(AppColors.accentForeground)
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                            .background(AppColors.accent)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        .buttonStyle(.plain)
                    } else {
                        Text(String(localized: "Finish a workout on Apple Watch or iPhone to record motion CSV files here."))
                            .font(AppFonts.bodySmall)
                            .foregroundStyle(AppColors.textSecondary)
                    }

                    Button {
                        isShowingExportsSheet = true
                    } label: {
                        Text(String(localized: "Browse All Exports"))
                            .font(AppFonts.secondaryActionLabel)
                            .foregroundStyle(AppColors.textPrimary)
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                            .background(AppColors.cardSurface)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(AppColors.textMuted.opacity(0.3), lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(AppColors.bgPrimary.opacity(0.35))
                .overlay {
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(AppColors.accent.opacity(0.18), lineWidth: 1)
                }
                .clipShape(RoundedRectangle(cornerRadius: 16))
            }
            .onAppear {
                store.refresh()
            }
            .sheet(isPresented: $isShowingExportsSheet) {
                DebugMotionCSVExportsSheet()
            }
        }
    }

    /// Lists all locally saved motion CSV files so any Watch or iPhone recording can be shared or deleted.
    private struct DebugMotionCSVExportsSheet: View {
        @Environment(\.dismiss) private var dismiss
        @State private var store = DebugMotionCSVStore.shared
        @State private var isShowingClearConfirmation = false

        var body: some View {
            NavigationStack {
                Group {
                    if store.items.isEmpty {
                        ContentUnavailableView(
                            String(localized: "No Motion CSVs Yet"),
                            systemImage: "doc.text",
                            description: Text("Finish a workout on Apple Watch or iPhone to record motion CSV files here.")
                        )
                    } else {
                        List {
                            ForEach(store.items) { item in
                                HStack(spacing: 12) {
                                    Image(systemName: item.source.systemImageName)
                                        .font(AppFonts.sectionIcon)
                                        .foregroundStyle(AppColors.accent)
                                        .frame(width: 28)

                                    VStack(alignment: .leading, spacing: 4) {
                                        HStack(spacing: 6) {
                                            Text(item.source.localizedTitle)
                                                .font(AppFonts.bodyLabelStrong)
                                                .foregroundStyle(AppColors.textPrimary)

                                            Text(item.formattedSize)
                                                .font(AppFonts.bodySmall)
                                                .foregroundStyle(AppColors.textSecondary)
                                        }

                                        Text(item.createdAt.formatted(date: .abbreviated, time: .standard))
                                            .font(AppFonts.bodySmall)
                                            .foregroundStyle(AppColors.textSecondary)

                                        Text(item.filename)
                                            .font(AppFonts.bodySmall)
                                            .foregroundStyle(AppColors.textMuted)
                                            .lineLimit(1)
                                            .truncationMode(.middle)
                                    }

                                    Spacer(minLength: 8)

                                    ShareLink(item: item.url) {
                                        Image(systemName: "square.and.arrow.up")
                                            .font(AppFonts.sectionIcon)
                                            .foregroundStyle(AppColors.accent)
                                            .frame(width: 40, height: 40)
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel(Text(String(localized: "Share CSV")))
                                }
                                .listRowBackground(AppColors.bgPrimary.opacity(0.35))
                            }
                            .onDelete(perform: deleteItems)
                        }
                        .scrollContentBackground(.hidden)
                    }
                }
                .background(AppColors.cardSurface)
                .navigationTitle(String(localized: "Motion CSV Exports"))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    if !store.items.isEmpty {
                        ToolbarItem(placement: .topBarLeading) {
                            Button(String(localized: "Clear All"), role: .destructive) {
                                isShowingClearConfirmation = true
                            }
                            .foregroundStyle(.red)
                        }
                    }

                    ToolbarItem(placement: .topBarTrailing) {
                        Button(String(localized: "Done")) {
                            dismiss()
                        }
                    }
                }
                .alert(
                    String(localized: "Clear All Motion CSVs?"),
                    isPresented: $isShowingClearConfirmation
                ) {
                    Button(String(localized: "Delete"), role: .destructive) {
                        store.deleteAll()
                    }
                    Button(String(localized: "Cancel"), role: .cancel) {}
                } message: {
                    Text(String(localized: "This deletes all locally saved debug motion CSV files on this iPhone."))
                }
                .onAppear {
                    store.refresh()
                }
            }
            .preferredColorScheme(.dark)
        }

        private func deleteItems(at offsets: IndexSet) {
            for index in offsets where store.items.indices.contains(index) {
                store.delete(store.items[index])
            }
        }
    }
#endif
