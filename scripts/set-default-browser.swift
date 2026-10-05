import AppKit
import UniformTypeIdentifiers

let usage = "Usage: swift scripts/set-default-browser.swift --apply"
if CommandLine.arguments.dropFirst().contains("--help") {
    print(usage)
    exit(0)
}
guard CommandLine.arguments.dropFirst() == ["--apply"] else {
    fputs("\(usage)\nThis changes the macOS default handler for http and https.\n", stderr)
    exit(2)
}

let app = URL(fileURLWithPath: "/Applications/Browser Chooser.app")
guard Bundle(url: app)?.bundleIdentifier == "dk.lvc.browserchooser" else {
    fputs("Install Browser Chooser in /Applications first.\n", stderr)
    exit(1)
}
let workspace = NSWorkspace.shared
let htmlBefore = workspace.urlForApplication(toOpen: UTType.html)
DispatchQueue.main.asyncAfter(deadline: .now() + 60) {
    fputs("Timed out waiting for macOS to finish changing the web handlers.\n", stderr)
    exit(124)
}
workspace.setDefaultApplication(at: app, toOpenURLsWithScheme: "http") { error in
    if let error { fputs("http: \(error.localizedDescription)\n", stderr); exit(1) }
    DispatchQueue.main.async {
        workspace.setDefaultApplication(at: app, toOpenURLsWithScheme: "https") { error in
            if let error { fputs("https: \(error.localizedDescription)\n", stderr); exit(1) }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                let http = workspace.urlForApplication(toOpen: URL(string: "http://example.com/")!)
                let https = workspace.urlForApplication(toOpen: URL(string: "https://example.com/")!)
                print("http: \(http?.path ?? "none")")
                print("https: \(https?.path ?? "none")")
                let htmlAfter = workspace.urlForApplication(toOpen: UTType.html)
                if htmlAfter != htmlBefore {
                    fputs("Warning: macOS also changed the HTML file handler from \(htmlBefore?.path ?? "none") to \(htmlAfter?.path ?? "none"). Restore your previous HTML opener in Finder > Get Info > Open with > Change All.\n", stderr)
                }
                exit(http == app && https == app ? 0 : 1)
            }
        }
    }
}
RunLoop.main.run()
