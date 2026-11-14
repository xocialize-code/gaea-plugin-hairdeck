import Foundation
import GaeaPluginKit
import GaeaProtocol
import HairDeckKit
import MLXBiRefNet
import MLXToolKit
import Synchronization

// gaea-plugin-hairdeck: HairDeck (hyz317/HairDeck, Apache-2.0; mlx-hairdeck-swift, MIT) on MES mesh.generate_part
// (GPP-1 §3.3.4, Gaea AB-T-0482): one character picture and the box around its head, plus the body the hair goes on,
// to a hair item — a skinned GLB with per-card colours, chain bones and VRMC_springBone, in the body's coordinates.
//
// - One model, `hairdeck`, one lane, `fp32`: the released weights are float32 and load unchanged.
// - The picture: one with transparency is used as it is cut out (`background: alpha`); an opaque one is cut out with
//   BiRefNet first (`background: remove`), a companion model of the plugin prepared with HairDeck. HairDeck reads the
//   matte through its matting hook, which runs the job's BiRefNet call.
// - `subject_box` is required: HairDeck does not find the head itself (AB-D-0227). GaeaPluginKit turns the shares of
//   the upright picture into pixels.
// - The item is written as the model made it: Gaea stamps and previews it and never moves or rescales it. HairDeck's
//   image conditioner is DINOv3, whose licence asks for "Built with DINOv3" wherever it ships: the offer carries it as
//   the licence's attribution, and Gaea writes it into every item and preview.

public let birefnetID = "birefnet"
public let modelID = "hairdeck"

// MARK: - The matting step

/// What a job's matting hook runs: BiRefNet through the job's engine session. HairDeck's configuration is fixed when
/// its lane loads, so the hook reads the running job's step from here; a worker runs one job at a time.
public enum MattingStep {
    static let current = Mutex<(@Sendable (Image) async throws -> Matte)?>(nil)

    /// Runs `body` with `step` as the hook's matting.
    public static func with<T: Sendable>(_ step: @escaping @Sendable (Image) async throws -> Matte,
                                         _ body: () async throws -> T) async throws -> T {
        current.withLock { $0 = step }
        defer { current.withLock { $0 = nil } }
        return try await body()
    }

    /// The hook the lane carries. Outside a job there is nothing to matte with.
    static let hook: HairDeckMatting = { image in
        guard let step = current.withLock({ $0 }) else {
            throw GPPError(.internal, "HairDeck asked for a matte outside a job.")
        }
        return try await step(image)
    }
}

// MARK: - Lanes and the operation

/// HairDeck's one lane, with the matting hook.
public func configuration() -> HairDeckConfiguration {
    var configuration = HairDeckConfiguration()
    configuration.matting = MattingStep.hook
    return configuration
}

/// BiRefNet as Gaea's other plugins run it: the general checkpoint at 1024, fp16.
public func birefnetConfiguration() -> BiRefNetConfiguration { BiRefNetConfiguration() }

/// What the job asks beyond the kit's mapping, checked: the box is required, and the background is one HairDeck serves.
public func check(_ job: Job) throws {
    guard job.param("subject_box") != nil else {
        throw GPPError(.invalidRequest, "HairDeck needs subject_box: the box around the head, hair and face, in the picture.",
                       detail: ["param": "subject_box"])
    }
    let background = job.param("background")?.stringValue ?? "remove"
    guard ["alpha", "remove"].contains(background) else {
        throw GPPError(.invalidRequest, "background is alpha (the picture is cut out) or remove; HairDeck needs the character alone.",
                       detail: ["param": "background"])
    }
}

let generatePart = EngineOperation(CharacterParts.operation) { job, session in
    try check(job)
    let mapped = try CharacterParts.request(job)
    // The hook runs inside this job's own engine call, on its session. A cut-out picture never reaches it: the
    // package uses the picture's alpha.
    let matter = session
    let step: @Sendable (Image) async throws -> Matte = { frame in
        guard let response = try await matter.run(MattingRequest(image: frame), model: birefnetID) as? MattingResponse else {
            throw GPPError(.modelError, "BiRefNet returned no matte.")
        }
        return response.matte
    }
    let response = try await MattingStep.with(step) { try await session.run(mapped.request) }
    guard let part = response as? CharacterPartResponse else { throw GPPError(.modelError, "HairDeck returned no hair.") }
    var effective = mapped.effective
    effective["x-hairdeck.fitted_to_body"] = .bool(part.fittedToBody)
    return RunResult(outputs: try CharacterParts.outputs(part, outputDir: job.outputDir), effective: effective)
}

// MARK: - The plugin

public let license: JSONValue = [
    "spdx": "LicenseRef-DINOv3", "commercial_use": true,
    "terms_url": "https://ai.meta.com/resources/models-and-libraries/dinov3-license/",
    "attribution": "Built with DINOv3",
    "notice": "HairDeck is Apache-2.0; its DINOv3 image conditioner is under Meta's DINOv3 License, which asks for \"Built with DINOv3\" wherever it ships.",
]

let hairdeck = ModelDefinition.engine(HairDeckPackage.self, id: modelID, title: "HairDeck",
                                      lanes: [LaneDefinition(id: "fp32", default: true, configuration: configuration())],
                                      operations: [generatePart])
    .composing([birefnetID])

let birefnet = ModelDefinition.engine(BiRefNetPackage.self, id: birefnetID, title: "BiRefNet (background removal for HairDeck)",
                                      lanes: [LaneDefinition(id: "fp16", default: true, configuration: birefnetConfiguration())],
                                      operations: [])

let offer = PluginManifest.Offer(
    operation: CharacterParts.operation, profile: "mesh",
    model: [
        "id": .string(modelID), "title": "HairDeck", "license": license,
        "memory_class": "medium", "speed_class": "fast", "quality_tiers": ["draft", "standard", "best"],
        "default": true,
        "notes": "Anime-style hair for an avatar from one character picture: hair cards with per-card colours and spring-bone chains, placed on the body's head. About a second a hairstyle. Built with DINOv3.",
        "supports": [
            "parts": ["hair"], "subject_box": "required", "physics": true, "textures": ["atlas", "none"],
            "background_removal": true, "seed": true,
        ],
    ],
    defaults: [:])

public let hairdeckPlugin = GaeaPluginDefinition(
    id: "com.xocialize.gaea.hairdeck", version: "0.1.0", minGaea: "1.7.0", team: "CFZS6RXUCP",
    repo: "https://github.com/xocialize-code/gaea-plugin-hairdeck", title: "HairDeck",
    summary: "HairDeck: hair for an avatar from one character picture (MES mesh.generate_part) — a skinned GLB item with per-card colours and spring bones, placed on the body's head. Built with DINOv3.",
    license: "Apache-2.0", executable: "gaea-hairdeck-worker",
    models: [hairdeck, birefnet], offers: [offer])
