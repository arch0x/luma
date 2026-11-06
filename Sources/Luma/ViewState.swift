import SwiftUI

// macOS 27's SDK exports both a State macro and the original property wrapper.
// The CLI toolchain omits SwiftUIMacros, so select the stable wrapper by type alias.
// This keeps the app compatible with macOS 14 and Swift 6.2 as well.
typealias ViewState<Value> = SwiftUI.State<Value>
