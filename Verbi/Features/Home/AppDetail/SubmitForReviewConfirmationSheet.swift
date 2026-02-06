import SwiftUI

struct SubmitForReviewConfirmationSheet: View {
    @Binding var releaseOption: ReleaseOption
    @Binding var isPhasedReleaseEnabled: Bool
    let versionNumber: String?
    let onCancel: () -> Void
    let onSubmit: () -> Void

    @State private var showSubmitConfirmation = false
    
    private var canSubmit: Bool {
        if releaseOption.kind == .scheduled {
            return releaseOption.scheduledDate != nil
        }
        return true
    }

    private var confirmationMessage: String {
        switch releaseOption.kind {
        case .manual:
            return "This version will be submitted for review and released manually after approval."
        case .afterApproval:
            if isPhasedReleaseEnabled {
                return "This version will be submitted for review and released automatically in phases after approval."
            }
            return "This version will be submitted for review and released automatically after approval."
        case .scheduled:
            return "This version will be submitted for review and released on the scheduled date and time."
        }
    }
    
    var body: some View {
        VStack(spacing: 20) {
            // Header
            VStack(spacing: 8) {
                Image(systemName: "paperplane.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(.blue)
                
                Text("Submit for Review")
                    .font(.title2)
                    .fontWeight(.bold)
                
                if let version = versionNumber {
                    Text("Version \(version)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            
            Divider()
            
            // Release Type Selection
            VStack(alignment: .leading, spacing: 12) {
                Text("Release Option")
                    .font(.headline)
                
                VStack(spacing: 8) {
                    ForEach(ReleaseOption.Kind.allCases) { kind in
                        ReleaseTypeOptionRow(
                            displayName: kind.displayName,
                            description: kind.description,
                            isSelected: releaseOption.kind == kind,
                            onTap: {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    releaseOption = kind.defaultOption()
                                    if kind != .afterApproval {
                                        isPhasedReleaseEnabled = false
                                    }
                                }
                            }
                        )
                        
                        // Show date picker inline for scheduled type
                        if kind == .scheduled && releaseOption.kind == .scheduled {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Select Release Date & Time")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .padding(.leading, 44)
                                
                                DatePicker(
                                    "",
                                    selection: Binding(
                                        get: {
                                            releaseOption.scheduledDate ?? ReleaseOption.defaultScheduledDate()
                                        },
                                        set: { releaseOption = .scheduled($0) }
                                    ),
                                    in: Date()...,
                                    displayedComponents: [.date, .hourAndMinute]
                                )
                                .datePickerStyle(.compact)
                                .labelsHidden()
                                .padding(.leading, 44)
                                .padding(.vertical, 8)
                            }
                            .transition(.move(edge: .top).combined(with: .opacity))
                        }
                    }

                    if releaseOption.kind == .afterApproval {
                        Toggle(isOn: $isPhasedReleaseEnabled) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Release in Phases")
                                    .font(.subheadline)
                                Text("Roll out this version gradually over 7 days in eligible territories.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .toggleStyle(.switch)
                        .padding(.leading, 44)
                        .padding(.top, 4)
                    }
                }
            }
            
            Divider()
            
            // Info text
            Text("Once submitted, your app will be reviewed by Apple. This process typically takes 24-48 hours.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            
            // Action buttons
            HStack(spacing: 12) {
                Button("Cancel") {
                    onCancel()
                }
                .buttonStyle(.bordered)

                Button("Submit for Review") {
                    showSubmitConfirmation = true
                }
                .buttonStyle(.borderedProminent)
                .tint(.blue)
                .disabled(!canSubmit)
            }
        }
        .padding(28)
        .frame(width: 460)
        .onAppear {
            if releaseOption.kind != .afterApproval {
                isPhasedReleaseEnabled = false
            }
        }
        .onChange(of: releaseOption.kind) { _, newValue in
            if newValue != .afterApproval {
                isPhasedReleaseEnabled = false
            }
        }
        .alert("Submit for Review", isPresented: $showSubmitConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Submit") {
                onSubmit()
            }
        } message: {
            Text(confirmationMessage)
        }
    }
}

struct ReleaseTypeOptionRow: View {
    let displayName: String
    let description: String
    let isSelected: Bool
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                // Radio button indicator
                ZStack {
                    Circle()
                        .stroke(isSelected ? Color.blue : Color.gray.opacity(0.4), lineWidth: 2)
                        .frame(width: 22, height: 22)
                    
                    if isSelected {
                        Circle()
                            .fill(Color.blue)
                            .frame(width: 12, height: 12)
                    }
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(displayName)
                        .font(.subheadline)
                        .fontWeight(isSelected ? .semibold : .regular)
                    
                    Text(description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                }
                
                Spacer()
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Color.blue.opacity(0.1) : Color.clear)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(isSelected ? Color.blue.opacity(0.3) : Color.gray.opacity(0.2), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
    }
}

#Preview {
    SubmitForReviewConfirmationSheet(
        releaseOption: .constant(.manual),
        isPhasedReleaseEnabled: .constant(false),
        versionNumber: "1.2.0",
        onCancel: {},
        onSubmit: {}
    )
}
