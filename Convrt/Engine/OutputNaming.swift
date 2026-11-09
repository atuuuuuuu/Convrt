import Foundation

/// Output file names. Convrt never overwrites: a taken name gets "-1", "-2", ...
enum OutputNaming {
    /// `dir/base+suffix.ext`, or `dir/base+suffix-N.ext` when that name is taken.
    static func uniqueURL(dir: URL, base: String, suffix: String = "", ext: String) -> URL {
        let fm = FileManager.default
        func candidate(_ n: Int?) -> URL {
            let name = base + suffix + (n.map { "-\($0)" } ?? "")
            let url = dir.appendingPathComponent(name)
            return ext.isEmpty ? url : url.appendingPathExtension(ext)
        }
        var result = candidate(nil)
        var n = 1
        while fm.fileExists(atPath: result.path) {
            result = candidate(n)
            n += 1
        }
        return result
    }
}
