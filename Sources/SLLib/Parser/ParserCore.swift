//
//  ParserCore.swift
//  
//
//  Created by Oleh Hudeichuk on 12.05.2020.
//

import Foundation
import ArgumentParser

final class ParserCore {

    let parser: Parser
    private let fileManager: FileManager
    private var localizableStrings: [String: String] = .init()

    init(parser: Parser, fileManager: FileManager = .default) {
        self.parser = parser
        self.fileManager = fileManager
    }

    func run() throws {
        /// the strings files keys comparison
        checkLocalizationKeysDiff(parser.localizationPath)

        let currentStrings: [LocaleFolder] = getCurrentLocalizations(path: parser.localizationPath,
                                                                     localizedPrefix: parser.localizedPrefix)
        
        let newStrings: [LineGroup] = try findNewLocalizeStrings(parser.projectPath,
                                                                 parser.stringPrefix,
                                                                 parser.localizationPath,
                                                                 parser.localizedPrefix)

        let newFolders: [LocaleFolder] = mergeLocalizedStrings(currentStrings, newStrings)

        writeLocaleFiles(newFolders)
        replaceInsideSwiftFiles(parser.projectPath,
                                parser.localizationPath,
                                parser.localizedPrefix,
                                parser.stringPrefix,
                                parser.methodPrefix)
    }
}

// MARK: PRIVATE METHODS
extension ParserCore {

    private func replaceInsideSwiftFiles(_ projectPath: String,
                                         _ localizationPath: String,
                                         _ localizedPrefix: String,
                                         _ stringPrefix: String,
                                         _ methodPrefix: String
    ) {
        recursiveReadDirectory(path: projectPath) { (folderPath, fileURL) in
            guard let relativeFilePath: String = makeRelativePath(from: projectPath, to: fileURL.path) else { return }
            if !isValidSwiftFileName(relativeFilePath) { return }

            if folderPath != localizationPath {
                var resultText: String = .init()
                readFile(fileURL) { (str) in
                    let matches: [Int: String] = str.regexp(stringForLocalizePattern(stringPrefix))
                    if matches[0] != nil {
                        if  let beforeValue = matches[1],
                            let value = matches[2],
                            let afterValue = matches[3]
                        {
                            if let localizedKey: String = findLocalizedString(projectPath, localizedPrefix, relativeFilePath, value) {
                                let newLine = str.replace("^[\\s\\S]+$", "\(beforeValue)\"\(localizedKey)\".\(methodPrefix)\(afterValue)")
                                resultText.append(newLine)
                            }
                            return
                        }
                    }
                    resultText.append(str)
                }
                writeFile(to: fileURL.path, resultText)
                cleanFile(path: fileURL.path)
            }
        }
    }

    private func findLocalizedString(_ path: String,
                                     _ localizedPrefix: String,
                                     _ filePath: String,
                                     _ value: String
    ) -> String? {
        var result: String?
        let currentStrings: [LocaleFolder] = getCurrentLocalizations(path: parser.localizationPath,
                                                                     localizedPrefix: parser.localizedPrefix)
        let key: String = makeClearKeyFrom(path: filePath)
        if let anyLocaleFile: LocaleFile = currentStrings.first?.files.first {
            anyLocaleFile.groups.forEach { (group) in
                if result != nil { return }
                if (group.name ?? "") == key {
                    group.lines.forEach { (textLine) in
                        if result != nil { return }
                        let matches: [Int: String] = textLine.text.regexp(LocalizableStringPattern)
                        if  let localizedKey: String = matches[1],
                            let localizedValue: String = matches[2]
                        {
                            if localizedValue == value {
                                result = localizedKey
                            }
                        }
                    }
                }
            }
        }

        return result
    }

    private func writeLocaleFiles(_ folders: [LocaleFolder]) {
        folders.forEach { (localeFolder) in
            localeFolder.files.forEach { (localeFile) in
                var resultString: String = .init()
                if !fileManager.fileExists(atPath: localeFile.path) {
                    fileManager.createFile(atPath: localeFile.path, contents: nil, attributes: nil)
                }
                localeFile.groups.forEach { (group) in
                    resultString.append(group.text)
                }

                writeFile(to: localeFile.path, resultString)
                cleanFile(path: localeFile.path)
            }
        }
    }

    private func mergeLocalizedStrings(_ current: [LocaleFolder], _ new: [LineGroup]) -> [LocaleFolder] {
        var result: [LocaleFolder] = .init()
        for var localeFolder in current {
            for var localeFile in localeFolder.files {
                for var newLineGroup in new {
                    translateValue(folder: localeFolder, group: &newLineGroup)
                    if var currentLineGroup = localeFile.getGroup(by: newLineGroup.id) {
                        currentLineGroup.merge(newLineGroup)
                        localeFile.overrideGroup(currentLineGroup)
                    } else {
                        localeFile.addGroup(newLineGroup)
                    }
                }
                localeFolder.addLocaleFile(localeFile)
            }
            result.append(localeFolder)
        }

        return result
    }

    private func translateValue(folder: LocaleFolder, group: inout LineGroup) {
        guard
            let folderLang: String = folder.path.regexp(LprojNamePattern)[1]
            else { fatalError("Translate: can not parse lang name") }
        if folderLang == parser.lang { return }
        group.lines = group.lines.map { (line) -> TextLine in
            let newValue: String = (try? translate(line.getValue(),
                                                   from: parser.lang,
                                                   to: folderLang,
                                                   api: parser.googleApi,
                                                   key: parser.googlekey)) ?? ""
            if newValue.isEmpty {
                return line
            } else {
                return TextLine(number: line.number,
                                clearKey: line.getClearKey(),
                                localizedPrefix: parser.localizedPrefix,
                                value: newValue,
                                type: line.type)
            }
        }
    }

    private func findNewLocalizeStrings(_ path: String,
                                        _ stringPrefix: String,
                                        _ localizationPath: String,
                                        _ localizedPrefix: String
    ) throws -> [LineGroup] {
        var tempStore: [String: LineGroup] = .init()

        recursiveReadDirectory(path: path) { (folderPath, fileURL) in
            var filePath: String = fileURL.path
            if !isValidSwiftFileName(filePath) { return }
            if folderPath != localizationPath {
                readFile(fileURL) { (str) in
                    let line: String = str.trimmingCharacters(in: CharacterSet.init(arrayLiteral: "\n"))
                    guard let realProjectPath: String = try? realpath(path) else { return }
                    deleteProjectPath(rooPath: realProjectPath, &filePath)
                    let matches: [Int: String] = line.regexp(stringForLocalizePattern(stringPrefix))
                    if matches[0] != nil {
                        let key: String = makeClearKeyFrom(path: filePath)
                        guard let value: String = matches[2] else { return }
                        if tempStore[key] == nil {
                            tempStore[key] = .init(name: key, localizedPrefix: localizedPrefix)
                        }
                        tempStore[key]!.addNextTextLine(value: value)
                    }
                }
            }
        }

        let result: [LineGroup] = tempStore.values.map { (fileGroup) -> LineGroup in
            fileGroup
        }

        return result
    }
    
    private func deleteProjectPath(rooPath: String, _ filePath: inout String) {
        filePath.replaceSelf(rooPath, "")
    }
}
