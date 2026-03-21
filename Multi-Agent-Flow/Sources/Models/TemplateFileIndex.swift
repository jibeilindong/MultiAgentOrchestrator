//
//  TemplateFileIndex.swift
//  Multi-Agent-Flow
//
//  Created by Codex on 2026/3/22.
//

import Foundation

enum TemplateFileNodeKind: String, Hashable {
    case directory
    case markdown
    case json
    case other
}

enum TemplateFileNodeCategory: String, Hashable {
    case structure
    case soul
    case support
    case systemManaged
    case extensionSupport
    case revision
}

struct TemplateFileNode: Identifiable, Hashable {
    let relativePath: String
    let displayName: String
    let kind: TemplateFileNodeKind
    let category: TemplateFileNodeCategory
    let isRequired: Bool
    let isEditable: Bool
    let isSystemManaged: Bool
    let isPresent: Bool
    let isDirty: Bool
    let children: [TemplateFileNode]

    var id: String { relativePath }
    var isDirectory: Bool { kind == .directory }

    func findNode(relativePath: String) -> TemplateFileNode? {
        if self.relativePath == relativePath {
            return self
        }

        for child in children {
            if let match = child.findNode(relativePath: relativePath) {
                return match
            }
        }

        return nil
    }

    var flattenedNodes: [TemplateFileNode] {
        [self] + children.flatMap(\.flattenedNodes)
    }
}

struct TemplateFileIndex: Hashable {
    let rootDirectoryURL: URL
    let nodes: [TemplateFileNode]

    func node(relativePath: String) -> TemplateFileNode? {
        for node in nodes {
            if let match = node.findNode(relativePath: relativePath) {
                return match
            }
        }
        return nil
    }

    var flattenedNodes: [TemplateFileNode] {
        nodes.flatMap(\.flattenedNodes)
    }
}
