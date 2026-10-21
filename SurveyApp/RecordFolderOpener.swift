import UIKit

enum RecordFolderOpener {
    static func open(_ folder: URL, completion: @escaping (Bool) -> Void) {
        guard var components = URLComponents(string: "shareddocuments://") else {
            completion(false)
            return
        }
        components.path = folder.path
        guard let url = components.url else {
            completion(false)
            return
        }
        UIApplication.shared.open(url, options: [:], completionHandler: completion)
    }
}
