//
//  Shimadzu_File_ConverterApp.swift
//  Shimadzu File Converter
//
//  Created by Zinco Verde, Inc. on 3/7/26.
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers

@main
struct Shimadzu_File_ConverterApp: App {
    var body: some Scene {
        DocumentGroup(editing: .itemDocument, migrationPlan: Shimadzu_File_ConverterMigrationPlan.self) {
            ContentView()
        }
    }
}

extension UTType {
    static var itemDocument: UTType {
        UTType(importedAs: "com.example.item-document")
    }
}

struct Shimadzu_File_ConverterMigrationPlan: SchemaMigrationPlan {
    static var schemas: [VersionedSchema.Type] = [
        Shimadzu_File_ConverterVersionedSchema.self,
    ]

    static var stages: [MigrationStage] = [
        // Stages of migration between VersionedSchema, if required.
    ]
}

struct Shimadzu_File_ConverterVersionedSchema: VersionedSchema {
    static var versionIdentifier = Schema.Version(1, 0, 0)

    static var models: [any PersistentModel.Type] = [
        Item.self,
    ]
}
