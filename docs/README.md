# Documents

Typst sources and rendered PDFs for the project.

| File | What it is |
|------|-----------|
| `summer-report.typ` | Progress report for the summer semester (main document). |
| `test-scenario.typ` | Detailed Phase A/B test-scenario specification. |
| `harmonogram.typ` | Project schedule. |
| `SETUP_GUIDE.md` | Environment bootstrap guide. |

## Compiling

`summer-report.typ` and `harmonogram.typ` reference assets outside `docs/`
(`../images/`, `../SLR/`, `../loadGenTests/...`), so Typst must be given the **repo
root** as its project root via `--root`:

```bash
# from the repo root
typst compile --root . docs/summer-report.typ
typst compile --root . docs/harmonogram.typ
```

`test-scenario.typ` has no external assets and compiles on its own:

```bash
typst compile docs/test-scenario.typ
```
