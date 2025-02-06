# Zotero-Obsidian Link Generator

A tool to create Obsidian-compatible links from Zotero citations. This script scans your Obsidian notes directory and automatically adds Zotero links to notes that match PDF files in your Zotero storage.

## Features

- Matches note names with Zotero PDFs using exact and fuzzy matching
- Creates `zotero://` protocol links for direct PDF access
- Dry run mode to preview changes
- Detailed logging of all operations
- Handles "et al" and other common citation text variations

## Usage

```bash
./zotero-obsidian-linker.sh [-n] <zotero_storage_path> <obsidian_notes_path>
```

### Options
- `-n, --dry-run`: Show what would be done without making changes

### Examples
```bash
# Normal run
./zotero-obsidian-linker.sh ~/Zotero/storage ~/Documents/Notes

# Dry run to preview changes
./zotero-obsidian-linker.sh -n ~/Zotero/storage ~/Documents/Notes
```

## Requirements
- zsh shell
- Zotero with local storage enabled
- Obsidian vault with markdown files