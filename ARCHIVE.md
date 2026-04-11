# BananaPlayer Archive Note

## Status

This repository is archived as a minimal source snapshot for future maintenance.

- Archive date: 2026-04-11
- Git history: removed and reinitialized as a fresh repository
- Current branch: `main`
- Current state: no commits yet

## Retained Content

- Swift source code in `Sources/`
- Swift Package manifest in `Package.swift`
- Packaging script in `scripts/`
- Project notes in `release.md` and `requirements.md`

## Removed Content

- Previous `.git` history
- Local build artifacts such as `.build/`
- Packaged outputs such as `dist/`
- Editor-only settings such as `.vscode/`
- Finder metadata such as `.DS_Store`

## Resume Development

1. Review product and packaging notes in `requirements.md` and `release.md`.
2. Run `swift package resolve` if dependencies need to be restored.
3. Build or package the app again when development resumes.
4. Create the first clean commit for the archived baseline when ready.
