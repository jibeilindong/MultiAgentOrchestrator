//
//  TemplateDraftSession.swift
//  Multi-Agent-Flow
//
//  Created by Codex on 2026/3/22.
//

import Foundation

struct TemplateDraftSession: Identifiable, Hashable {
    let templateID: String
    let sourceAssetURL: URL
    let draftRootURL: URL
    let openedAt: Date
    var hasUnsavedChanges: Bool
    var hasValidationErrors: Bool
    var dirtyFilePaths: [String]
    var selectedFilePath: String?
    var lastValidationState: TemplateValidationState?

    var id: String { templateID }

    init(
        templateID: String,
        sourceAssetURL: URL,
        draftRootURL: URL,
        openedAt: Date = Date(),
        hasUnsavedChanges: Bool = false,
        hasValidationErrors: Bool = false,
        dirtyFilePaths: [String] = [],
        selectedFilePath: String? = nil,
        lastValidationState: TemplateValidationState? = nil
    ) {
        self.templateID = templateID
        self.sourceAssetURL = sourceAssetURL
        self.draftRootURL = draftRootURL
        self.openedAt = openedAt
        self.hasUnsavedChanges = hasUnsavedChanges
        self.hasValidationErrors = hasValidationErrors
        self.dirtyFilePaths = dirtyFilePaths
        self.selectedFilePath = selectedFilePath
        self.lastValidationState = lastValidationState
    }
}
