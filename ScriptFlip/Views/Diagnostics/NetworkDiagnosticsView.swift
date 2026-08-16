import SwiftUI

/// Diagnostic sheet displaying live Supabase Edge Function connectivity and request/response payloads.
public struct NetworkDiagnosticsView: View {
    @Environment(\.dismiss) private var dismiss
    let diagnostics: NetworkDiagnosticInfo
    let onRunTest: () -> Void
    
    @State private var isCopied: Bool = false
    
    public init(diagnostics: NetworkDiagnosticInfo, onRunTest: @escaping () -> Void = {}) {
        self.diagnostics = diagnostics
        self.onRunTest = onRunTest
    }
    
    public var body: some View {
        NavigationStack {
            ZStack {
                Color(red: 0.05, green: 0.05, blue: 0.07).ignoresSafeArea()
                
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        // Overview Header Card
                        headerCard
                        
                        // Configuration Section
                        configurationSection
                        
                        // Last Request Section
                        lastRequestSection
                        
                        // Last Response Section
                        lastResponseSection
                        
                        // Action Buttons
                        actionButtons
                    }
                    .padding(20)
                }
            }
            .navigationTitle("Network Diagnostics")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.gray)
                    }
                }
            }
        }
    }
    
    // MARK: - Subviews
    
    private var headerCard: some View {
        HStack(spacing: 14) {
            Image(systemName: diagnostics.hasValidAnonKey ? "network" : "exclamationmark.triangle.fill")
                .font(.system(size: 32))
                .foregroundStyle(diagnostics.hasValidAnonKey ? .cyan : .yellow)
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Supabase Edge Function")
                    .font(.headline.bold())
                    .foregroundStyle(.white)
                Text(diagnostics.lastResponseStatusCode != nil ? "Last Status: HTTP \(diagnostics.lastResponseStatusCode!)" : "Status: Ready")
                    .font(.subheadline)
                    .foregroundStyle(diagnostics.lastResponseStatusCode == 200 ? .green : (diagnostics.lastResponseStatusCode != nil ? .red : .gray))
            }
            Spacer()
        }
        .padding(16)
        .background(Color.white.opacity(0.06))
        .cornerRadius(14)
    }
    
    private var configurationSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("CONFIGURATION")
                .font(.caption.bold())
                .foregroundStyle(.gray)
            
            VStack(alignment: .leading, spacing: 12) {
                diagnosticRow(title: "Target URL", value: diagnostics.endpointURL, isMonospace: true)
                diagnosticRow(title: "Anon Key Status", value: diagnostics.anonKeyStatus, isMonospace: false)
                diagnosticRow(title: "Anon Key Valid", value: diagnostics.hasValidAnonKey ? "YES (JWT Format)" : "NO (Missing/Invalid)", isMonospace: false, isSuccess: diagnostics.hasValidAnonKey)
            }
            .padding(16)
            .background(Color.white.opacity(0.04))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            )
        }
    }
    
    private var lastRequestSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("LAST HTTP REQUEST")
                .font(.caption.bold())
                .foregroundStyle(.gray)
            
            VStack(alignment: .leading, spacing: 10) {
                if let timestamp = diagnostics.lastRequestTimestamp {
                    diagnosticRow(title: "Timestamp", value: timestamp.formatted(date: .abbreviated, time: .standard), isMonospace: false)
                }
                diagnosticRow(title: "Method", value: diagnostics.lastRequestMethod ?? "POST", isMonospace: true)
                
                if let body = diagnostics.lastRequestBody, !body.isEmpty {
                    Text("Request Body:")
                        .font(.caption.bold())
                        .foregroundStyle(.gray)
                    Text(body)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.8))
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.black.opacity(0.4))
                        .cornerRadius(8)
                } else {
                    Text("No request sent yet.")
                        .font(.caption)
                        .foregroundStyle(.gray)
                }
            }
            .padding(16)
            .background(Color.white.opacity(0.04))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            )
        }
    }
    
    private var lastResponseSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("LAST HTTP RESPONSE")
                .font(.caption.bold())
                .foregroundStyle(.gray)
            
            VStack(alignment: .leading, spacing: 10) {
                if let status = diagnostics.lastResponseStatusCode {
                    diagnosticRow(title: "HTTP Status", value: "\(status)", isMonospace: true, isSuccess: (200...299).contains(status))
                }
                if let duration = diagnostics.lastDurationMs {
                    diagnosticRow(title: "Latency", value: String(format: "%.1f ms", duration), isMonospace: true)
                }
                if let error = diagnostics.lastErrorMessage {
                    Text("Error Message:")
                        .font(.caption.bold())
                        .foregroundStyle(.red)
                    Text(error)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.red.opacity(0.9))
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.red.opacity(0.1))
                        .cornerRadius(8)
                }
                if let body = diagnostics.lastResponseBody, !body.isEmpty {
                    Text("Response Body:")
                        .font(.caption.bold())
                        .foregroundStyle(.gray)
                    Text(body)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.8))
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.black.opacity(0.4))
                        .cornerRadius(8)
                } else if diagnostics.lastErrorMessage == nil {
                    Text("No response received yet.")
                        .font(.caption)
                        .foregroundStyle(.gray)
                }
            }
            .padding(16)
            .background(Color.white.opacity(0.04))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            )
        }
    }
    
    private var actionButtons: some View {
        VStack(spacing: 12) {
            Button(action: {
                copyFullDiagnostics()
            }) {
                HStack(spacing: 8) {
                    Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                    Text(isCopied ? "Diagnostics Copied!" : "Copy Full Diagnostics Payload")
                }
                .font(.subheadline.bold())
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .background(Color.white.opacity(0.12))
                .cornerRadius(12)
            }
            
            Button(action: {
                dismiss()
                onRunTest()
            }) {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.clockwise")
                    Text("Trigger Test Generation")
                }
                .font(.subheadline.bold())
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .background(
                    LinearGradient(
                        colors: [.cyan, .mint],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .cornerRadius(12)
            }
        }
    }
    
    private func diagnosticRow(title: String, value: String, isMonospace: Bool, isSuccess: Bool? = nil) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption2.bold())
                .foregroundStyle(.gray)
            
            Text(value)
                .font(isMonospace ? .system(.caption, design: .monospaced) : .caption)
                .foregroundStyle(
                    isSuccess == true ? Color.green : (isSuccess == false ? Color.red : Color.white)
                )
        }
    }
    
    private func copyFullDiagnostics() {
        let dump = """
        === SCRIPTFLIP NETWORK DIAGNOSTICS ===
        Endpoint URL: \(diagnostics.endpointURL)
        Anon Key Status: \(diagnostics.anonKeyStatus)
        Anon Key Valid: \(diagnostics.hasValidAnonKey)
        Last Timestamp: \(diagnostics.lastRequestTimestamp?.description ?? "None")
        Last Method: \(diagnostics.lastRequestMethod ?? "None")
        Last Status Code: \(diagnostics.lastResponseStatusCode?.description ?? "None")
        Last Duration: \(diagnostics.lastDurationMs != nil ? "\(diagnostics.lastDurationMs!) ms" : "None")
        Last Error: \(diagnostics.lastErrorMessage ?? "None")
        
        --- REQUEST BODY ---
        \(diagnostics.lastRequestBody ?? "None")
        
        --- RESPONSE BODY ---
        \(diagnostics.lastResponseBody ?? "None")
        =======================================
        """
        
        UIPasteboard.general.string = dump
        isCopied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            isCopied = false
        }
    }
}
