import SwiftUI
import UIKit

struct ContentView: View {
    var body: some View {
        VStack {
            Text("Teleprompter App")
                .font(.largeTitle)
                .padding()
            
            // Integrate the UIKit ViewController
            UIViewControllerRepresented()
                .edgesIgnoringSafeArea(.all)
        }
    }
}

struct UIViewControllerRepresented: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> UIViewController {
        let storyboard = UIStoryboard(name: "Main", bundle: nil)
        let viewController = storyboard.instantiateViewController(withIdentifier: "ViewController") as! ViewController
        return viewController
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        // Update the UI if needed
    }
}
