import SwiftUI
import LaTeXSwiftUI


struct ChatView: View {
    @StateObject private var geminiService = GeminiService()
    @StateObject private var quotaManager = AIQuotaManager.shared
    @State private var messageText = ""
    @State private var messages: [ChatMessage] = []
    @State private var isLoading = false
    
    @Binding var contextToProcess: String?
    
    var onPlotFunction: (GeminiService.GraphCommand) -> Void
    
    struct ChatMessage: Identifiable {
        let id = UUID()
        let text: String
        let isUser: Bool
        let timestamp = Date()
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header with quota status
            HStack {
                Text("Cognote")
                    .font(.headline)
                Spacer()
                // Quota indicator
                HStack(spacing: 4) {
                    Image(systemName: quotaManager.canMakeRequest ? "sparkles" : "exclamationmark.triangle.fill")
                        .foregroundColor(quotaManager.canMakeRequest ? .blue : .orange)
                    Text("\(quotaManager.remainingQuota)/\(AIQuotaManager.dailyLimit)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding()
            .background(Color(UIColor.secondarySystemBackground))
            
            // Messages
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(messages) { message in
                            MessageBubble(message: message)
                        }
                        
                        if isLoading {
                            HStack {
                                ProgressView()
                                    .padding(8)
                                    .background(Color(UIColor.secondarySystemBackground))
                                    .cornerRadius(12)
                                Spacer()
                            }
                            .padding(.horizontal)
                        }
                    }
                    .padding()
                }
                .onChange(of: messages.count) { _ in
                    if let lastId = messages.last?.id {
                        withAnimation {
                            proxy.scrollTo(lastId, anchor: .bottom)
                        }
                    }
                }
            }
            
            // Input Area
            HStack(alignment: .bottom) {
                TextField("Ask anything...", text: $messageText, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1...5)
                
                Button(action: { sendMessage() }) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 30))
                        .foregroundColor(quotaManager.canMakeRequest ? .blue : .gray)
                }
                .disabled(messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isLoading || !quotaManager.canMakeRequest)
            }
            .padding()
            .background(Color(UIColor.secondarySystemBackground))
        }
        .background(Color(UIColor.systemBackground))
        .cornerRadius(16)
        .shadow(radius: 10)
        .frame(width: 350, height: 500)
        .onChange(of: contextToProcess) { context in
            if let context = context {
                sendMessage(context: context)
                contextToProcess = nil
            }
        }
    }
    
    private func sendMessage(context: String? = nil) {
        let text: String
        let isContextMessage: Bool
        
        if let context = context {
            text = context
            isContextMessage = true
        } else {
            text = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
            isContextMessage = false
        }
        
        guard !text.isEmpty else { return }
        
        // Check AI quota before proceeding
        guard quotaManager.checkAndRecordUsage() else {
            messages.append(ChatMessage(text: "Daily AI limit reached (\(AIQuotaManager.dailyLimit) requests). Your quota resets at midnight.", isUser: false))
            return
        }
        
        if !isContextMessage {
            let userMessage = ChatMessage(text: text, isUser: true)
            messages.append(userMessage)
            messageText = ""
        } else {
            // For context messages, maybe show a system message or a summarized user message?
            // Let's show it as a user message for now, but maybe truncated?
            // Or just "Sent selection context"
            let userMessage = ChatMessage(text: "Analyzing selection...", isUser: true)
            messages.append(userMessage)
        }
        
        isLoading = true
        
        Task {
            do {
                let response: String
                if isContextMessage {
                    response = try await geminiService.sendSelectionContext(text, mode: .explain)
                } else {
                    response = try await geminiService.sendMessage(text)
                }
                
                let (cleanText, graphCommand) = geminiService.parseResponse(response)
                
                await MainActor.run {
                    if !cleanText.isEmpty {
                        let aiMessage = ChatMessage(text: cleanText, isUser: false)
                        messages.append(aiMessage)
                    }
                    
                    if let command = graphCommand {
                        onPlotFunction(command)
                        // Optionally add a system message saying graph was plotted
                        messages.append(ChatMessage(text: "Plotting \(command.expression)...", isUser: false))
                    }
                    
                    isLoading = false
                }
            } catch {
                await MainActor.run {
                    messages.append(ChatMessage(text: "Error: \(error.localizedDescription)", isUser: false))
                    isLoading = false
                }
            }
        }
    }
}

struct MessageBubble: View {
    let message: ChatView.ChatMessage
    
    var body: some View {
        HStack {
            if message.isUser {
                Spacer()
                Text(message.text)
                    .padding(10)
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(12)
                    .font(.custom("Caveat-Regular", size: 20)) // Use handwriting font for user too? Or maybe just AI.
            } else {
                LaTeX(message.text)
                    .padding(10)
                    .background(Color(UIColor.secondarySystemBackground))
                    .foregroundColor(.primary)
                    .cornerRadius(12)
                    .font(.custom("Caveat-Regular", size: 22)) // Handwriting for AI
                Spacer()
            }
        }
    }
}
