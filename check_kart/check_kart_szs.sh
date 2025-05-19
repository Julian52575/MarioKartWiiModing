#!/bin/bash

# Directory containing your .szs files
SZS_DIR="$1"
TMP_DIR="./tmp_szs_check"
ERRORS=""

rm -r "$TMP_DIR" || true 2&> /dev/null
mkdir -p "$TMP_DIR"

# Parameters:
# $1 = file_path
function checkExtracted() {
    szs_file="$1"
    extracted="$TMP_DIR/$(basename "$1")"".d"

    # Extract contents
    if ! wszst extract "$szs_file" -D "$extracted" > /dev/null 2>&1; then
        # >&2 echo "Error: Cannot extract $szs_file to $extracted"
        return
    fi
    # Extract and check all 3d models
    brres_files=$(find "$extracted" -name '*.brres')
    for brres in $brres_files; do
        brres_folder="$brres.d"
        texture_folder="$brres_folder""/Textures(NW4R)/"
        
        if ! wszst extract "$brres" -D $brres_folder > /dev/null 2>&1; then
            # >&2 echo "Error: Cannot extract $brres to $brres_folder"
            return
        fi
        # Texture size / format (bonus)
        
        if ! [ -d "$texture_folder" ]; then
            ERRORS="$ERRORS\n"" ⚠️  No $texture_folder !"
            break
        fi
        for tex in $(find "$texture_folder" -exec echo '{}' ';') ; do
            tex_size=$(stat -c%s "$tex")
            if (( $tex_size > 131072 )); then # > 1024x1024
                ERRORS="$ERRORS\n"" ⚠️  Large Texture '$(basename tex)' ($tex_size >131072 or 1024x1024)"
            fi
            if (( (($tex_size % 2)) != 0 )); then
                ERRORS="$ERRORS\n"" ⚠️  Uneven Texture size '$(basename tex)'"
            fi
        done
    done
}


COUNT=0
ERR_COUNT=0
# Iterate over each .szs file in the directory
for szs_file in "$SZS_DIR"/*.szs; do
    ERRORS=""
    FILE=$(basename "$szs_file")

    # Check file size
    file_size=$(stat -c%s "$szs_file")

    # List contents to check for mdl0 and brres
    content_list=$(wszst list-la "$szs_file")
    if ! echo "$content_list" | grep -q -i "mdl0"; then
        ERRORS="$ERRORS\n""  ❌ Missing mdl0 file"
    fi
    if ! echo "$content_list" | grep -q -i "brres"; then
        ERRORS="$ERRORS\n""  ❌ Missing brres file"
    fi
    if ! echo "$content_list" | grep -q -i "chr0"; then
        ERRORS="$ERRORS\n""  ⚠️  No animation (chr0) found"
    fi
    
    # Texture check (looks for large textures by size or suspicious formats)
    if ! echo "$content_list" | grep -Ei '\.(tex0|tpl)' > /dev/null;
    then
        # texture_files=$(echo "$content_list" | grep -Ei '\.(tex0|tpl)')
        # texture_count=$(echo "$texture_files" | wc -l)
        # echo "  📦 Found $texture_count textures"
    #else
        ERRORS="$ERRORS\n""  ⚠️  No textures found (might crash visually)"
    fi

    # Unusual file type detection
    uncommon=$(echo "$content_list" | grep -Ev '\.((brres|tex0|chr0|mdl0|tpl))' | grep -q -E '\.')
    if [ -n "$uncommon" ]; then
        ERRORS="$ERRORS\n""  ⚠️  Contains unusual file types:"
        ERRORS="$ERRORS\n""$uncommon" | sed 's/^/     • /'
    fi

    # Nested folder detection
    SZS_COUNT=$(echo "$content_list" | grep -c '/.*\.szs')
    if (( $SZS_COUNT > 1 )) ; then
        ERRORS="$ERRORS\n""⚠️  Mod might be double-packed (nested .szs)"
    fi
    
    checkExtracted $szs_file
    if ! [[ -z "${ERRORS}" ]]; then
        echo -e "$FILE"
        >&2 echo -e $ERRORS
        ERR_COUNT=$(($ERR_COUNT + 1))
    fi
    COUNT=$(($COUNT + 1))
done

>&2 echo "Found $ERR_COUNT possible invalid files out of $COUNT" 
