class MetadataUtils {
    static void checkFileExists(path, String label) {
        if (path == null || path.toString().trim().isEmpty()) {
            failWithHelpfulMessage("${label} path is required")
        }
        File file = new File(path.toString())
        if (!file.exists()) {
            failWithHelpfulMessage("${label} does not exist: ${path}")
        }
    }

    static String inferDelimiter(path) {
        String name = path.toString().toLowerCase()
        if (name.endsWith('.tsv')) {
            return '\t'
        }
        if (name.endsWith('.csv')) {
            return ','
        }
        String text = new File(path.toString()).text
        return text.count('\t') > text.count(',') ? '\t' : ','
    }

    static List<Map<String, String>> readCsvOrTsv(path) {
        String delimiter = inferDelimiter(path)
        List<String> lines = new File(path.toString()).readLines().findAll { it.size() > 0 }
        if (lines.isEmpty()) {
            return []
        }
        List<String> header = lines[0].split(delimiter, -1).collect { it.trim() }
        return lines.drop(1).collect { line ->
            List<String> values = line.split(delimiter, -1).collect { it.trim() }
            [header, values].transpose().collectEntries { key, value -> [(key): value] }
        }
    }

    static void requireColumns(List<Map<String, String>> table, List<String> requiredColumns, String tableName) {
        if (table.isEmpty()) {
            failWithHelpfulMessage("${tableName} is empty")
        }
        Set<String> columns = table[0].keySet()
        List<String> missing = requiredColumns.findAll { !columns.contains(it) }
        if (!missing.isEmpty()) {
            failWithHelpfulMessage("${tableName} is missing required columns: ${missing.join(', ')}")
        }
    }

    static String normalizeSpeciesLabel(label) {
        return label == null ? '' : label.toString().trim().replaceAll(/\s+/, '_')
    }

    static void failWithHelpfulMessage(String message) {
        throw new IllegalArgumentException("CAME metadata error: ${message}")
    }
}
