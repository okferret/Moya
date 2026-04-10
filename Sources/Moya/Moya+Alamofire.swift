import Foundation
import Alamofire

public typealias Session = Alamofire.Session
internal typealias Request = Alamofire.Request
internal typealias DownloadRequest = Alamofire.DownloadRequest
internal typealias UploadRequest = Alamofire.UploadRequest
internal typealias DataRequest = Alamofire.DataRequest
internal typealias DataStreamRequest = Alamofire.DataStreamRequest

internal typealias URLRequestConvertible = Alamofire.URLRequestConvertible

/// Represents an HTTP method.
public typealias Method = Alamofire.HTTPMethod

/// Choice of parameter encoding.
public typealias ParameterEncoding = Alamofire.ParameterEncoding
public typealias JSONEncoding = Alamofire.JSONEncoding
public typealias URLEncoding = Alamofire.URLEncoding

/// Multipart form.
public typealias RequestMultipartFormData = Alamofire.MultipartFormData

/// Multipart form data encoding result.
public typealias DownloadDestination = Alamofire.DownloadRequest.Destination

/// Make the Alamofire Request type conform to our type, to prevent leaking Alamofire to plugins.
extension Request: RequestType {
    public var sessionHeaders: [String: String] {
        delegate?.sessionConfiguration.httpAdditionalHeaders as? [String: String] ?? [:]
    }
}

/// Represents Request interceptor type that can modify/act on Request
public typealias RequestInterceptor = Alamofire.RequestInterceptor

/// Internal token that can be used to cancel requests
public final class CancellableToken: Cancellable, CustomDebugStringConvertible {
    let cancelAction: () -> Void
    let request: Request?
    
    public fileprivate(set) var isCancelled = false
    
    fileprivate var lock: DispatchSemaphore = DispatchSemaphore(value: 1)
    
    public func cancel() {
        _ = lock.wait(timeout: DispatchTime.distantFuture)
        defer { lock.signal() }
        guard !isCancelled else { return }
        isCancelled = true
        cancelAction()
    }
    
    public init(action: @escaping () -> Void) {
        self.cancelAction = action
        self.request = nil
    }
    
    init(request: Request) {
        self.request = request
        self.cancelAction = {
            request.cancel()
        }
    }
    
    /// A textual representation of this instance, suitable for debugging.
    public var debugDescription: String {
        guard let request = self.request else {
            return "Empty Request"
        }
        return request.cURLDescription()
    }
    
}

internal typealias RequestableCompletion = (HTTPURLResponse?, URLRequest?, Data?, Swift.Error?) -> Void

internal protocol Requestable {
    func response(callbackQueue: DispatchQueue?, completionHandler: @escaping RequestableCompletion) -> Self
}

extension DataRequest: Requestable {
    internal func response(callbackQueue: DispatchQueue?, completionHandler: @escaping RequestableCompletion) -> Self {
        if let callbackQueue = callbackQueue {
            return response(queue: callbackQueue) { handler  in
                completionHandler(handler.response, handler.request, handler.data, handler.error)
            }
        } else {
            return response { handler  in
                completionHandler(handler.response, handler.request, handler.data, handler.error)
            }
        }
    }
}

extension DownloadRequest: Requestable {
    internal func response(callbackQueue: DispatchQueue?, completionHandler: @escaping RequestableCompletion) -> Self {
        if let callbackQueue = callbackQueue {
            return response(queue: callbackQueue) { handler  in
                completionHandler(handler.response, handler.request, nil, handler.error)
            }
        } else {
            return response { handler  in
                completionHandler(handler.response, handler.request, nil, handler.error)
            }
        }
    }
}

extension DataStreamRequest: Requestable {
    
    func response(callbackQueue: DispatchQueue?, completionHandler: @escaping RequestableCompletion) -> Self {
        return responseStream(on: callbackQueue ?? .main) { stream in
            switch stream.event {
            case .complete(let handler):
                completionHandler(handler.response, handler.request, nil, handler.error)
            default: break
            }
        }
    }
    
}

final class MoyaRequestInterceptor: RequestInterceptor {
    var prepare: ((URLRequest) -> URLRequest)?
    
    @Atomic
    var willSend: ((URLRequest) -> Void)?
    
    init(prepare: ((URLRequest) -> URLRequest)? = nil, willSend: ((URLRequest) -> Void)? = nil) {
        self.prepare = prepare
        self.willSend = willSend
    }
    
    func adapt(_ urlRequest: URLRequest, for session: Alamofire.Session, completion: @escaping (Result<URLRequest, Error>) -> Void) {
        let request = prepare?(urlRequest) ?? urlRequest
        willSend?(request)
        completion(.success(request))
    }
}

/// DestinationStream
public final class DestinationOutputStream {
    internal let url: URL
    internal let stream: Optional<OutputStream>
    
    /// Int64
    internal var totalBytesCount: Int64 {
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            if let value: Int64 = attributes[.size] as? Int64 {
                return value
            } else {
                return 0
            }
        } catch {
            return 0
        }
    }
    
    /// 初始化
    /// - Parameters:
    ///   - url: URL
    ///   - append: Bool
    public init(url: URL, append: Bool) {
        self.url = url
        self.stream = .init(url: url, append: append)
    }
    
    /// write buffer
    /// - Parameters:
    ///   - buffer: UnsafePointer<UInt8>
    ///   - len: Int
    /// - Returns: Int
    internal func write(_ buffer: UnsafePointer<UInt8>, maxLength: Int) -> Int {
        guard let stream = stream else { return 0 }
        if stream.streamStatus == .notOpen {
            stream.open()
        }
        return stream.write(buffer, maxLength: maxLength)
    }
    
    /// Bool
    internal var hasSpaceAvailable: Bool {
        return stream?.hasSpaceAvailable ?? false
    }
    
    /// open
    internal func open() {
        stream?.open()
    }
    
    /// close
    internal func close() {
        stream?.close()
    }
}
