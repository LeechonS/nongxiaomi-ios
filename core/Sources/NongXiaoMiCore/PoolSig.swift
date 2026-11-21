import Foundation

// MARK: - 池条目签名(编辑检测) 与 Java兼容数字形态

public enum JavaNumber {

    /// Java Double.toString 兼容形态(与Android端完全一致):
    /// 1e-3 <= |v| < 1e7 用小数(无小数位时补".0"), 否则科学计数 d[.ddd]E±ee
    public static func doubleString(_ d: Double) -> String {
        if d.isNaN { return "NaN" }
        if d.isInfinite { return d < 0 ? "-Infinity" : "Infinity" }
        if d == 0 { return d.sign == .minus ? "-0.0" : "0.0" }
        let neg = d < 0
        let a = abs(d)
        // Swift最短路程表示(与Java同口径: 能往返的最短十进制)
        let s = String(a)
        let mant: String
        let exp10: Int
        if let e = s.firstIndex(of: "e") { // 三元表达式不窄化可选, 用if拆
            mant = String(s[..<e])
            exp10 = Int(s[s.index(after: e)...]) ?? 0
        } else {
            mant = s
            exp10 = 0
        }
        let dot = mant.firstIndex(of: ".")
        let intPart: String
        let fracPart: String
        if let d2 = dot {
            intPart = String(mant[..<d2])
            fracPart = String(mant[mant.index(after: d2)...])
        } else {
            intPart = mant
            fracPart = ""
        }
        let intAllZero = !intPart.isEmpty && intPart.allSatisfy { $0 == "0" }
        var digits = (intAllZero ? "" : intPart) + fracPart
        // 整数位数(可0/负: 0.0001→0, 1e-5→-4)
        let k = (intAllZero ? 0 : intPart.count) + exp10
        // Java用"最短有效数字": 尾零可移进指数(1e7 → "1.0E7" 而非 "1.0000000E7";
        // 1200.0 → "1200.0" 用2位有效数字)。逐位剥尾零, 不再往返即停
        while let last = digits.last, last == "0" {
            let d2 = String(digits.dropLast())
            let cand: String
            if k <= 0 {
                cand = "0." + String(repeating: "0", count: -k) + d2
            } else if k < d2.count {
                let i = d2.index(d2.startIndex, offsetBy: k)
                cand = String(d2[..<i]) + "." + String(d2[i...])
            } else {
                cand = d2 + String(repeating: "0", count: k - d2.count)
            }
            guard let v = Double(cand), v == a else { break }
            digits = d2
        }
        let out: String
        if a >= 1e-3 && a < 1e7 {
            if k <= 0 {
                out = "0." + String(repeating: "0", count: -k) + digits
            } else if k < digits.count {
                let i = digits.index(digits.startIndex, offsetBy: k)
                out = String(digits[..<i]) + "." + String(digits[i...])
            } else {
                out = digits + String(repeating: "0", count: k - digits.count) + ".0"
            }
        } else {
            let lz = digits.prefix { $0 == "0" }.count
            let sig_ = digits[digits.index(digits.startIndex, offsetBy: lz)...]
            let first = sig_[sig_.startIndex]
            let mantissa: String
            if sig_.count > 1 { // 拆开避免类型检查超时
                let rest = sig_[sig_.index(after: sig_.startIndex)...]
                mantissa = String(first) + "." + String(rest)
            } else {
                mantissa = String(first) + ".0"
            }
            let exp = k - lz - 1
            out = mantissa + "E" + (exp < 0 ? "-" : "") + String(abs(exp))
        }
        return neg ? "-" + out : out
    }
}

public enum PoolSig {

    /// Java String.hashCode (32位, 按UTF-16码元, 溢出环绕)。
    /// 池签名 = String.valueOf(hashCode)。iOS端必须与Android端算出同一值,
    /// 否则同一内容两端签名不同会反复重推(浪费流量, 不破坏数据)
    public static func javaStringHash(_ s: String) -> Int32 {
        var h: Int32 = 0
        for u in s.utf16 {
            h = h &* 31 &+ Int32(u)
        }
        return h
    }

    /// 池条目签名 (Backup.sigOf:375-391):
    /// 键按字典序(TreeMap), 排除 device/mtime/stype/photo_b64
    /// (keepPhotoB64s=false时再排除 photo_b64s/photo——照片base64两处构建
    /// 路径形态不同必须排除; 日常观察的签名含照片, 加/换照片也算编辑自动重推),
    /// 拼成 "k=v;" 后取字符串hash。
    /// - Note: values须为与Android端同口径的形态(数字经JavaNumber.doubleString)
    public static func sig(_ fields: [String: String], keepPhotoB64s: Bool) -> String {
        var excluded = ["device", "mtime", "stype", "photo_b64"]
        if !keepPhotoB64s {
            excluded += ["photo_b64s", "photo"]
        }
        let body = fields.keys
            .filter { !excluded.contains($0) }
            .sorted()
            // 每条结尾都带分号(Java sigOf逐条 append(key)=append(v).append(';'), 含最后一条)
            .map { "\($0)=\(fields[$0] ?? "");" }
            .joined()
        return String(javaStringHash(body))
    }
}
