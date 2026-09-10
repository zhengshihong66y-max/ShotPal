import Foundation

nonisolated enum PythonRuntimeError: LocalizedError {
    case validationFailed(String)

    var errorDescription: String? {
        switch self {
        case let .validationFailed(message):
            return L10n.text("内置识别运行环境不完整：\(message)。请重新安装完整安装包；无需另外安装 Python 或依赖。")
        }
    }
}

/// Recognition libraries are immutable, relocatable app resources. There is no
/// user-machine pip/venv setup, developer-path fallback or synchronous import
/// probe here. Actual initialization runs once inside the cancellable worker.
extension LibraryStore {
    nonisolated static func bundledRecognitionPython(named name: String) throws -> URL {
        let files: [String]
        switch name {
        case "music":
            files = ["recognition/site-packages/shazamio/__init__.py",
                     "recognition/site-packages/shazamio_core/__init__.py",
                     "recognition/site-packages/requests/__init__.py"]
        case "scene":
            files = ["recognition/site-packages/torch/__init__.py",
                     "recognition/site-packages/numpy/__init__.py",
                     "recognition/site-packages/transnetv2_pytorch/__init__.py"]
        default:
            throw PythonRuntimeError.validationFailed(L10n.text("未知识别引擎"))
        }
        for path in ["recognition/manifest.json", "recognition_bootstrap.py"] + files {
            guard FileManager.default.isReadableFile(atPath: YTDLPRuntime.toolsURL.appendingPathComponent(path).path) else {
                throw PythonRuntimeError.validationFailed(path)
            }
        }
        guard FileManager.default.isExecutableFile(atPath: YTDLPRuntime.pythonURL.path) else {
            throw PythonRuntimeError.validationFailed("Python")
        }
        return YTDLPRuntime.pythonURL
    }

    nonisolated static func recognitionArguments(_ arguments: [String]) -> [String] {
        ["-I", "-B", "-u", YTDLPRuntime.toolsURL.appendingPathComponent("recognition_bootstrap.py").path] + arguments
    }

    nonisolated static var recognitionEnvironment: [String: String] {
        var environment = YTDLPRuntime.environment
        for key in ["PYTHONUSERBASE", "PYTHONPLATLIBDIR", "PYTHONEXECUTABLE", "__PYVENV_LAUNCHER__",
                    "DYLD_FRAMEWORK_PATH", "DYLD_FALLBACK_LIBRARY_PATH", "DYLD_FALLBACK_FRAMEWORK_PATH"] {
            environment.removeValue(forKey: key)
        }
        environment["PYTHONUNBUFFERED"] = "1"
        environment["PYTHONIOENCODING"] = "utf-8"
        for key in ["OMP_NUM_THREADS", "OPENBLAS_NUM_THREADS", "MKL_NUM_THREADS",
                    "VECLIB_MAXIMUM_THREADS", "NUMEXPR_NUM_THREADS"] {
            environment[key] = "1"
        }
        return environment
    }
}
