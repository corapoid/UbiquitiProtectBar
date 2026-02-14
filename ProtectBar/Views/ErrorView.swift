import SwiftUI

/// A view component for displaying user-friendly error messages with recovery suggestions
struct ErrorView: View {
    let error: Error
    let onRetry: (() -> Void)?
    let onDismiss: (() -> Void)?
    
    init(error: Error, onRetry: (() -> Void)? = nil, onDismiss: (() -> Void)? = nil) {
        self.error = error
        self.onRetry = onRetry
        self.onDismiss = onDismiss
    }
    
    private var apiError: APIError? {
        error as? APIError
    }
    
    private var iconName: String {
        apiError?.iconName ?? "exclamationmark.triangle"
    }
    
    private var isRetryable: Bool {
        apiError?.isRetryable ?? false
    }
    
    private var recoverySuggestion: String? {
        apiError?.recoverySuggestion
    }
    
    var body: some View {
        VStack(spacing: 12) {
            // Error Icon
            Image(systemName: iconName)
                .font(.system(size: 32))
                .foregroundColor(.red)
            
            // Error Message
            Text(error.localizedDescription)
                .font(.headline)
                .multilineTextAlignment(.center)
                .foregroundColor(.primary)
            
            // Recovery Suggestion
            if let suggestion = recoverySuggestion {
                Text(suggestion)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 8)
            }
            
            // Action Buttons
            HStack(spacing: 12) {
                if let onDismiss {
                    Button("Dismiss") {
                        onDismiss()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                
                if isRetryable, let onRetry {
                    Button("Retry") {
                        onRetry()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity)
    }
}

/// Compact inline error message for use in forms
struct InlineErrorView: View {
    let message: String
    let suggestion: String?
    
    init(_ message: String, suggestion: String? = nil) {
        self.message = message
        self.suggestion = suggestion
    }
    
    init(error: Error) {
        self.message = error.localizedDescription
        self.suggestion = (error as? APIError)?.recoverySuggestion
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.circle.fill")
                    .foregroundColor(.red)
                    .font(.caption)
                
                Text(message)
                    .font(.caption)
                    .foregroundColor(.red)
            }
            
            if let suggestion {
                Text(suggestion)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .padding(.leading, 20)
            }
        }
    }
}

/// Toast-style notification for transient errors
struct ErrorToast: View {
    let message: String
    let isShowing: Binding<Bool>
    
    var body: some View {
        if isShowing.wrappedValue {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
                
                Text(message)
                    .font(.caption)
                    .foregroundColor(.primary)
                
                Spacer()
                
                Button(action: { isShowing.wrappedValue = false }, label: {
                    Image(systemName: "xmark")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                })
                .buttonStyle(.plain)
            }
            .padding(12)
            .background(Color(.windowBackgroundColor))
            .cornerRadius(8)
            .shadow(radius: 4)
            .transition(.move(edge: .top).combined(with: .opacity))
            .onAppear {
                // Auto-dismiss after 5 seconds
                DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                    withAnimation {
                        isShowing.wrappedValue = false
                    }
                }
            }
        }
    }
}

// MARK: - Preview

#if DEBUG
struct ErrorView_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 20) {
            ErrorView(
                error: APIError.unauthorized,
                onRetry: {},
                onDismiss: {}
            )
            
            Divider()
            
            InlineErrorView(error: APIError.forbidden)
            
            Divider()
            
            ErrorToast(
                message: "Connection lost",
                isShowing: .constant(true)
            )
        }
        .padding()
        .frame(width: 300)
    }
}
#endif
