import Foundation
import ServiceManagement

enum AppLaunchServiceError: Error {
    case unsupportedEnvironment
    case unsupportedSystemVersion
    case requiresApproval
    case registrationFailed(String)
    case unregistrationFailed(String)
}

struct AppLaunchService {
    private protocol LaunchAtLoginRegistrar {
        var isEnabled: Bool { get }

        func setEnabled(isRunningFromAppBundle: Bool, _ enabled: Bool) throws
    }

    private struct UnavailableLaunchAtLoginRegistrar: LaunchAtLoginRegistrar {
        var isEnabled: Bool {
            false
        }

        func setEnabled(isRunningFromAppBundle: Bool, _ enabled: Bool) throws {
            throw AppLaunchServiceError.unsupportedSystemVersion
        }
    }

    @available(macOS 13.0, *)
    private struct SMAppServiceLaunchAtLoginRegistrar: LaunchAtLoginRegistrar {
        private let service: SMAppService = .mainApp

        var isEnabled: Bool {
            self.service.status == .enabled
        }

        func setEnabled(isRunningFromAppBundle: Bool, _ enabled: Bool) throws {
            guard isRunningFromAppBundle else {
                throw AppLaunchServiceError.unsupportedEnvironment
            }

            if enabled {
                do {
                    try self.service.register()
                } catch {
                    throw AppLaunchServiceError.registrationFailed(error.localizedDescription)
                }

                let status = self.service.status
                if status == .enabled { return }
                if status == .requiresApproval {
                    SMAppService.openSystemSettingsLoginItems()
                    throw AppLaunchServiceError.requiresApproval
                }
                throw AppLaunchServiceError.registrationFailed("status=\(status.rawValue)")
            } else {
                do {
                    try self.service.unregister()
                } catch {
                    throw AppLaunchServiceError.unregistrationFailed(error.localizedDescription)
                }

                if self.service.status == .enabled {
                    throw AppLaunchServiceError.unregistrationFailed("status=\(self.service.status.rawValue)")
                }
            }
        }
    }

    init() {}

    var isEnabled: Bool {
        self.registrar().isEnabled
    }

    func setEnabled(_ enabled: Bool) throws {
        try self.registrar().setEnabled(isRunningFromAppBundle: self.isRunningFromAppBundle, enabled)
    }

    private var isRunningFromAppBundle: Bool {
        Bundle.main.bundleURL.pathExtension.caseInsensitiveCompare("app") == .orderedSame
    }

    private func registrar() -> any LaunchAtLoginRegistrar {
        if #available(macOS 13.0, *) {
            return SMAppServiceLaunchAtLoginRegistrar()
        }
        return UnavailableLaunchAtLoginRegistrar()
    }
}

// MARK: - Repository

@MainActor
final class DefaultLaunchAtLoginRepository: LaunchAtLoginRepository {
    private let service: AppLaunchService

    init(service: AppLaunchService) {
        self.service = service
    }

    var isEnabled: Bool {
        self.service.isEnabled
    }

    func setEnabled(_ enabled: Bool) throws {
        try self.service.setEnabled(enabled)
    }
}
