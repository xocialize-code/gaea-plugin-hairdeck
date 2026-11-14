import Foundation
import GaeaProtocol
import HairDeckKit
import HairDeckPlugin
import MLXBiRefNet
import MLXServeCore
import MLXToolKit

// The in-process reference for the plugin: HairDeck and BiRefNet loaded by MLXServeEngine in this process, with the
// lane configurations the worker uses (HairDeckPlugin), and BiRefNet as the matting step. The GLB is written to --out,
// and one JSON line of timings is printed. Not part of the plugin bundle.
//
//   hairdeck-inproc --image <png|jpg> --box x0,y0,x1,y1 [--body <vrm|glb>] [--seed 0] [--no-physics] [--no-texture]
//                   [--models-root <dir>] [--out <glb>]
// --box: pixels of the picture, as the worker hands HairDeck (GaeaPluginKit turns MES's shares into these).

var args = Array(CommandLine.arguments.dropFirst())
func option(_ name: String) -> String? {
    guard let i = args.firstIndex(of: name), i + 1 < args.count else { return nil }
    defer { args.removeSubrange(i...(i + 1)) }
    return args[i + 1]
}
func flag(_ name: String) -> Bool {
    guard let i = args.firstIndex(of: name) else { return false }
    args.remove(at: i)
    return true
}
func seconds(since start: ContinuousClock.Instant) -> Double {
    let d = ContinuousClock.now - start
    return Double(d.components.seconds) + Double(d.components.attoseconds) / 1e18
}

let modelsRoot = URL(fileURLWithPath: option("--models-root")
                     ?? NSHomeDirectory() + "/Library/Application Support/MLXEngine/Models", isDirectory: true)
guard let imagePath = option("--image") else { fatalError("hairdeck-inproc needs --image") }
guard let box = option("--box")?.split(separator: ",").compactMap({ Float($0) }), box.count == 4 else { fatalError("hairdeck-inproc needs --box x0,y0,x1,y1") }
let body = try option("--body").map { Mesh(format: .glb, data: try Data(contentsOf: URL(fileURLWithPath: $0))) }
let seed = UInt64(option("--seed") ?? "") ?? 0
let physics = !flag("--no-physics"), texture = !flag("--no-texture")

// The budget Gaea sends a worker on a large Mac (wiresWeights off).
let engine = MLXServeEngine(workerBudget: WorkerBudget(ceilingBytes: 100_000_000_000, wiresWeights: false))
await engine.useModelStore(ModelStore(root: modelsRoot))
let matteID = PackageID(birefnetID), id = PackageID(modelID)
_ = try await engine.register(BiRefNetPackage.registration, configuration: birefnetConfiguration(), id: matteID)
_ = try await engine.register(HairDeckPackage.registration, configuration: configuration(), id: id)
var clock = ContinuousClock.now
_ = try await engine.prepare(.matting, package: matteID)
_ = try await engine.prepare(.characterPart, package: id)
var result: [String: Any] = ["model": modelID, "seed": seed, "physics": physics, "texture": texture, "prepare_s": seconds(since: clock)]
clock = ContinuousClock.now
let url = URL(fileURLWithPath: imagePath)
let picture = Image(format: url.pathExtension.lowercased() == "png" ? .png : .jpeg, data: try Data(contentsOf: url))
let step: @Sendable (Image) async throws -> Matte = { frame in
    guard let response = try await engine.run(MattingRequest(image: frame), package: matteID) as? MattingResponse else {
        fatalError("BiRefNet returned no matte")
    }
    return response.matte
}
let request = CharacterPartRequest(image: picture, subjectBox: box, body: body, part: .hair, seed: seed, springBones: physics, colors: texture)
let response = try await MattingStep.with(step) { try await engine.run(request, package: id) }
guard let part = response as? CharacterPartResponse else { fatalError("HairDeck returned no hair") }
result["run_s"] = seconds(since: clock)
result["vertices"] = part.mesh.vertexCount ?? 0
result["fitted_to_body"] = part.fittedToBody
if let out = option("--out") { try part.mesh.data.write(to: URL(fileURLWithPath: out)) }
var usage = rusage()
getrusage(RUSAGE_SELF, &usage)
result["max_rss_gb"] = Double(usage.ru_maxrss) / 1e9
print(String(decoding: try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys]), as: UTF8.self))
