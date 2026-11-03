# Version map and provenance

| Supplied directory/artifact | Role in preservation |
|---|---|
| `GoldBrain-main` | Current integrated source used for this repository; original local mirror had noGit directory |
| `GoldBrain-phase1` | Misleadingly named final worktree, not merely Phase1; latest source commit8c0fd76 dated2026-10-18 |
| Main vs phase1 | Source contents match after CRLF/LF normalization; raw byte differences are line endings. Unrelated animation helper excluded |
| `GoldBrain-github` | Older full-stack checkout ending2026-09-12; historical sourceZIP only |
| `GoldBrainFlutter` | Older standalone frontend ending2026-09-08, including Android scaffold; historical sourceZIP only |
| Backup folders | Mostly duplicate/partial intermediate copies; two unique September handoff documents retained under `docs/history/` |
| Windows1.0.1 ZIP | Historical September4 standalone Flutter client, not an October full-stack build; not the current executable release |
| Promo v1.0.0 | Historical branding/poster; not current feature-validation evidence |

The two historical sourceZIPs in the preservation release retain selected original source bytes with provenance/omission manifests. They omit duplicate audio,credentials,databases,signing identities,private Git history and generated files. Use them for reference; do not overlay old files onto the current project and assume compatibility.

The public repository starts with a new reviewed preservation commit. It does not republish private historical Git objects. `SOURCE_PROVENANCE.json` records the inspected source identity and current source-file hashes. Original developer history remains intact in the owner's local folders.

## Additional historical creative sources

[GoldBrain opening-animation Blender source and backup](../design/history/GoldBrain-opening/README.md) were recovered in the drive discovery and added on2026-11-03. They are unchanged creative references, not a verified render/build or part of the current app architecture. The supplied historical v1.0.0 promotional video is also a separate release download.
