## Design Context

### Users
- **Chi**: Utente generico / tutti — chiunque scriva testi e voglia migliorarli velocemente
- **Contesto**: Uso da status bar macOS — chiamano Parrot da qualsiasi app, fanno correzione rapida, chiudono. Non un editor full-screen
- **Job to be done**: Correggere, riscrivere, verificare originalità di un testo in pochi click, senza interrompere il flusso di lavoro
- **Emozioni target**: Sicuro, affidabile, ma anche piacevole da usare — non un tool sterile

### Brand Personality
- **3+1 parole**: Creativo, Giocoso, Minimale, Caldo
- **Tono**: Amichevole ma non invadente. Professionale ma non freddo. Con personalità ma non strillato
- **Non deve sembrare**: Un pannello admin, un tool enterprise, un chatbot generico

### Aesthetic Direction
- **Tono visivo**: Utility Mac premium — pensa a Cotypist, Things 3 o Paste (app native con personalità)
- **Reference primaria**: **Cotypist** — "macraft over hype", UI nativa e pulita, copy calda e intima, si fa da parte quando non serve. Il tool non è il protagonista, lo è il flusso dell'utente
- **Tema**: Sistema (light/dark automatico), accent color di sistema
- **Materiali**: NSVisualEffectView vibrant, SF Symbols, padding generoso ma contenuto
- **Anti-reference**: Non PWA, non web wrapper, non glassmorphism, non gradienti AI purple-blue. Non sembrare un tool enterprise

### Design Principles
1. **Utility prima di tutto** — Parrot vive nella status bar. Non far aspettare. Zero attrito.
2. **Personalità nei micro-dettagli** — Non una rebranding totale, ma ogni interazione deve sentirsi intenzionale: hover, transizioni, typography
3. **Caldo ma minimale** — Colori caldi usati con parsimonia come accenti. Neutri tinti. Non esagerare.
4. **Giocoso nel movimento** — Transizioni fluide ma non lente. Spring animation misurate. Sorprendere senza stancare.
5. **Tutto deve avere una ragione** — Niente decorazione fine a se stessa. Bold = intenzionale, non rumoroso.
