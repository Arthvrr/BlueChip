import Foundation
import UserNotifications
import Combine

class NotificationManager: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    
    static let shared = NotificationManager()
    
    override private init() {
        super.init()
        // Permet d'intercepter les notifications
        UNUserNotificationCenter.current().delegate = self
    }
    
    // Demande la permission à l'utilisateur
    func requestAuthorization() {
        let options: UNAuthorizationOptions = [.alert, .sound, .badge]
        UNUserNotificationCenter.current().requestAuthorization(options: options) { success, error in
            if let error = error { print("Erreur Notif : \(error.localizedDescription)") }
        }
    }
    
    // 1. Notification immédiate (Targets & Goals atteints)
    func sendImmediateNotification(title: String, subtitle: String, body: String, identifier: String = UUID().uuidString) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.subtitle = subtitle
        content.body = body
        content.sound = .default
        
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
    
    // 2. Notification programmée à la seconde près (Calendrier)
    func scheduleCalendarNotification(for date: Date, title: String, body: String, identifier: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        
        let triggerDate = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let trigger = UNCalendarNotificationTrigger(dateMatching: triggerDate, repeats: false)
        
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)
    }
    
    // 3. Annulation si on supprime l'événement
    func cancelScheduledNotification(identifier: String) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [identifier])
    }
    
    // CRUCIAL : Force l'affichage de la bannière même quand l'app est utilisée
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
}
