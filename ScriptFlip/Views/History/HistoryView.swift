import SwiftUI

/// View displaying the last 5 generated scripts with one-tap teleprompter launch, details, and delete actions.
public struct HistoryView: View {
    public let onLaunchPrompter: (Script) -> Void
    
    @Environment(\.dismiss) private var dismiss
    @State private var historyItems: [HistoryItem] = []
    @State private var selectedScriptForDetail: Script? = nil
    @State private var showClearConfirmation: Bool = false
    
    public init(onLaunchPrompter: @escaping (Script) -> Void) {
        self.onLaunchPrompter = onLaunchPrompter
    }
    
    public var body: some View {
        NavigationStack {
            ZStack {
                Color(red: 0.05, green: 0.05, blue: 0.07).ignoresSafeArea()
                
                if historyItems.isEmpty {
                    emptyStateView
                } else {
                    ScrollView {
                        VStack(spacing: 16) {
                            // Header hint
                            HStack {
                                Text("Last 5 Generated Scripts")
                                    .font(.subheadline.bold())
                                    .foregroundStyle(.gray)
                                Spacer()
                                Text("\(historyItems.count)/5 Saved")
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.cyan)
                            }
                            .padding(.horizontal, 20)
                            .padding(.top, 12)
                            
                            ForEach(historyItems) { item in
                                historyCard(for: item)
                            }
                        }
                        .padding(.bottom, 30)
                    }
                }
            }
            .navigationTitle("Script History")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") {
                        dismiss()
                    }
                    .font(.body.bold())
                    .foregroundStyle(.cyan)
                }
                
                if !historyItems.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(action: { showClearConfirmation = true }) {
                            Image(systemName: "trash")
                                .font(.subheadline)
                                .foregroundStyle(.red)
                        }
                    }
                }
            }
            .alert("Clear All History?", isPresented: $showClearConfirmation) {
                Button("Clear History", role: .destructive) {
                    HistoryManager.shared.clearHistory()
                    loadHistory()
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("This will delete all 5 recent script records from this device.")
            }
            .sheet(item: $selectedScriptForDetail) { script in
                ScriptResultsView(scripts: [script]) { prompterScript in
                    selectedScriptForDetail = nil
                    dismiss()
                    onLaunchPrompter(prompterScript)
                }
            }
            .onAppear {
                loadHistory()
            }
        }
    }
    
    private func loadHistory() {
        self.historyItems = HistoryManager.shared.getHistory()
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 54))
                .foregroundStyle(.gray.opacity(0.6))
            
            Text("No Script History Yet")
                .font(.title3.bold())
                .foregroundStyle(.white)
            
            Text("Your last 5 generated scripts will automatically appear here for fast teleprompter rehearsal.")
                .font(.subheadline)
                .foregroundStyle(.gray)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .padding()
    }
    
    private func historyCard(for item: HistoryItem) -> some View {
        let script = HistoryManager.shared.toScript(item: item)
        
        return VStack(alignment: .leading, spacing: 14) {
            // Top Row: Style Pill, Duration, and Timestamp
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                        .font(.caption2)
                    Text(item.styleUsed)
                        .font(.caption2.bold())
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.cyan.opacity(0.15))
                .foregroundStyle(.cyan)
                .cornerRadius(6)
                
                Text(item.estimatedDuration)
                    .font(.caption2.monospaced())
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Color.white.opacity(0.08))
                    .foregroundStyle(.gray)
                    .cornerRadius(4)
                
                Spacer()
                
                Text(formattedDate(item.timestamp))
                    .font(.caption2)
                    .foregroundStyle(.gray)
            }
            
            // Script Title
            Text(item.title)
                .font(.headline.bold())
                .foregroundStyle(.white)
            
            // Hook Preview
            VStack(alignment: .leading, spacing: 4) {
                Text("HOOK (0-3s)")
                    .font(.system(size: 10, weight: .black, design: .monospaced))
                    .foregroundStyle(.yellow)
                
                Text(item.hook)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.9))
                    .lineLimit(2)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white.opacity(0.03))
            .cornerRadius(8)
            
            // Action Buttons
            HStack(spacing: 10) {
                // Open in Teleprompter
                Button(action: {
                    dismiss()
                    onLaunchPrompter(script)
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "play.tv.fill")
                        Text("Prompter")
                    }
                    .font(.subheadline.bold())
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .frame(height: 38)
                    .background(
                        LinearGradient(
                            colors: [.cyan, .mint],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .cornerRadius(10)
                }
                
                // Copy
                Button(action: {
                    UIPasteboard.general.string = item.fullScriptText
                }) {
                    Image(systemName: "doc.on.doc")
                        .font(.subheadline.bold())
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 38)
                        .background(Color.white.opacity(0.08))
                        .cornerRadius(10)
                }
                
                // Delete single
                Button(action: {
                    HistoryManager.shared.deleteItem(id: item.id)
                    loadHistory()
                }) {
                    Image(systemName: "trash")
                        .font(.subheadline)
                        .foregroundStyle(.red.opacity(0.8))
                        .frame(width: 44, height: 38)
                        .background(Color.red.opacity(0.1))
                        .cornerRadius(10)
                }
            }
        }
        .padding(16)
        .background(Color.white.opacity(0.05))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
        .cornerRadius(16)
        .padding(.horizontal, 20)
    }
    
    private func formattedDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
