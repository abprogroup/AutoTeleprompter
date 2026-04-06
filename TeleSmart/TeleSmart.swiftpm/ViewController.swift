//ViewController.swift:
//Explanation:
//Properties:
//
//speechHandler: Manages speech recognition.
//textScroller: Handles the scrolling of text on the teleprompter.
//nlpHandler: Processes the recognized speech to determine the next actions.
//teleprompterTextView: The UITextView where the text is displayed and scrolled.
//startButton: A UIButton that toggles speech recognition on and off.
//viewDidLoad():
//
//Initializes the handlers and UI elements when the view loads.
//setupHandlers():
//
//Instantiates the speech handler, text scroller, and NLP handler.
//Sets a callback for when speech is recognized, triggering further processing.
//setupUI():
//
//Configures the appearance and initial state of the UI elements, like setting the start button’s title and color.
//startButtonTapped():
//
//This function is triggered when the start button is tapped. It either starts or stops the speech recognition based on its current state.
//handleRecognizedText(_:):
//
//This function processes the recognized text through NLP and updates the teleprompter with the appropriate text using the text scroller.

//ViewController.swift:
//Explanation:
//Properties:
//
//speechHandler: Manages speech recognition.
//textScroller: Handles the scrolling of text on the teleprompter.
//nlpHandler: Processes the recognized speech to determine the next actions.
//teleprompterTextView: The UITextView where the text is displayed and scrolled.
//startButton: A UIButton that toggles speech recognition on and off.
//viewDidLoad():
//
//Initializes the handlers and UI elements when the view loads.
//setupHandlers():
//
//Instantiates the speech handler, text scroller, and NLP handler.
//Sets a callback for when speech is recognized, triggering further processing.
//setupUI():
//
//Configures the appearance and initial state of the UI elements, like setting the start button’s title and color.
//startButtonTapped():
//
//This function is triggered when the start button is tapped. It either starts or stops the speech recognition based on its current state.
//handleRecognizedText(_:):
//
//This function processes the recognized text through NLP and updates the teleprompter with the appropriate text using the text scroller.

import UIKit
import Speech

class ViewController: UIViewController {

    // MARK: - Properties
    var speechHandler: SpeechHandler?
    var textScroller: TextScroller?
    var nlpHandler: NLPHandler?
    
    // TextView for displaying the teleprompter text
    @IBOutlet weak var teleprompterTextView: UITextView!

    // Button to start/stop voice recognition
    @IBOutlet weak var startButton: UIButton!

    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Initial Setup
        setupHandlers()
        setupUI()
    }

    // MARK: - Setup Functions
    private func setupHandlers() {
        // Initialize the handlers
        speechHandler = SpeechHandler()
        nlpHandler = NLPHandler()
        textScroller = TextScroller(teleprompterTextView: teleprompterTextView)
        
        // Set the callback for when speech recognition is successful
        speechHandler?.onSpeechRecognition = { [weak self] recognizedText in
            guard let strongSelf = self else { return }
            strongSelf.handleRecognizedText(recognizedText)
        }
    }

    private func setupUI() {
        // Customize UI Elements
        teleprompterTextView.text = ""
        startButton.setTitle("Start", for: .normal)
        startButton.layer.cornerRadius = 10
        startButton.backgroundColor = .systemBlue
        startButton.tintColor = .white
    }

    // MARK: - Button Actions
    @IBAction func startButtonTapped(_ sender: UIButton) {
        if speechHandler?.isRecognizing == true {
            // Stop Speech Recognition
            speechHandler?.stopRecognition()
            startButton.setTitle("Start", for: .normal)
        } else {
            // Start Speech Recognition
            speechHandler?.startRecognition()
            startButton.setTitle("Stop", for: .normal)
        }
    }

    // MARK: - Handling Recognized Text
    private func handleRecognizedText(_ text: String) {
        // Process the recognized text using NLPHandler
        let processedText = nlpHandler?.process(text: text)
        
        // Update the teleprompter view using TextScroller
        textScroller?.scrollText(processedText ?? "")
    }
}
