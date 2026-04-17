//
//  PaceReferenceLoader.swift
//  HyroxCore
//
//  Created by bbdyno on 4/17/26.
//

import Foundation

public enum PaceReferenceLoader {

    /// Load the bundled pace reference JSON (v1 — hyresult benchmarks).
    public static func loadBundled() throws -> PaceReference {
        guard let url = Bundle.module.url(forResource: "v1", withExtension: "json") else {
            throw PaceReferenceError.fileNotFound
        }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(PaceReference.self, from: data)
    }

    /// Load the bundled race model JSON (polynomial regression from 685K+ results).
    public static func loadRaceModel() throws -> RaceModel {
        guard let url = Bundle.module.url(forResource: "race_model", withExtension: "json") else {
            throw PaceReferenceError.fileNotFound
        }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(RaceModel.self, from: data)
    }

    /// Load a RacePredictor with both model and optional benchmark reference.
    public static func loadPredictor() throws -> RacePredictor {
        let model = try loadRaceModel()
        let reference = try? loadBundled()
        return RacePredictor(model: model, reference: reference)
    }

    /// Load the pace planner bucket data.
    public static func loadPacePlanner() throws -> PacePlanner {
        guard let url = Bundle.module.url(forResource: "pace_planner", withExtension: "json") else {
            throw PaceReferenceError.fileNotFound
        }
        let data = try Data(contentsOf: url)
        let plannerData = try JSONDecoder().decode(PacePlannerData.self, from: data)
        let reference = try? loadBundled()
        return PacePlanner(data: plannerData, reference: reference)
    }
}

public enum PaceReferenceError: Error, Sendable {
    case fileNotFound
}
