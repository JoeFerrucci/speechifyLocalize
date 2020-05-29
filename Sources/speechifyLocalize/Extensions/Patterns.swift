//
//  File.swift
//  
//
//  Created by Oleh Hudeichuk on 26.05.2020.
//

import Foundation

let LocalizableStringPattern: String = #"^\"([\s\S]+)\"\s+=\s+\"([\s\S]+)\".*;.*$"#

let PathWithSwiftExtensionPattern: String = #"^([\s\S]+)\.swift$"#

let CommentPattern: String = #"^\s*//\s*((?!MARK)[\s\S])+$"#

let MarkPattern: String = #"^\s*//\s+MARK:.+"#

let LprojNamePattern: String = #"([^/]+).lproj$"#

func stringForLocalizePattern(_ stringPrefix: String) -> String {
    "^([\\s\\S]*)\"\\s*\(stringPrefix)\\.([\\s\\S]+)\\S*?\"([\\s\\S]*)$"
}

func fileNameFromLocalizedStringPattern(_ localizedPrefix: String) -> String {
    "^.*\"([\\s\\S]+)\\.\(localizedPrefix)_\\d+.*?\"\\s+=\\s+.+"
}

func numberLocalizedString(_ localizedPrefix: String) -> String {
    "\(localizedPrefix)_(\\d+)"
}