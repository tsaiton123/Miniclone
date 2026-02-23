import Foundation

enum CLIPTokenizerError: Error {
    case fileNotFound(String)
    case parsingError
}

class CLIPTokenizer {
    private var vocab: [String: Int] = [:]
    private var bpeRanks: [String: Int] = [:]
    private var cache: [String: String] = [:]

    let startToken = 49406
    let endToken = 49407
    let maxTokens = 77

    init() throws {
        try loadVocab()
        try loadMerges()
    }

    private func loadVocab() throws {
        guard let url = Bundle.main.url(forResource: "vocab", withExtension: "json") else {
            throw CLIPTokenizerError.fileNotFound("vocab.json")
        }
        let data = try Data(contentsOf: url)
        if let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Int] {
            self.vocab = json
        } else {
            throw CLIPTokenizerError.parsingError
        }
    }

    private func loadMerges() throws {
        guard let url = Bundle.main.url(forResource: "merges", withExtension: "txt") else {
            throw CLIPTokenizerError.fileNotFound("merges.txt")
        }
        let content = try String(contentsOf: url, encoding: .utf8)
        let lines = content.components(separatedBy: .newlines).filter { !$0.isEmpty }
        
        // Skip the first line which is often a header like "#version: 0.2"
        let bpeMerges = Array(lines.dropFirst())
        
        for (index, merge) in bpeMerges.enumerated() {
            // merge is "token1 token2"
            self.bpeRanks[merge] = index
        }
    }

    func encode(text: String) -> [Int32] {
        var tokens = [Int32(startToken)]
        
        let cleanedText = text.lowercased()
            .components(separatedBy: .whitespacesAndNewlines)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)
        
        let words = cleanedText.components(separatedBy: " ")
        
        for (i, word) in words.enumerated() {
            var tokenWord = word
            if i != 0 {
                // OpenAI CLIP puts "</w>" at the end of words instead of using spaces. 
                // A simplified approach for quick BPE without regex is wrapping words.
            }
            tokenWord += "</w>" // Standard CLIP BPE suffix for end of word
            
            let bpeTokens = bpe(word: tokenWord)
            for bpeToken in bpeTokens {
                if let id = vocab[bpeToken] {
                    tokens.append(Int32(id))
                }
            }
        }
        
        tokens.append(Int32(endToken))
        
        // Pad or truncate to maxTokens
        if tokens.count > maxTokens {
            tokens = Array(tokens.prefix(maxTokens))
            tokens[maxTokens - 1] = Int32(endToken)
        } else {
            while tokens.count < maxTokens {
                tokens.append(0) // padding token is often 0
            }
        }
        
        return tokens
    }
    
    // Very simplified BPE algorithm
    private func bpe(word: String) -> [String] {
        if let cached = cache[word] {
            return cached.components(separatedBy: " ")
        }
        
        var wordTokens = word.map { String($0) }
        
        // Re-join the last char with </w> since we appended it
        if wordTokens.count >= 4 && wordTokens.suffix(4).joined() == "</w>" {
            wordTokens = Array(wordTokens.dropLast(4))
            wordTokens.append(wordTokens.removeLast() + "</w>")
        } else if wordTokens.count >= 1 && word.hasSuffix("</w>") {
             if wordTokens.count > 4 {
                 wordTokens = Array(wordTokens.dropLast(4))
                 wordTokens.append(String(word.suffix(5)))
             } else {
                 wordTokens = [word]
             }
        }

        while wordTokens.count > 1 {
            var pairs: [String] = []
            for i in 0..<(wordTokens.count - 1) {
                pairs.append("\(wordTokens[i]) \(wordTokens[i+1])")
            }
            
            // Find the pair with the lowest rank
            var bigram: String? = nil
            var minRank = Int.max
            
            for pair in pairs {
                if let rank = bpeRanks[pair], rank < minRank {
                    minRank = rank
                    bigram = pair
                }
            }
            
            if bigram == nil {
                break
            }
            
            let parts = bigram!.components(separatedBy: " ")
            let first = parts[0]
            let second = parts[1]
            
            var newTokens: [String] = []
            var i = 0
            while i < wordTokens.count {
                if i < wordTokens.count - 1 && wordTokens[i] == first && wordTokens[i+1] == second {
                    newTokens.append(first + second)
                    i += 2
                } else {
                    newTokens.append(wordTokens[i])
                    i += 1
                }
            }
            wordTokens = newTokens
        }
        
        let result = wordTokens.joined(separator: " ")
        cache[word] = result
        return wordTokens
    }
}
