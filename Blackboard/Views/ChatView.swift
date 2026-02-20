import SwiftUI
import LaTeXSwiftUI


struct ChatView: View {
    @StateObject private var geminiService = GeminiService()
    @StateObject private var quotaManager = AIQuotaManager.shared
    @State private var messageText = ""
    @State private var messages: [ChatMessage] = []
    @State private var isLoading = false
    @State private var streamingMessageId: UUID? = nil
    
    @Binding var contextToProcess: String?
    
    var onPlotFunction: (GeminiService.GraphCommand) -> Void
    var onDismiss: () -> Void
    @Environment(\.appTheme) private var appTheme
    
    struct ChatMessage: Identifiable {
        let id = UUID()
        var text: String
        let isUser: Bool
        var isStreaming: Bool = false
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
                        .foregroundColor(quotaManager.canMakeRequest ? appTheme.accentColor : .orange)
                    Text("\(quotaManager.remainingQuota)/\(AIQuotaManager.dailyLimit)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Button(action: onDismiss) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 20))
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
                        
                        if isLoading && streamingMessageId == nil {
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
                    scrollToBottom(proxy: proxy)
                }
                .onChange(of: messages.last?.text) { _ in
                    scrollToBottom(proxy: proxy)
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
                        .foregroundColor(quotaManager.canMakeRequest ? appTheme.accentColor : .gray)
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
    
    private func scrollToBottom(proxy: ScrollViewProxy) {
        if let lastId = messages.last?.id {
            withAnimation {
                proxy.scrollTo(lastId, anchor: .bottom)
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
        guard quotaManager.hasQuota(cost: 2) else {
            messages.append(ChatMessage(text: "Daily AI limit reached (\(AIQuotaManager.dailyLimit) requests). Your quota resets at midnight.", isUser: false))
            return
        }
        
        if !isContextMessage {
            let userMessage = ChatMessage(text: text, isUser: true)
            messages.append(userMessage)
            messageText = ""
        } else {
            let userMessage = ChatMessage(text: "Analyzing selection...", isUser: true)
            messages.append(userMessage)
        }
        
        isLoading = true
        
        // Create an empty AI message for streaming
        var aiMessage = ChatMessage(text: "", isUser: false, isStreaming: true)
        let aiMessageId = aiMessage.id
        messages.append(aiMessage)
        streamingMessageId = aiMessageId
        
        Task {
            do {
                let fullResponse: String
                
                if isContextMessage {
                    fullResponse = try await geminiService.streamSelectionContext(text, mode: .explain) { chunk in
                        // Append chunk to the streaming message
                        if let index = messages.firstIndex(where: { $0.id == aiMessageId }) {
                            messages[index].text += chunk
                        }
                    }
                } else {
                    fullResponse = try await geminiService.streamMessage(text) { chunk in
                        if let index = messages.firstIndex(where: { $0.id == aiMessageId }) {
                            messages[index].text += chunk
                        }
                    }
                }
                
                // Stream complete — finalize the message
                let (cleanText, graphCommand) = geminiService.parseResponse(fullResponse)
                
                await MainActor.run {
                    // Update with parsed text (removes JSON blocks if any)
                    if let index = messages.firstIndex(where: { $0.id == aiMessageId }) {
                        messages[index].text = cleanText
                        messages[index].isStreaming = false
                    }
                    
                    if let command = graphCommand {
                        onPlotFunction(command)
                        messages.append(ChatMessage(text: "Plotting \(command.expression)...", isUser: false))
                    }
                    
                    quotaManager.recordUsage(cost: 2)
                    
                    streamingMessageId = nil
                    isLoading = false
                }
            } catch {
                await MainActor.run {
                    // Show error in the streaming message
                    if let index = messages.firstIndex(where: { $0.id == aiMessageId }) {
                        messages[index].text = "Error: \(error.localizedDescription)"
                        messages[index].isStreaming = false
                    }
                    streamingMessageId = nil
                    isLoading = false
                }
            }
        }
    }
}

struct MessageBubble: View {
    let message: ChatView.ChatMessage
    @Environment(\.appTheme) private var appTheme
    
    var body: some View {
        HStack {
            if message.isUser {
                Spacer()
                Text(message.text)
                    .padding(10)
                    .background(appTheme.accentColor)
                    .foregroundColor(.white)
                    .cornerRadius(12)
                    .font(.custom("Caveat-Regular", size: 20))
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    if message.isStreaming {
                        // During streaming, show raw text (avoids partial LaTeX parse flicker)
                        Text(message.text)
                            .font(.custom("Caveat-Regular", size: 22))
                    } else {
                        // After streaming completes, render with LaTeX
                        LaTeX(message.text)
                            .font(.custom("Caveat-Regular", size: 22))
                    }
                    
                    if message.isStreaming {
                        // Blinking cursor indicator
                        Text("▊")
                            .font(.system(size: 14))
                            .foregroundColor(appTheme.accentColor)
                            .opacity(0.8)
                    }
                }
                .padding(10)
                .background(Color(UIColor.secondarySystemBackground))
                .foregroundColor(.primary)
                .cornerRadius(12)
                Spacer()
            }
        }
    }
}
