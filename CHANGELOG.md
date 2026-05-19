# Parrot Changelog

## Unreleased

### Hybrid Correction Engine
- **RuleBasedEngine**: 13+ regole deterministiche per italiano (qual'è → qual è, un pò → un po', accenti, apostrofi, spaziatura multi-lingua)
- **Harper CLI**: Integrazione per English — correzioni grammaticali istantanee senza LLM
- **Pipeline ibrida**: RuleBased → Harper → LLM fallback. Correzioni istantanee quando possibile, AI quando serve
- **Source badge**: ⚡ per regole deterministiche, 🤖 per LLM, 🔀 per ibrido

### Custom Rules Engine
- Aggiungi regole personalizzate (string match o regex) per pattern specifici
- Supporto multi-lingua con filtro per lingua attiva
- Toggle enable/disable per ogni regola
- Persistenza JSON in Application Support

### Writing Coach Mode
- Modalità "Coach" con feedback strutturato: Grammar, Style, Tone, Clarity
- Shortcut `Cmd+Shift+C` dedicato
- Disponibile dal menu bar e dalle preferenze

### Direct Apply
- Shortcut `Cmd+Shift+A` per applicare correzioni senza aprire il panel
- Toast non-intrusivo con undo (5 secondi)
- NSPanel borderless a livello screenSaver+1

### Undo History
- Stack ultime 20 correzioni con persistenza JSON
- Accessibile dal panel suggerimenti
- Supporto undo/redo completo

### Onboarding
- Wizard multi-step: Accessibilità → Modello → Download → Ready
- Download modello con progresso, retry, e validazione GGUF
- Setup automatico al primo avvio

### Language Support
- Picker 90+ lingue raggruppate per area geografica
- Prompt engine aware della famiglia linguistica (RTL, CJK, Nordico, Slavo)

### Bug Fixes
- Safe optional casting per AXUIElement (NSCFType crash)
- MainActor isolation per UI state updates
- Task leak prevention con weak self
- Unicode crash fix per text replacement
- Error handling migliorato per text extraction
