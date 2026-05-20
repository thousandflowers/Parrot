import Foundation

enum Lexicon {
    static let informalWords: Set<String> = [
        "hey", "yeah", "yep", "nope", "cool", "awesome", "gonna",
        "wanna", "gotta", "kinda", "sorta", "dunno", "lol", "omg",
        "btw", "thx", "pls", "ok", "okay", "nah", "wow", "oops",
        "ciao", "eh", "ah", "oh", "xd", "haha", "lmao", "rofl",
        "tbh", "imo", "smh",
        // French informal
        "ouais", "nan", "bah", "hein", "genre", "truc", "machin",
        "chelou", "ouf", "grave", "carrément", "trop", "vachement",
        // Croatian informal
        "bok", "cao", "kul", "super", "hej", "jel", "šta", "kaj",
        // Danish informal
        "fedt", "nice", "sejt", "bare", "altså", "jo",
        // German informal
        "krass", "geil", "mega", "moin", "tschüss", "nee", "jup", "boah", "äh", "ähm",
        // Spanish informal
        "tío", "tía", "guay", "mola", "venga", "dale", "oye", "pues", "vale", "hostia",
        // Portuguese informal
        "fixe", "giro", "bué", "tipo", "massa", "beleza", "oi", "opa", "poxa", "caramba",
    ]

    static let academicWords: Set<String> = [
        "therefore", "furthermore", "consequently", "nonetheless",
        "moreover", "thus", "hence", "accordingly", "nevertheless",
        "whereas", "hereby", "therein", "thereof", "wherein",
        "pertanto", "inoltre", "dunque", "conseguentemente",
        "ciononostante", "tuttavia", "perciò", "nonostante",
        "altresì", "parimenti",
        // French academic
        "ainsi", "néanmoins", "cependant", "toutefois", "certes",
        "dès lors", "par conséquent", "en outre", "en effet",
        // Croatian academic
        "stoga", "međutim", "naime", "štoviše", "naposljetku",
        // Danish academic
        "desuden", "endvidere", "følgelig", "imidlertid", "herunder",
        "ligeledes", "dermed", "således", "henholdsvis",
        // German academic
        "daher", "folglich", "demnach", "infolgedessen", "gleichwohl",
        "demzufolge", "hingegen", "überdies", "allerdings", "dennoch",
        // Spanish academic
        "por tanto", "sin embargo", "no obstante", "asimismo",
        "por consiguiente", "en consecuencia", "dado que",
        // Portuguese academic
        "portanto", "contudo", "todavia", "entretanto", "ademais",
        "consequentemente", "nomeadamente", "outrossim",
    ]

    static let technicalWords: Set<String> = [
        "function", "variable", "api", "json", "http", "async",
        "import", "struct", "protocol", "interface", "const",
        "swift", "python", "javascript", "typescript", "kotlin",
        "boolean", "integer", "callback", "endpoint", "repository",
        "dockerfile", "kubernetes", "docker", "gradle", "webpack",
    ]

    static let informalContractionsEN: Set<String> = [
        "don't", "can't", "it's", "we're", "i'm", "you're", "they're",
        "won't", "shouldn't", "couldn't", "wouldn't", "isn't", "aren't",
        "wasn't", "weren't", "hasn't", "haven't", "hadn't", "let's",
        "that's", "what's", "who's", "here's", "there's", "he's", "she's",
        "i'll", "you'll", "he'll", "she'll", "we'll", "they'll",
        "i've", "you've", "we've", "they've", "i'd", "you'd", "he'd", "she'd",
    ]

    static let informalContractionsIT: Set<String> = [
        "dell'", "nell'", "sull'", "coll'", "all'", "dall'",
        "c'è", "c'era", "c'erano", "l'ho", "l'hai", "l'ha",
        "m'ha", "t'ho", "s'è", "n'è",
    ]

    // MARK: - Shared word-count scoring

    struct StyleScores {
        let informalScore: Double
        let academicScore: Double
        let technicalScore: Double
        let exclamationCount: Int
        let wordCount: Int
    }

    /// Pure word-count-based scoring shared between ToneDetector and ContextAnalyzer.
    static func computeWordScores(words: [String], rawWords: [String], text: String) -> StyleScores {
        let wordCount = max(words.count, 1)
        let informalCount = words.filter { informalWords.contains($0) }.count
        let singleWordAcademicCount = words.filter { academicWords.contains($0) }.count
        let phraseAcademicCount = academicWords.filter { $0.contains(" ") && text.lowercased().contains($0) }.count
        let academicCount = singleWordAcademicCount + phraseAcademicCount
        let technicalCount = words.filter { technicalWords.contains($0) }.count
        let exclamationCount = text.filter { $0 == "!" }.count
        let allCapsRatio: Double = {
            let capsWords = rawWords.filter { $0 == $0.uppercased() && $0.count > 2 }
            return Double(capsWords.count) / Double(wordCount)
        }()

        let informalScore = Double(informalCount) / Double(wordCount) * 100.0
            + Double(exclamationCount) * 5.0
            + allCapsRatio * 50.0
        let academicScore = Double(academicCount) / Double(wordCount) * 100.0
        let technicalScore = Double(technicalCount) / Double(wordCount) * 100.0

        return StyleScores(
            informalScore: informalScore,
            academicScore: academicScore,
            technicalScore: technicalScore,
            exclamationCount: exclamationCount,
            wordCount: wordCount
        )
    }
}
