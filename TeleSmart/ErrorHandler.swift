//ErrorHandler.swift:
//Explanation:
//logError(_:, message:):
//
//Logs errors to the console and optionally displays an alert to the user.
//This method provides a standardized way to log errors across the entire application. Custom messages can be appended to give more context.
//logMessage(_:):
//
//Used to log informational messages that are not errors but might be useful for debugging or tracking the application's state.
//displayAlert(message:):
//
//A helper method that identifies the topmost view controller in the application and presents an alert dialog with the error message.
//This method ensures that users are informed of critical issues in a user-friendly manner.
//showAlert(on:, with:):
//
//This method presents the actual alert dialog on the identified view controller.
//It ensures that UI updates occur on the main thread, preventing any potential threading issues.
//handleSpeechRecognitionError(_:):
//
//A specific method for handling errors related to speech recognition. It logs the error and informs the user that speech recognition encountered an issue.
//handleNLProcessingError(_:):
//
//Handles errors related to natural language processing, providing specific feedback to the user that there was an issue with processing the recognized text.
//handleScrollError(_:):
//
//Manages errors related to the text scrolling functionality, ensuring that any issues in this area are logged and addressed.
//Key Features:
//Centralized Error Handling: All error handling is centralized, making it easier to maintain and update as the application evolves.
//User-Friendly Alerts: The application provides clear, actionable alerts to the user when errors occur, enhancing the user experience even in adverse conditions.
//Extensibility: The error handling framework is designed to be easily extended. New error types and custom handling can be added without disrupting the existing structure.
//Application Flow:
//With the ErrorHandler.swift in place, all critical functions of your iPad teleprompter application are now equipped to handle and log errors, ensuring robustness and reliability. This file is designed to work seamlessly with the other components—ViewController, SpeechHandler, NLPHandler, and TextScroller—to create a well-rounded and professional application.

import Foundation
import UIKit

class ErrorHandler {
    
    // MARK: - Log Error
    static func logError(_ error: Error, message: String? = nil) {
        // Prepare the error message
        var errorMessage = "Error: \(error.localizedDescription)"
        if let customMessage = message {
            errorMessage += "\n\(customMessage)"
        }
        
        // Log the error to the console (can be expanded to log to a file or remote server)
        print(errorMessage)
        
        // Optionally, display an alert to the user
        displayAlert(message: errorMessage)
    }
    
    // MARK: - Log Custom Message
    static func logMessage(_ message: String) {
        // Log custom informational messages to the console
        print("Info: \(message)")
    }
    
    // MARK: - Display Alert to User
    static private func displayAlert(message: String) {
        // Get the topmost view controller to present the alert
        if let topViewController = UIApplication.shared.keyWindow?.rootViewController {
            showAlert(on: topViewController, with: message)
        }
    }
    
    static private func showAlert(on viewController: UIViewController, with message: String) {
        // Create an alert controller
        let alertController = UIAlertController(title: "An Error Occurred", message: message, preferredStyle: .alert)
        alertController.addAction(UIAlertAction(title: "OK", style: .default, handler: nil))
        
        // Present the alert
        DispatchQueue.main.async {
            viewController.present(alertController, animated: true, completion: nil)
        }
    }
    
    // MARK: - Handle Specific Error Types
    static func handleSpeechRecognitionError(_ error: Error) {
        logError(error, message: "Speech recognition encountered an issue. Please try again.")
    }
    
    static func handleNLProcessingError(_ error: Error) {
        logError(error, message: "There was an issue processing the natural language input.")
    }
    
    static func handleScrollError(_ error: Error) {
        logError(error, message: "There was an issue with scrolling the text. Please check the input and try again.")
    }
}
