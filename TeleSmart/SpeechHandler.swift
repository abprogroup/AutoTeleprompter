//SpeechHandler.swift:
//Explanation:
//Properties:
//
//speechRecognizer: An instance of SFSpeechRecognizer configured for the "en-US" locale.
//recognitionRequest: Handles the audio input and sends it to the speech recognizer.
//recognitionTask: Manages the recognition process and delivers the results.
//audioEngine: Captures the audio input from the microphone.
//isRecognizing: A boolean to track if recognition is currently active.
//onSpeechRecognition: A callback that is triggered when speech is successfully recognized.
//startRecognition():
//
//Starts the audio engine and initializes the speech recognition process. It also ensures that if the audio engine is already running, it doesn't restart it.
//stopRecognition():
//
//Stops the audio engine and ends the current recognition task.
//startAudioEngine():
//
//Configures the audio session and prepares the audio engine for capturing voice input.
//Installs a tap on the audio engine's input node to receive audio buffers and sends these buffers to the recognition request.
//Starts the audio engine to begin capturing audio.
//speechRecognizer(_:availabilityDidChange:):
//
//A delegate method that handles changes in the availability of the speech recognizer. It stops recognition if the recognizer becomes unavailable.
//Key Features:
//Real-Time Transcription: The recognition task is set to report partial results, enabling near-instant feedback on recognized speech.
//Error Handling: The method handles errors gracefully by stopping the recognition process and deactivating the audio engine when necessary.
//Optimization for Swift Performance: The file is designed for optimal performance, with the audio engine and recognition task only running when needed.

import Foundation
import Speech

class SpeechHandler: NSObject, SFSpeechRecognizerDelegate {
    
    // MARK: - Properties
    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))!
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()
    
    var isRecognizing = false
    var onSpeechRecognition: ((String) -> Void)?
    
    override init() {
        super.init()
        speechRecognizer.delegate = self
    }
    
    // MARK: - Start Recognition
    func startRecognition() {
        guard !audioEngine.isRunning else { return }
        
        do {
            try startAudioEngine()
            isRecognizing = true
        } catch {
            print("Error starting the audio engine: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Stop Recognition
    func stopRecognition() {
        audioEngine.stop()
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        isRecognizing = false
    }
    
    // MARK: - Audio Engine Setup
    private func startAudioEngine() throws {
        // Cancel the previous task if it's running
        if recognitionTask != nil {
            recognitionTask?.cancel()
            recognitionTask = nil
        }
        
        // Setup the audio session for recording
        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
        try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest = recognitionRequest else { return }
        
        let inputNode = audioEngine.inputNode
        recognitionRequest.shouldReportPartialResults = true
        
        recognitionTask = speechRecognizer.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            guard let strongSelf = self else { return }
            
            if let result = result {
                // Send the transcribed text to the callback
                strongSelf.onSpeechRecognition?(result.bestTranscription.formattedString)
            }
            
            if error != nil || result?.isFinal == true {
                // Stop recognition if there's an error or the result is final
                strongSelf.stopRecognition()
            }
        }
        
        // Install tap on the audio engine's input node to receive audio samples
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, when in
            recognitionRequest.append(buffer)
        }
        
        // Start the audio engine
        audioEngine.prepare()
        try audioEngine.start()
    }
    
    // MARK: - SFSpeechRecognizerDelegate Methods
    func speechRecognizer(_ speechRecognizer: SFSpeechRecognizer, availabilityDidChange available: Bool) {
        if !available {
            stopRecognition()
            print("Speech recognition is not available.")
        }
    }
}
