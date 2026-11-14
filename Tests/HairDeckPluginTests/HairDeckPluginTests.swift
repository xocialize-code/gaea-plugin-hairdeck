import Foundation
@testable import GaeaPluginKit
import MLXToolKit
import GaeaProtocol
import Testing
@testable import HairDeckPlugin

@Suite struct HairDeckPluginTests {
    func job(_ params: [String: JSONValue]) -> Job {
        Job(requestID: "r", job: "job_1", operation: "mesh.generate_part", model: "hairdeck", lane: "fp32", inputs: [:],
            params: params, modelParams: [:], adapters: [], seed: 7, outputDir: URL(fileURLWithPath: "/tmp"))
    }

    @Test func theBoxIsRequiredAndTheBackgroundIsOneItServes() throws {
        let box: JSONValue = ["x": 0.25, "y": 0.1, "width": 0.5, "height": 0.4]
        try check(job(["subject_box": box, "background": "alpha"]))
        try check(job(["subject_box": box, "background": "remove"]))
        try check(job(["subject_box": box]))
        #expect(throws: GPPError.self) { try check(job(["background": "alpha"])) }
        #expect(throws: GPPError.self) { try check(job(["subject_box": box, "background": "keep"])) }
    }

    @Test func manifestOffersGeneratePartWithBothWeightSourcesAndBiRefNet() throws {
        let manifest = try hairdeckPlugin.manifest()
        #expect(manifest.offers.map(\.modelID) == ["hairdeck"])
        #expect(manifest.offers.allSatisfy { $0.profile == "mesh" && $0.operation == "mesh.generate_part" })
        let model = try #require(manifest.models.first { $0.id == "hairdeck" })
        #expect(model.lanes.map(\.id) == ["fp32"])
        let repos = model.lanes[0].resolved.weightSources.map(\.repo)
        #expect(repos.contains("xocialize/hairdeck-mlx") && repos.contains("xocialize/trellis2-mlx"), "\(repos)")
        #expect(repos.contains("mlx-community/BiRefNet-fp16"), "BiRefNet's weights too: \(repos)")
    }

    @Test func theHookRefusesOutsideAJob() async {
        await #expect(throws: GPPError.self) { _ = try await MattingStep.hook(Image(format: .png, data: Data())) }
    }
}
