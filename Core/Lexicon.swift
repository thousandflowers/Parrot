import Foundation

enum Lexicon {
    static let informalWords: Set<String> = [
        // English
        "hey", "yeah", "yep", "nope", "cool", "awesome", "gonna",
        "wanna", "gotta", "kinda", "sorta", "dunno", "lol", "omg",
        "btw", "thx", "pls", "ok", "okay", "nah", "wow", "oops",
        "xd", "haha", "lmao", "rofl", "tbh", "imo", "smh", "irl",
        "fwiw", "afaik", "idk", "nvm", "rn", "asap", "gg", "ty", "np",
        // Italian informal
        "ciao", "dai", "boh", "mah", "eh", "ah", "oh", "beh",
        "magari", "figurati", "prego", "insomma", "vabbè", "azz",
        "basta", "tipo", "roba", "mica", "mica male", "pazzesco",
        // French informal
        "ouais", "nan", "bah", "hein", "genre", "truc", "machin",
        "chelou", "ouf", "grave", "carrément", "trop", "vachement",
        "sympa", "super", "tip-top", "nickel", "cool", "wesh",
        "franchement", "franchement", "putain", "mec", "gars",
        // Spanish informal
        "tío", "tía", "guay", "mola", "venga", "dale", "oye", "pues",
        "vale", "hostia", "tronco", "macho", "colega", "joder",
        "buenas", "que tal", "genial", "brutal", "flipar", "chévere",
        // Portuguese informal
        "fixe", "giro", "bué", "tipo", "massa", "beleza", "oi", "opa",
        "poxa", "caramba", "cara", "mano", "legal", "valeu", "né",
        "pô", "eita", "nossa", "show", "tá",
        // German informal
        "krass", "geil", "mega", "moin", "tschüss", "nee", "jup",
        "boah", "äh", "ähm", "alter", "digga", "oha", "naja",
        "stimmt", "genau", "echt", "echt jetzt", "hammer",
        // Croatian informal
        "bok", "cao", "kul", "super", "hej", "jel", "šta", "kaj",
        // Danish/Norwegian informal
        "fedt", "nice", "sejt", "bare", "altså", "jo", "asså",
        "skjønner", "kult", "digg",
        // Russian informal
        "ладно", "окей", "норм", "круто", "блин", "чё", "ваще",
        "типа", "прикол", "лол", "ок",
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

    // Articulated-preposition elisions (dell', nell', all', sull', dall', coll')
    // are mandatory, register-neutral Italian grammar — NOT informal — and appear
    // constantly in formal text, so they are deliberately excluded here.
    static let informalContractionsIT: Set<String> = [
        "c'è", "c'era", "c'erano", "l'ho", "l'hai", "l'ha",
        "m'ha", "t'ho", "s'è", "n'è",
    ]

    static let informalContractionsFR: Set<String> = [
        "j'ai", "j'm", "t'as", "t'es", "c'est", "c'était", "y'a",
        "y'en a", "j'vais", "j'veux", "t'inquiète", "t'sais",
        "j'suis", "ch'uis", "i'l", "i'z", "ça",
    ]

    static let informalContractionsDE: Set<String> = [
        "ich's", "er's", "sie's", "hast du's", "hab's", "mach's",
        "gibt's", "geht's", "is'", "ham", "'nen", "'nem", "'ne",
    ]

    static let informalContractionsES: Set<String> = [
        "pa'", "pa' qué", "tó", "to'", "na'", "ca'", "d'", "m'",
        "t'", "l'", "qu'", "s'", "'tá", "'tán",
    ]

    static let informalContractionsPT: Set<String> = [
        "tô", "tá", "tão", "pra", "pro", "pros", "pras",
        "num", "numa", "nuns", "numas", "dum", "duma",
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
            // Require an actual letter (after punctuation trim) so figures like
            // "1234" don't read as shouting.
            let capsWords = rawWords.filter { raw in
                let w = raw.trimmingCharacters(in: .punctuationCharacters)
                guard w.count > 2, w.contains(where: { $0.isLetter }) else { return false }
                return w == w.uppercased()
            }
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
