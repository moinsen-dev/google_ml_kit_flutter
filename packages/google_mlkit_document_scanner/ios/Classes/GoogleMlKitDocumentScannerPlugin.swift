import Flutter
import UIKit
import VisionKit
import PDFKit

@objc
public class GoogleMlKitDocumentScannerPlugin: NSObject, FlutterPlugin {
  private var pendingResult: FlutterResult?
  private var scannerOptions: DocumentScannerOptions?

  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "google_mlkit_document_scanner",
      binaryMessenger: registrar.messenger()
    )
    let instance = GoogleMlKitDocumentScannerPlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "vision#startDocumentScanner":
      startDocumentScanner(call: call, result: result)
    case "vision#closeDocumentScanner":
      pendingResult = nil
      scannerOptions = nil
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func startDocumentScanner(call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard let args = call.arguments as? [String: Any],
          let optionsDict = args["options"] as? [String: Any] else {
      result(FlutterError(code: "invalid_args", message: "Missing options", details: nil))
      return
    }

    let options = DocumentScannerOptions(from: optionsDict)
    self.scannerOptions = options

    guard let rootViewController = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first?
            .windows
            .first?
            .rootViewController else {
      result(FlutterError(code: "no_view_controller", message: "Could not find root view controller", details: nil))
      return
    }

    let scanner = VNDocumentCameraViewController()
    scanner.delegate = self

    self.pendingResult = result
    rootViewController.present(scanner, animated: true)
  }

  private func saveScannedImages(scan: VNDocumentCameraScan) -> [String] {
    var paths: [String] = []
    let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("document_scanner")
    try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

    let pageLimit = scannerOptions?.pageLimit ?? scan.pageCount
    let count = min(scan.pageCount, pageLimit)

    for i in 0..<count {
      let image = scan.imageOfPage(at: i)
      let fileURL = tempDir.appendingPathComponent("scan_\(i).jpg")
      if let jpegData = image.jpegData(compressionQuality: 0.9) {
        try? jpegData.write(to: fileURL)
        paths.append(fileURL.path)
      }
    }
    return paths
  }

  private func generatePDF(from imagePaths: [String]) -> String? {
    let pdfDocument = PDFDocument()
    for (index, path) in imagePaths.enumerated() {
      guard let image = UIImage(contentsOfFile: path),
            let pdfPage = PDFPage(image: image) else { continue }
      pdfDocument.insert(pdfPage, at: index)
    }
    let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("document_scanner")
    try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    let pdfURL = tempDir.appendingPathComponent("scan.pdf")
    if pdfDocument.write(to: pdfURL) {
      return pdfURL.path
    }
    return nil
  }

  private func finishWithResult(images: [String], pdfPath: String?) {
    guard let result = pendingResult else { return }
    pendingResult = nil

    var resultMap: [String: Any] = [:]
    resultMap["images"] = images

    if let pdfPath = pdfPath {
      resultMap["pdf"] = [
        "pageCount": images.count,
        "uri": pdfPath
      ]
    } else {
      resultMap["pdf"] = NSNull()
    }

    result(resultMap)
  }

  private func finishWithError(_ message: String) {
    guard let result = pendingResult else { return }
    pendingResult = nil
    result(FlutterError(code: "scan_error", message: message, details: nil))
  }
}

extension GoogleMlKitDocumentScannerPlugin: VNDocumentCameraViewControllerDelegate {
  public func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFinishWith scan: VNDocumentCameraScan) {
    controller.dismiss(animated: true) {
      let imagePaths = self.saveScannedImages(scan: scan)
      let formats = self.scannerOptions?.formats ?? [.jpeg]

      var pdfPath: String?
      if formats.contains(.pdf) {
        pdfPath = self.generatePDF(from: imagePaths)
      }

      let jpegPaths = formats.contains(.jpeg) ? imagePaths : nil
      self.finishWithResult(images: jpegPaths ?? [], pdfPath: pdfPath)
    }
  }

  public func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
    controller.dismiss(animated: true) {
      self.finishWithError("User cancelled")
    }
  }

  public func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFailWithError error: Error) {
    controller.dismiss(animated: true) {
      self.finishWithError(error.localizedDescription)
    }
  }
}

// MARK: - Options Parsing

struct DocumentScannerOptions {
  let pageLimit: Int
  let formats: Set<DocumentFormat>
  let mode: ScannerMode
  let isGalleryImport: Bool

  init(from dict: [String: Any]) {
    self.pageLimit = dict["pageLimit"] as? Int ?? 1
    self.isGalleryImport = dict["isGalleryImport"] as? Bool ?? false

    if let formatNames = dict["formats"] as? [String] {
      self.formats = Set(formatNames.compactMap { DocumentFormat(rawValue: $0) })
    } else {
      self.formats = [.jpeg]
    }

    if let modeName = dict["mode"] as? String {
      self.mode = ScannerMode(rawValue: modeName) ?? .full
    } else {
      self.mode = .full
    }
  }
}

enum DocumentFormat: String, Hashable {
  case jpeg
  case pdf
}

enum ScannerMode: String {
  case base
  case filter
  case full
}
