//NLPHandler.swift:
//Explanation:
//Properties:
//
//tagger: An instance of NLTagger used for natural language processing tasks such as tagging and analyzing the text.
//options: Defines how the NLTagger should process the text, omitting punctuation and whitespace, and joining names.
//process(text:):
//
//This is the primary method that processes the transcribed text.
//It sets the text for the NLTagger, detects the language, analyzes sentiment, extracts named entities, and generates a response based on these analyses.
//detectLanguage(text:):
//
//Uses NLLanguageRecognizer to determine the dominant language of the text.
//analyzeSentiment(text:):
//
//Analyzes the sentiment of the text using the NLTagger and returns a sentiment score. The score helps determine whether the sentiment is positive, neutral, or negative.
//extractNamedEntities(text:):
//
//Extracts named entities such as personal names, organization names, and place names from the text. This can be useful for customizing the response or actions based on key entities mentioned in the speech.
//generateResponse(language:sentiment:entities:):
//
//Generates a response based on the detected language, sentiment, and named entities. This function is customizable depending on the specific needs of the application.
//Key Features:
//Multi-Language Support: The detectLanguage method allows the application to adapt to different languages, though it defaults to English for processing.
//Sentiment-Aware: By analyzing sentiment, the app can adjust its behavior or the text it displays based on the emotional tone of the user's speech.
//Entity Recognition: Extracts significant names and places, which could be used to make the teleprompter content more personalized or context-aware.

import Foundation
import NaturalLanguage

class NLPHandler {
    
    // MARK: - Properties
    private let tagger: NLTagger
    private let options: NLTagger.Options
    
    init() {
        // Initialize the NLTagger for processing text
        tagger = NLTagger(tagSchemes: [.nameType, .lemma, .language, .sentimentScore])
        options = [.omitPunctuation, .omitWhitespace, .joinNames]
    }
    
    // MARK: - Text Processing Function
    func process(text: String) -> String {
        // Set the text to the tagger
        tagger.string = text
        
        // Determine language and sentiment
        let language = detectLanguage(text: text)
        let sentiment = analyzeSentiment(text: text)
        
        // Process named entities
        let namedEntities = extractNamedEntities(text: text)
        
        // Generate processed output
        let processedText = generateResponse(language: language, sentiment: sentiment, entities: namedEntities)
        
        return processedText
    }
    
    // MARK: - Language Detection
    private func detectLanguage(text: String) -> String {
        let languageRecognizer = NLLanguageRecognizer()
        languageRecognizer.processString(text)
        if let language = languageRecognizer.dominantLanguage?.rawValue {
            return language
        }
        return "unknown"
    }
    
    // MARK: - Sentiment Analysis
    private func analyzeSentiment(text: String) -> Double {
        tagger.setLanguage(.english, range: text.startIndex..<text.endIndex)
        let sentimentScore = tagger.tag(at: text.startIndex, unit: .paragraph, scheme: .sentimentScore).0
        return Double(sentimentScore ?? "0.0") ?? 0.0
    }
    
    // MARK: - Named Entity Recognition
    private func extractNamedEntities(text: String) -> [String] {
        var entities = [String]()
        tagger.enumerateTags(in: text.startIndex..<text.endIndex, unit: .word, scheme: .nameType, options: options) { tag, tokenRange in
            if let tag = tag, tag == .personalName || tag == .organizationName || tag == .placeName {
                let entity = String(text[tokenRange])
                entities.append(entity)
            }
            return true
        }
        return entities
    }
    
    // MARK: - Generate Response
    private func generateResponse(language: String, sentiment: Double, entities: [String]) -> String {
        // Basic example: Customize this based on the app's needs
        var response = "Detected language: \(language)\n"
        response += "Sentiment score: \(sentiment)\n"
        response += "Named Entities: \(entities.joined(separator: ", "))\n"
        
        // Example logic: Adjust teleprompter text based on sentiment
        if sentiment < 0 {
            response += "Detected negative sentiment. Adjusting content...\n"
        } else {
            response += "Positive or neutral sentiment detected.\n"
        }
        
        return response
    }
}
