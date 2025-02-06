#!/bin/zsh

# Check arguments
if [[ $# -lt 2 ]] || [[ $# -gt 3 ]] || [[ "$1" == "-h" ]] || [[ "$1" == "--help" ]]; then
    echo "Usage: $0 [-n] <zotero_storage_path> <obsidian_notes_path>"
    echo "Options:"
    echo "  -n, --dry-run    Show what would be done without making changes"
    exit 1
fi

# Parse arguments
DRY_RUN=false
if [[ "$1" == "-n" ]] || [[ "$1" == "--dry-run" ]]; then
    DRY_RUN=true
    STORAGE_PATH="$2"
    NOTES_PATH="$3"
else
    STORAGE_PATH="$1"
    NOTES_PATH="$2"
fi

# Setup logging
LOG_FILE="zotero_linker_$(date +%Y%m%d_%H%M%S).log"
exec 1> >(tee -a "$LOG_FILE")
exec 2> >(tee -a "$LOG_FILE" >&2)

# Validate paths
if [[ ! -d "$STORAGE_PATH" ]] || [[ ! -r "$STORAGE_PATH" ]]; then
    echo "Error: Cannot read from Zotero storage path: $STORAGE_PATH"
    exit 1
fi

if [[ ! -d "$NOTES_PATH" ]] || [[ ! -w "$NOTES_PATH" ]]; then
    echo "Error: Cannot write to Obsidian notes path: $NOTES_PATH"
    exit 1
fi

# Create temporary files
UNMATCHED_NOTES=$(mktemp)
MATCHED_NOTES=$(mktemp)
SKIPPED_NOTES=$(mktemp)
FUZZY_MATCHES=$(mktemp)

# Function to clean filename for comparison
clean_filename() {
    local filename="$1"
    # Convert to lowercase
    filename=$(echo "$filename" | tr '[:upper:]' '[:lower:]')
    
    # Remove 'et al'
    filename=$(echo "$filename" | sed 's/et al\.//g')
    
    # Remove anything before the first dash (authors) and the dash itself
    filename=$(echo "$filename" | sed 's/^[^-]*-*//')
    
    # Remove years (2020, etc)
    filename=$(echo "$filename" | sed 's/[12][0-9][0-9][0-9]//')
    
    # Keep only letters
    filename=$(echo "$filename" | tr -cd '[:alpha:]')
    
    # Take first 80 chars
    echo "$filename" | cut -c1-80
}

# Function to check if strings are similar
are_similar() {
    local str1="$1"
    local str2="$2"
    local minlen maxlen shorter longer
    
    # Get lengths
    local len1=${#str1}
    local len2=${#str2}
    
    # Get min and max lengths
    if [[ $len1 -lt $len2 ]]; then
        minlen=$len1
        maxlen=$len2
        shorter="$str1"
        longer="$str2"
    else
        minlen=$len2
        maxlen=$len1
        shorter="$str2"
        longer="$str1"
    fi
    
    # If lengths are too different, return false
    if [[ $minlen -lt $(( maxlen * 60 / 100 )) ]]; then
        return 1
    fi
    
    # Check if shorter is substring of longer
    if [[ "$longer" == *"$shorter"* ]]; then
        return 0
    fi
    
    # Count matching characters
    local matches=0
    for ((i = 0; i < minlen; i++)); do
        if [[ "${str1:$i:1}" == "${str2:$i:1}" ]]; then
            ((matches++))
        fi
    done
    
    # Calculate similarity percentage
    local similarity=$(( matches * 100 / maxlen ))
    
    [[ $similarity -ge 90 ]]
    return $?
}

# Function to check if line contains a Zotero link
has_zotero_link() {
    [[ $(wc -l < "$1") -ge 6 ]] && sed -n '6p' "$1" | grep -q "zotero"
}

# Function to insert link at line 6
insert_link() {
    local file="$1"
    local link="$2"
    
    if [[ "$DRY_RUN" == true ]]; then
        return 0
    fi
    
    local temp_file=$(mktemp)
    
    # Safety check: ensure file is within notes directory
    if [[ ! "$file" =~ ^"$NOTES_PATH" ]]; then
        echo "Error: Attempting to modify file outside of notes directory: $file"
        rm -f "$temp_file"
        return 1
    fi
    
    sed -n '1,5p' "$file" > "$temp_file"
    echo "$link" >> "$temp_file"
    sed -n '6,$p' "$file" >> "$temp_file"
    
    mv "$temp_file" "$file"
}

# Process each note file
total_notes=0
[[ "$DRY_RUN" == true ]] && echo "\nDRY RUN - No changes will be made"

echo "Processing notes..."

find "$NOTES_PATH" -name "*.md" -type f | while read note_file; do
    ((total_notes++))
    note_name=$(basename "$note_file" .md)
    echo -n "." > /dev/tty
    
    # Skip if note already has a Zotero link
    if has_zotero_link "$note_file"; then
        echo "$note_name" >> "$SKIPPED_NOTES"
        continue
    fi
    
    # Clean note name for comparison
    clean_note_name=$(clean_filename "$note_name")
    
    # Find matching PDF
    matching_dir=""
    matching_pdf=""
    
    # Search through storage directories
    for dir in "$STORAGE_PATH"/*/; do
        [[ ! -d "$dir" ]] && continue
        
        for pdf in "$dir"*.pdf; do
            [[ ! -f "$pdf" ]] && continue
            
            pdf_name=$(basename "$pdf" .pdf)
            clean_pdf_name=$(clean_filename "$pdf_name")
            
            # Try exact match first
            if [[ "$clean_note_name" == "$clean_pdf_name" ]]; then
                matching_dir=$(basename "$dir")
                matching_pdf="$pdf_name"
                break 2
            # Try fuzzy match if no exact match
            elif are_similar "$clean_note_name" "$clean_pdf_name"; then
                matching_dir=$(basename "$dir")
                matching_pdf="$pdf_name"
                echo "$note_name -> $pdf_name" >> "$FUZZY_MATCHES"
                break 2
            fi
        done
    done
    
    # Process match
    if [[ -n "$matching_dir" ]]; then
        echo "$note_name" >> "$MATCHED_NOTES"
        insert_link "$note_file" "[Open in Zotero](zotero://open-pdf/library/items/$matching_dir)"
    else
        echo "$note_name" >> "$UNMATCHED_NOTES"
    fi
done

echo > /dev/tty  # New line after dots

# Print summary
echo "\nSummary"
echo "----------------------------------------"
echo "Total notes found: $total_notes"
echo "Successfully matched and linked: $(wc -l < "$MATCHED_NOTES")"
echo "Already linked (skipped): $(wc -l < "$SKIPPED_NOTES")"
echo "No matches found: $(wc -l < "$UNMATCHED_NOTES")"

if [[ -s "$FUZZY_MATCHES" ]]; then
    echo "\nFuzzy Matches Made:"
    echo "----------------------------------------"
    sed 's/^/• /' "$FUZZY_MATCHES"
fi

if [[ -s "$UNMATCHED_NOTES" ]]; then
    echo "\nUnmatched Notes:"
    echo "----------------------------------------"
    sed 's/^/• /' "$UNMATCHED_NOTES"
fi

[[ "$DRY_RUN" == true ]] && echo "\nDRY RUN - No changes were made" || echo "\nProcessing complete"

# Cleanup
rm -f "$UNMATCHED_NOTES" "$MATCHED_NOTES" "$SKIPPED_NOTES" "$FUZZY_MATCHES"