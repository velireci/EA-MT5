# Nisja e projektit XAUUSD

Kjo paketë përmban udhëzime, gjendjen fillestare, task-un e parë dhe përgjigjet origjinale të klientit. Kodi i robotit do të shkruhet në hapin e ardhshëm.

## Si e përdor

1. Nxirre ZIP-in në një dosje të re, p.sh. `xauusd-robot`. Hap dosjen që përmban drejtpërdrejt `CLAUDE.md` dhe `AGENTS.md` në Claude Code. Mos mbishkruaj një projekt ekzistues pa krahasuar skedarët.
2. Mbaje të njëjtën dosje edhe për Codex. Nëse punoni në kompjuterë të ndryshëm, shkëmbeni versionin e ruajtur ose përdorni repository privat. Një mjet duhet të përfundojë ndryshimet përpara se tjetri të shkruajë.
3. Claude Code lexon `CLAUDE.md`, i cili importon udhëzimet e përbashkëta `AGENTS.md`. Codex përdor `AGENTS.md`. Hap një sesion të ri pasi t'i vendosësh skedarët që udhëzimet të ngarkohen nga fillimi.
4. Nis me task-un T001 duke përdorur mesazhin më poshtë.
5. Pas çdo hapi, `docs/STATE.md` tregon çfarë u bë, çfarë u testua dhe çfarë duhet më tej. Nuk ka nevojë ta kopjosh gjithë bisedën.

## Mesazhi i parë për Claude Code

Lexo udhëzimet e projektit dhe docs/STATE.md. Implemento vetëm tasks/T001-foundation.md. Puno drejtpërdrejt për pjesët e thjeshta; përdor një agjent vetëm për një detyrë të kufizuar kur kjo ndihmon. Mos shpik rregulla tregtimi. Në fund regjistro evidencën e kompilimit dhe testimit dhe përditëso docs/STATE.md. Ndalo te përfundimi i këtij task-u për rishikim.

## Mesazhi për Codex pas hapit të parë

Lexo AGENTS.md dhe docs/STATE.md. Rishiko implementimin e tasks/T001-foundation.md dhe raportin e verifikimit. Kontrollo leximin e timeframe-eve, candles e mbyllura/formuese, gatishmërinë e historikut dhe mungesën e veprimeve të tregtimit. Raporto gabimet konkrete dhe kontrollet pa evidencë; mos ndrysho kodin gjatë këtij rishikimi.

## Ndarja e punës sipas modelit

| Punë | Zgjedhje e propozuar | Roli |
|---|---|---|
| Nxjerrje faktesh ose kërkim i një përgjigjeje në dokumente | Haiku | evidence-reader, vetëm lexim |
| Ndërtim dhe korrigjime të zakonshme MQL5 | Sonnet | Agjenti kryesor ose mql5-builder |
| Paqartësi të vështira, risk/ekzekutim dhe rishikim kritik | Opus | strategy-reviewer, vetëm lexim |
| Rishikim i pavarur i specifikimit/kodit dhe rezultateve | Codex | Modeli që ke zgjedhur në aplikacion; forcë arsyetimi sipas vështirësisë |

Këto janë zgjedhje pune, jo garanci se një model do të ketë rezultat më të mirë në çdo detyrë. Agjentët e Claude janë te `.claude/agents/` dhe kanë alias-et e modeleve në konfigurim. Kontrollo disponueshmërinë dhe modelin që po përdoret në instalimin tënd; mund t'i ndryshosh ose të përdorësh `inherit`.

Skedarët CLAUDE.md dhe AGENTS.md nuk bëjnë kalim automatik mes Claude Code dhe Codex. Dorëzimi realizohet me të njëjtët skedarë/version dhe task-un e qartë që i jep mjetit përkatës. Agjentët brenda Claude Code janë të veçantë nga Codex.

## Si kursejmë kontekstin

- Udhëzimet e përhershme janë të shkurtra. Detajet lexohen vetëm për task-un aktual.
- Në fillim lexohet gjendja e fundit dhe task-u; dokumentet e klientit nuk ri-ngarkohen të gjitha çdo herë.
- Një implementim dhe një rishikim i fokusuar zakonisht mjaftojnë për një hap.
- Modelet më të vogla mund të ulin koston, por nuk ulin domosdoshmërisht numrin e tokens. Agjentët shtesë kanë kontekst dhe përgjigje shtesë.
- Mos importo me `@` dokumentet e gjata te CLAUDE.md: importi i ngarkon në kontekst. Mbaji si referenca për lexim sipas nevojës.

## Dokumentacioni i verifikuar

- [Codex: AGENTS.md](https://learn.chatgpt.com/docs/agent-configuration/agents-md)
- [Claude Code: memoria dhe importet](https://code.claude.com/docs/en/memory)
- [Claude Code: subagents dhe model](https://code.claude.com/docs/en/sub-agents)

Konfigurimi është përgatitur sipas këtyre dokumenteve; ende nuk është provuar duke nisur agjentët në instalimin tënd të Claude Code. Përdorimi i MT5/MetaEditor verifikohet në T001. Paketa përmban informacionin e klientit: mbaje projektin privat.
