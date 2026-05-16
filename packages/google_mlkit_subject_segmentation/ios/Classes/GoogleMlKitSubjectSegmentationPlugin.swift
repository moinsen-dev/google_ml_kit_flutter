import Flutter
import UIKit
import Vision
import CoreImage
import CoreVideo

@objc
public class GoogleMlKitSubjectSegmentationPlugin: NSObject, FlutterPlugin {
  private var instances: [String: Any] = [:]

  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "google_mlkit_subject_segmentation",
      binaryMessenger: registrar.messenger()
    )
    let instance = GoogleMlKitSubjectSegmentationPlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "vision#startSubjectSegmenter":
      handleSegmentation(call: call, result: result)
    case "vision#closeSubjectSegmenter":
      if let args = call.arguments as? [String: Any], let uid = args["id"] as? String {
        instances.removeValue(forKey: uid)
      }
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func handleSegmentation(call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard let args = call.arguments as? [String: Any],
          let imageData = args["imageData"] as? [String: Any],
          let uid = args["id"] as? String else {
      result(FlutterError(code: "invalid_args", message: "Missing arguments", details: nil))
      return
    }

    guard let cgImage = cgImage(from: imageData) else {
      result(FlutterError(code: "invalid_image", message: "Invalid or missing image data", details: nil))
      return
    }

    let options = args["options"] as? [String: Any] ?? [:]
    let enableForegroundBitmap = (options["enableForegroundBitmap"] as? NSNumber)?.boolValue ?? false
    let enableForegroundConfidenceMask = (options["enableForegroundConfidenceMask"] as? NSNumber)?.boolValue ?? false
    let enableMultiSubjectBitmap = options["enableMultiSubjectBitmap"] as? [String: Any] ?? [:]
    let enableSubjectConfidenceMask = (enableMultiSubjectBitmap["enableConfidenceMask"] as? NSNumber)?.boolValue ?? false
    let enableSubjectBitmap = (enableMultiSubjectBitmap["enableSubjectBitmap"] as? NSNumber)?.boolValue ?? false

    let request = VNGenerateForegroundInstanceMaskRequest()
    let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])

    do {
      try handler.perform([request])
      guard let observation = request.results?.first as? VNInstanceMaskObservation else {
        result(["subjects": [], "foregroundBitmap": NSNull(), "foregroundConfidenceMask": NSNull()])
        return
      }

      var resultMap: [String: Any] = [:]

      if enableForegroundBitmap {
        let maskBuffer = try observation.generateScaledMaskForImage(
          forInstances: observation.allInstances,
          from: handler
        )
        resultMap["foregroundBitmap"] = compositeMaskedImage(cgImage: cgImage, maskBuffer: maskBuffer) ?? NSNull()
      } else {
        resultMap["foregroundBitmap"] = NSNull()
      }

      if enableForegroundConfidenceMask {
        let maskBuffer = try observation.createScaledMask(
          for: observation.allInstances,
          croppedToInstancesContent: false
        )
        resultMap["foregroundConfidenceMask"] = floatArrayFromPixelBuffer(maskBuffer) ?? NSNull()
      } else {
        resultMap["foregroundConfidenceMask"] = NSNull()
      }

      let enableMultiSubjects = !observation.allInstances.isEmpty && (enableSubjectBitmap || enableSubjectConfidenceMask)
      if enableMultiSubjects {
        var subjects: [[String: Any]] = []
        let boundingBoxes = computeBoundingBoxes(from: observation.instanceMask, instances: observation.allInstances)

        for instanceIndex in observation.allInstances {
          var subject: [String: Any] = [:]
          let box = boundingBoxes[instanceIndex] ?? CGRect(x: 0, y: 0, width: CGFloat(cgImage.width), height: CGFloat(cgImage.height))
          subject["startX"] = Int(box.minX)
          subject["startY"] = Int(box.minY)
          subject["width"] = Int(box.width)
          subject["height"] = Int(box.height)

          if enableSubjectConfidenceMask {
            let maskBuffer = try observation.createScaledMask(
              for: IndexSet(integer: instanceIndex),
              croppedToInstancesContent: false
            )
            subject["confidenceMask"] = floatArrayFromPixelBuffer(maskBuffer) ?? NSNull()
          } else {
            subject["confidenceMask"] = NSNull()
          }

          if enableSubjectBitmap {
            let maskBuffer = try observation.generateScaledMaskForImage(
              forInstances: IndexSet(integer: instanceIndex),
              from: handler
            )
            subject["bitmap"] = compositeMaskedImage(cgImage: cgImage, maskBuffer: maskBuffer) ?? NSNull()
          } else {
            subject["bitmap"] = NSNull()
          }

          subjects.append(subject)
        }
        resultMap["subjects"] = subjects
      } else {
        resultMap["subjects"] = []
      }

      result(resultMap)
    } catch {
      result(FlutterError(code: "segmentation_error", message: error.localizedDescription, details: nil))
    }
  }

  // MARK: - Image Parsing

  private func cgImage(from imageData: [String: Any]) -> CGImage? {
    guard let imageType = imageData["type"] as? String else { return nil }
    switch imageType {
    case "file":
      guard let path = imageData["path"] as? String else { return nil }
      guard let image = UIImage(contentsOfFile: path) else { return nil }
      return image.cgImage
    case "bytes":
      return cgImageFromBytes(imageData)
    case "bitmap":
      return cgImageFromBitmap(imageData)
    default:
      return nil
    }
  }

  private func cgImageFromBytes(_ imageData: [String: Any]) -> CGImage? {
    guard let byteData = imageData["bytes"] as? FlutterStandardTypedData else { return nil }
    let imageBytes = byteData.data
    guard let metadata = imageData["metadata"] as? [String: Any],
          let width = metadata["width"] as? NSNumber,
          let height = metadata["height"] as? NSNumber,
          let rawFormat = metadata["image_format"] as? NSNumber,
          let bytesPerRow = metadata["bytes_per_row"] as? NSNumber else {
      return nil
    }
    let widthVal = Int(truncating: width)
    let heightVal = Int(truncating: height)
    let bytesPerRowVal = Int(truncating: bytesPerRow)
    let bufferSize = bytesPerRowVal * heightVal
    guard bufferSize > 0, imageBytes.count >= bufferSize else { return nil }

    let copy = UnsafeMutableRawPointer.allocate(byteCount: bufferSize, alignment: 1)
    imageBytes.copyBytes(to: UnsafeMutableBufferPointer(start: copy.assumingMemoryBound(to: UInt8.self), count: bufferSize))

    let format = OSType(truncating: rawFormat)
    var pxBuffer: CVPixelBuffer?
    CVPixelBufferCreateWithBytes(
      kCFAllocatorDefault,
      widthVal,
      heightVal,
      format,
      copy,
      bytesPerRowVal,
      { _, ptr in ptr?.deallocate() },
      nil,
      nil,
      &pxBuffer
    )
    guard let pixelBuffer = pxBuffer else {
      copy.deallocate()
      return nil
    }
    return cgImageFromPixelBuffer(pixelBuffer)
  }

  private func cgImageFromBitmap(_ imageData: [String: Any]) -> CGImage? {
    guard let bitmapData = imageData["bitmapData"] as? FlutterStandardTypedData else { return nil }
    if let metadata = imageData["metadata"] as? [String: Any],
       let width = metadata["width"] as? NSNumber,
       let height = metadata["height"] as? NSNumber {
      var result: CGImage?
      let colorSpace = CGColorSpaceCreateDeviceRGB()
      let bytesPerPixel = 4
      let bytesPerRow = bytesPerPixel * width.intValue
      let bitsPerComponent = 8

      bitmapData.data.withUnsafeBytes { rawBuffer in
        guard let rawData = rawBuffer.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return }
        guard let context = CGContext(
          data: UnsafeMutableRawPointer(mutating: rawData),
          width: width.intValue,
          height: height.intValue,
          bitsPerComponent: bitsPerComponent,
          bytesPerRow: bytesPerRow,
          space: colorSpace,
          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        ) else { return }
        result = context.makeImage()
      }
      if let result = result { return result }
    }
    guard let image = UIImage(data: bitmapData.data) else { return nil }
    return image.cgImage
  }

  private func cgImageFromPixelBuffer(_ pixelBuffer: CVPixelBuffer) -> CGImage? {
    let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
    let context = CIContext(options: nil)
    return context.createCGImage(ciImage, from: ciImage.extent)
  }

  // MARK: - Mask Processing

  private func compositeMaskedImage(cgImage: CGImage, maskBuffer: CVPixelBuffer) -> Data? {
    let originalCIImage = CIImage(cgImage: cgImage)
    let maskCIImage = CIImage(cvPixelBuffer: maskBuffer)

    let filter = CIFilter.blendWithMask()
    filter.inputImage = originalCIImage
    filter.backgroundImage = CIImage(color: .clear).cropped(to: originalCIImage.extent)
    filter.maskImage = maskCIImage

    guard let outputImage = filter.outputImage else { return nil }
    let context = CIContext(options: nil)
    guard let outputCGImage = context.createCGImage(outputImage, from: outputImage.extent) else { return nil }
    let uiImage = UIImage(cgImage: outputCGImage)
    return uiImage.pngData()
  }

  private func floatArrayFromPixelBuffer(_ pixelBuffer: CVPixelBuffer) -> [Double]? {
    CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
    defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

    guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else { return nil }
    let width = CVPixelBufferGetWidth(pixelBuffer)
    let height = CVPixelBufferGetHeight(pixelBuffer)
    let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)

    var result: [Double] = []
    result.reserveCapacity(width * height)

    for y in 0..<height {
      let rowPtr = baseAddress.advanced(by: y * bytesPerRow).assumingMemoryBound(to: Float.self)
      for x in 0..<width {
        result.append(Double(rowPtr[x]))
      }
    }
    return result
  }

  private func computeBoundingBoxes(from pixelBuffer: CVPixelBuffer, instances: IndexSet) -> [Int: CGRect] {
    CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
    defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

    guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else { return [:] }
    let width = CVPixelBufferGetWidth(pixelBuffer)
    let height = CVPixelBufferGetHeight(pixelBuffer)
    let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)

    var minX: [Int: Int] = [:]
    var minY: [Int: Int] = [:]
    var maxX: [Int: Int] = [:]
    var maxY: [Int: Int] = [:]

    for instance in instances {
      minX[instance] = width
      minY[instance] = height
      maxX[instance] = 0
      maxY[instance] = 0
    }

    for y in 0..<height {
      let rowPtr = baseAddress.advanced(by: y * bytesPerRow).assumingMemoryBound(to: UInt8.self)
      for x in 0..<width {
        let label = Int(rowPtr[x])
        if instances.contains(label) {
          if x < minX[label]! { minX[label] = x }
          if y < minY[label]! { minY[label] = y }
          if x > maxX[label]! { maxX[label] = x }
          if y > maxY[label]! { maxY[label] = y }
        }
      }
    }

    var boxes: [Int: CGRect] = [:]
    for instance in instances {
      let x0 = minX[instance] ?? 0
      let y0 = minY[instance] ?? 0
      let x1 = maxX[instance] ?? 0
      let y1 = maxY[instance] ?? 0
      boxes[instance] = CGRect(x: x0, y: y0, width: x1 - x0 + 1, height: y1 - y0 + 1)
    }
    return boxes
  }
}
