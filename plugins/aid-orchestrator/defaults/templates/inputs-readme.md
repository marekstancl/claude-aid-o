# Input Files

Place sample data files here for AID to analyze during brainstorming runs.

## Supported Formats

- **PDF** — AID detects page count, language, and document structure
- **CSV** — AID reads headers, counts rows, and shows a sample
- **JSON** — AID detects schema structure and top-level keys
- **Images** (PNG, JPG, etc.) — AID describes visual content
- **Other text files** — AID notes filename and size

## How It Works

When you run `/aid-plan brainstorm`, AID automatically scans this directory and presents a summary of found files. This helps AID understand your data and ask better questions.

## Notes

- Files here are **read-only** — AID never modifies or moves them
- You can also point AID to files outside this directory during brainstorming
- Maximum 10 files are analyzed per run
- This directory is created by `/aid-init`
