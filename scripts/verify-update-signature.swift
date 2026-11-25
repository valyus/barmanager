// Checks an update archive's EdDSA signature against the public key an app
// was built with, the same check Sparkle does before installing.
//
//   swift scripts/verify-update-signature.swift BarManager.app BarManager-x.y.z.zip SIGNATURE
import CryptoKit
import Foundation

let args = CommandLine.arguments
guard args.count == 4 else {
    FileHandle.standardError.write("usage: verify-update-signature.swift <app> <archive> <base64 signature>\n".data(using: .utf8)!)
    exit(2)
}
let plist = URL(fileURLWithPath: args[1]).appendingPathComponent("Contents/Info.plist")
guard let info = NSDictionary(contentsOf: plist), let publicKey = info["SUPublicEDKey"] as? String,
      let keyData = Data(base64Encoded: publicKey), let key = try? Curve25519.Signing.PublicKey(rawRepresentation: keyData) else {
    FileHandle.standardError.write("✗ \(args[1]) has no valid SUPublicEDKey\n".data(using: .utf8)!)
    exit(1)
}
guard let archive = FileManager.default.contents(atPath: args[2]), let signature = Data(base64Encoded: args[3]) else {
    FileHandle.standardError.write("✗ Can't read \(args[2]) or the signature\n".data(using: .utf8)!)
    exit(1)
}
if key.isValidSignature(signature, for: archive) {
    print("✓ \(URL(fileURLWithPath: args[2]).lastPathComponent) is signed with the key in \(URL(fileURLWithPath: args[1]).lastPathComponent)")
} else {
    FileHandle.standardError.write("✗ The signature doesn't match the app's SUPublicEDKey: the private key isn't the one the app trusts\n".data(using: .utf8)!)
    exit(1)
}
