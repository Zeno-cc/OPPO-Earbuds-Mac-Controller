import CryptoKit
import Foundation

// Developer release validation only. Sparkle alone implements client verification/install.
guard CommandLine.arguments.count == 4,
      let signature = Data(base64Encoded: CommandLine.arguments[2]),
      let publicKey = Data(base64Encoded: CommandLine.arguments[3]) else {
    fputs("Usage: verify-update-signature.swift archive signature public-key\n", stderr)
    exit(2)
}
do {
    let data = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]), options: .mappedIfSafe)
    let key = try Curve25519.Signing.PublicKey(rawRepresentation: publicKey)
    guard key.isValidSignature(signature, for: data) else {
        fputs("Update archive does not match the embedded trust anchor.\n", stderr)
        exit(1)
    }
    print("Archive signature matches the embedded public key.")
} catch {
    fputs("Unable to verify archive signature.\n", stderr)
    exit(1)
}
