import UniformTypeIdentifiers

func surveyImportTypes() -> [UTType] {
    var types: [UTType] = [.pdf, .plainText, .commaSeparatedText, .data]
    for ext in ["dxf", "sfc", "sima", "sim", "csv", "txt"] {
        if let type = UTType(filenameExtension: ext) {
            types.append(type)
        }
    }
    return types
}
