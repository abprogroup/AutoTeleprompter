//TextScroller.swift:
//Explanation:
//Properties:
//
//teleprompterTextView: A weak reference to the UITextView that displays the teleprompter text.
//scrollSpeed: Controls how fast the text scrolls. The lower the value, the faster the scroll.
//scrollTimer: A Timer that controls the interval at which the text scrolls.
//currentScrollOffset: Tracks the current position of the scroll in the text view.
//init(teleprompterTextView:):
//
//Initializes the TextScroller with a reference to the UITextView that will display the text.
//startScrolling():
//
//Begins the scrolling process by setting up a timer that triggers the scrollText method at regular intervals based on the scrollSpeed.
//stopScrolling():
//
//Stops the scrolling by invalidating the timer and resetting the scrollTimer to nil.
//updateText(_:):
//
//Updates the text displayed in the UITextView and resets the scroll position to the top of the text.
//scrollText():
//
//This method is called repeatedly by the timer to gradually scroll the text. It calculates the new scroll offset and adjusts the UITextView's content offset accordingly.
//If the text has scrolled to the end, it stops the scrolling.
//resetScrollOffset():
//
//Resets the scroll position to the beginning of the text, ensuring that the text starts scrolling from the top.
//adjustScrollSpeed(to:):
//
//Adjusts the speed of the scrolling. If scrolling is currently active, it stops and restarts the timer with the new speed.
//Key Features:
//Customizable Scroll Speed: Allows dynamic adjustment of the scroll speed, providing flexibility depending on user preferences or application needs.
//Smooth Scrolling: The text scrolls smoothly in a continuous manner, mimicking the behavior of a teleprompter.
//Automatic Stop: The scrolling automatically stops when it reaches the end of the text, preventing unnecessary processing.

import UIKit

class TextScroller {
    
    // MARK: - Properties
    private weak var teleprompterTextView: UITextView?
    private var scrollSpeed: Double = 0.05
    private var scrollTimer: Timer?
    private var currentScrollOffset: CGFloat = 0
    
    init(teleprompterTextView: UITextView) {
        self.teleprompterTextView = teleprompterTextView
    }
    
    // MARK: - Start Scrolling
    func startScrolling() {
        guard scrollTimer == nil else { return } // Prevent multiple timers
        
        scrollTimer = Timer.scheduledTimer(timeInterval: scrollSpeed, target: self, selector: #selector(scrollText), userInfo: nil, repeats: true)
    }
    
    // MARK: - Stop Scrolling
    func stopScrolling() {
        scrollTimer?.invalidate()
        scrollTimer = nil
    }
    
    // MARK: - Update Text
    func updateText(_ text: String) {
        // Update the text in the UITextView and reset the scroll offset
        teleprompterTextView?.text = text
        resetScrollOffset()
    }
    
    // MARK: - Scroll Text
    @objc private func scrollText() {
        guard let textView = teleprompterTextView else { return }
        
        // Calculate the new scroll offset
        currentScrollOffset += 1
        let maxOffset = textView.contentSize.height - textView.bounds.size.height
        
        // Check if we have reached the end of the text
        if currentScrollOffset >= maxOffset {
            stopScrolling()
        } else {
            // Scroll the text view
            textView.setContentOffset(CGPoint(x: 0, y: currentScrollOffset), animated: false)
        }
    }
    
    // MARK: - Reset Scroll Offset
    private func resetScrollOffset() {
        currentScrollOffset = 0
        teleprompterTextView?.setContentOffset(CGPoint(x: 0, y: 0), animated: false)
    }
    
    // MARK: - Adjust Scroll Speed
    func adjustScrollSpeed(to speed: Double) {
        scrollSpeed = speed
        if scrollTimer != nil {
            // Restart scrolling with the new speed
            stopScrolling()
            startScrolling()
        }
    }
}
