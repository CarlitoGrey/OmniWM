// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 OmniNull — https://github.com/OmniNull/OmniWM

import Foundation

final class ShellBuiltInHTTPClient: NSObject, URLSessionTaskDelegate, Sendable {
    private let service: ShellBuiltInService
    private let permissions: ShellNetworkPermissions

    init(service: ShellBuiltInService, permissions: ShellNetworkPermissions) {
        self.service = service
        self.permissions = permissions
    }

    static func load(
        _ request: URLRequest,
        service: ShellBuiltInService,
        permissions: ShellNetworkPermissions,
        protocolClasses: [AnyClass]? = nil
    ) async throws -> (Data, URLResponse) {
        try Task.checkCancellation()
        guard let url = request.url, permissions.permits(url, service: service) else {
            throw ShellHTTPFailure("network_blocked")
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.timeoutIntervalForRequest = service == .weather ? 20 : 15
        configuration.timeoutIntervalForResource = service == .weather ? 30 : 20
        if let protocolClasses { configuration.protocolClasses = protocolClasses }
        let session = URLSession(
            configuration: configuration,
            delegate: ShellBuiltInHTTPClient(service: service, permissions: permissions),
            delegateQueue: nil
        )
        defer { session.invalidateAndCancel() }
        let result = try await session.data(for: request)
        try Task.checkCancellation()
        guard permissions.permits(result.1.url ?? url, service: service) else {
            throw ShellHTTPFailure("network_blocked")
        }
        return result
    }

    func urlSession(
        _: URLSession,
        task _: URLSessionTask,
        willPerformHTTPRedirection _: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        completionHandler(request.url.map { permissions.permits($0, service: service) } == true ? request : nil)
    }
}
