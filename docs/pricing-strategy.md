# Parrot — Pricing Strategy

## Market Analysis

Based on 17+ competitor apps in the macOS writing assistant space:

| App | Model | Price | Revenue Signal |
|---|---|---|---|
| WunderType | One-time MAS | $8.99 | Got its own domain, active development |
| Refine | One-time direct | $29 | v1.31, active releases |
| RewriteBar | One-time + credits | $29-$59 | Indie.Deals presence, testimonials |
| Stanza | Lifetime / Monthly | $14.99 / $2.99mo | "Trusted by thousands" |
| FlowWrite | Freemium subscription | $2.99-$7.99/mo | Free tier with limits |
| GrammarBot | One-time | $12 | Product Hunt launch |
| GhostEdit | Free (open source) | $0 | GitHub stars, community |
| TextWarden | Free (open source) | $0 | GitHub, active dev |
| Echoo | Free (proprietary) | $0 | Account-gated, growing features |

## Recommendation: Free + Optional Support

**Parrot should remain free and open source (MIT).** Here's why:

### Why Free Wins for Parrot

1. **Open source is a differentiator** — Only 3 of 17+ competitors are truly open source. This attracts developers, privacy advocates, and the tech community.
2. **Network effect via GitHub** — Stars, forks, and issues drive organic discovery. A paywall kills this.
3. **Competitive moat** — Your technical advantage (managed llama-server subprocess, no Ollama dependency) is hard to replicate. Monetize later if needed.
4. **Market is price-sensitive** — Most successful indie apps in this space are under $15. Users expect writing tools to be cheap or free.

### Future Monetization Options (if needed)

| Option | Pros | Cons | Effort |
|---|---|---|---|
| **Buy Me a Coffee / GitHub Sponsors** | Zero friction, community-driven | Unpredictable revenue | 1 hour |
| **Mac App Store paid version** | MAS visibility, easy payment | 30% Apple cut, sandbox constraints | 2-3 days |
| **Pro tier (custom prompts cloud sync)** | Recurring revenue, real value add | Requires backend infrastructure | 2-3 weeks |
| **Notarized DMG with suggested donation** | Respects open source ethos | Most won't pay | 1 hour |

### Recommended Path

**Phase 1 (now):** Free, open source, focus on adoption
- Build GitHub stars and community
- Get on Product Hunt, Hacker News, Reddit
- Collect testimonials and user feedback

**Phase 2 (1000+ users):** Optional support
- Add GitHub Sponsors button
- Consider MAS submission at $4.99 (convenience premium)
- Keep direct download free

**Phase 3 (10,000+ users):** Evaluate monetization
- If demand exists, consider Pro tier with iCloud sync
- Or keep free and monetize via consulting/custom builds

## Bottom Line

At this stage, **distribution beats monetization**. Every dollar spent on a paywall is a user lost to Refine, WunderType, or GhostEdit. Build the audience first, monetize later.
