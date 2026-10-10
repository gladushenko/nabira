import Foundation
import PackagePlugin

@main
struct CompileLocalizations: BuildToolPlugin {
    func createBuildCommands(context: PluginContext, target: Target) throws -> [Command] {
        let catalog = context.package.directoryURL.appending(path: "Localizations/Localizable.xcstrings")
        let output = context.pluginWorkDirectoryURL.appending(path: "Resources")
        let files = ["en", "ru"].flatMap { language in
            ["strings", "stringsdict"].map {
                output.appending(path: "\(language).lproj/Localizable.\($0)")
            }
        }
        return [.buildCommand(
            displayName: "Compile Nabira translations",
            executable: URL(fileURLWithPath: "/usr/bin/xcrun"),
            arguments: ["xcstringstool", "compile", catalog.path, "--output-directory", output.path],
            inputFiles: [catalog], outputFiles: files
        )]
    }
}
