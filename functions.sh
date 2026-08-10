#!/usr/bin/env bash

copy_with_prompt() {
    local src="$1"
    local dest="$2"
    
    # If destination is a directory and doesn't have a filename, add the source filename
    if [ -d "$dest" ] && [ -f "$src" ]; then
        # Get just the filename from src
        local filename;
        filename=$(basename "$src")
        dest="${dest%/}/$filename"  # Ensure no trailing slash before adding filename
    fi

    if [ -d "$src" ]; then
        # If it's a directory, call copy_dir_with_prompt recursively
        copy_dir_with_prompt "$src" "$dest"
    elif [ -f "$src" ]; then
        # If it's a file, call copy_file_with_prompt
        copy_file_with_prompt "$src" "$dest"
    fi
}

# Copies $src over $dest, replacing $dest even when it is a symlink.
# `cp -f` FOLLOWS a symlinked destination and writes into whatever it points at. Since `just flavour_make_symlinks` links config/current_flavour/deps.* at the flavour's own files, a parent flavour's installer (eg. community -> run_installers ember social) would otherwise overwrite the CHILD flavour's source deps.git — and the child's own copy would then no-op ("identical", same inode), silently leaving the parent's dep list in place (this is how bonfire_ui_groups/topics went missing in CI). Unlinking first keeps sources intact and lets the last writer (the flavour being installed) win.
replace_file() {
    local src="$1"
    local dest="$2"
    rm -f "$dest"
    cp -f "$src" "$dest"
}

# Function to copy file with diff and prompt
copy_file_with_prompt() {
    local src="$1"
    local dest="$2"
    local cwd;
    cwd=$(pwd)

    # Check if source and destination are the same file (compare contents, and resolve symlinks so a dest that merely POINTS at src counts as identical)
    if cmp -s "$src" "$dest"; then
        echo "Source and destination are identical, skipping: $src"
    else
        # If AUTO_YES is true, skip diffing and copy the file directly
        if [ "$AUTO_YES" = true ]; then
            replace_file "$src" "$dest"
            echo "File copied: $dest"
        else
            # Check if destination file exists
            if [ -f "$dest" ]; then
                echo "File already exists: $dest"

                # Show diff if files are different
                # if ! diff -w -q "$src" "$dest" >/dev/null 2>&1; then
                    echo "Here's the diff using $(realpath "$src" | sed "s|^$cwd/||"):"
                    if command -v colordiff >/dev/null 2>&1; then
                        colordiff -u "$dest" "$src" || true
                    else
                        diff -u "$dest" "$src" | grep -vE '^(---|\+\+\+)' | sed -e '/^@/s/^/\x1b[32m/' -e '/^-/s/^/\x1b[31m/' -e '/^+/s/^/\x1b[34m/' -e 's/$/\x1b[0m/' || true
                    fi

                    # Prompt user to confirm overwriting the file
                    read -r -p "Override existing file? (y/N) " response
                    if [[ "$response" =~ ^[Yy]$ ]]; then
                        replace_file "$src" "$dest"
                        echo "File copied: $dest"
                    else
                        echo "Skipping: $dest"
                    fi
                # else
                #     echo "Files are identical, skipping."
                # fi
            else
                replace_file "$src" "$dest"
                echo "File copied: $dest"
            fi
        fi
    fi
}


# Function to handle directory copying with prompts
copy_dir_with_prompt() {
    local src="$1"
    local dest_dir="$2"

    mkdir -p "$dest_dir"

    shopt -s nullglob
    files=("$src"/*)
    if [ ${#files[@]} -eq 0 ]; then
        echo "No files found in $src"
        return
    fi

    for src_file in "$src"/*; do
        base_name=$(basename "$src_file")
        dest_file="$dest_dir/$base_name"

        copy_with_prompt "$src_file" "$dest_file"
    done
}


# Function to copy files matching a glob pattern
copy_glob_with_prompt() {
    local src_dir="$1"
    local glob_pattern="$2"
    local dest_dir="$3"
    
    echo "Processing $glob_pattern files"
    shopt -s nullglob
    files=("$src_dir"/"$glob_pattern")
    
    if [ ${#files[@]} -eq 0 ]; then
        echo "No files found matching $glob_pattern"
        return
    fi
    
    for src_file in "$src_dir"/$glob_pattern; do
        dest_file="$dest_dir/$(basename "$src_file")"
        copy_with_prompt "$src_file" "$dest_file"
    done
}

# Function to run another installer script
run_installer() {
    local script_path="$1"
    local script_name="$2"
    
    echo "Running $script_name installer..."
    if [ -f "$script_path" ]; then
        if [ "$AUTO_YES" = true ]; then
            bash "$script_path" -y
        else
            bash "$script_path"
        fi
    else
        echo "Error: $script_name installer not found at $script_path"
        return 1
    fi
}

run_installers() {
    local dep_names=("$@")

    for dep_name in "${dep_names[@]}"; do

        # Construct the paths based on the dependency name
        local ext_path="./extensions/${dep_name}/install.sh"
        local deps_path="./deps/${dep_name}/install.sh"

        # Check if the extension installer exists and run it
        if [ -f "$ext_path" ]; then
            run_installer "$ext_path" "${dep_name}" || \
            exit 1
        elif [ -f "$deps_path" ]; then
            run_installer "$deps_path" "${dep_name}" || \
            exit 1
        else

            test -d extensions/"$dep_name" || (mkdir -p extensions && git clone https://github.com/bonfire-networks/"$dep_name" extensions/"$dep_name" || echo "Could not clone the $dep_name extension")

            run_installer "$ext_path" "${dep_name}" || \
            (echo "No installers found for dependency: $dep_name" ; exit 1)
        fi
    done
}

# Copy a flavour's own static assets (if it ships any) into the app's priv/static/
copy_flavour_static() {
    local source_dir="$1"

    if [ -d "$source_dir/priv/static/" ]; then
        echo -e "\nCopying static assets..."
        copy_dir_with_prompt "$source_dir/priv/static/" "priv/static/"
    fi
}

# Append a flavour's themes/theme.css to bonfire_ui_common's custom_themes.css (idempotent: keyed on
# the flavour name appearing in the file). No-op for flavours that don't ship a themes/theme.css.
install_flavour_themes() {
    local source_dir="$1"
    local flavour="$2"

    [ -f "$source_dir/themes/theme.css" ] || return 0

    echo -e "\nInstalling flavour themes..."

    # NOTE: don't name this loop var `path` — that's a special PATH-linked array in zsh
    local custom_themes="" candidate
    for candidate in "extensions/bonfire_ui_common/assets/css/custom_themes.css" "deps/bonfire_ui_common/assets/css/custom_themes.css"; do
        if [ -f "$candidate" ]; then
            custom_themes="$candidate"
            break
        fi
    done

    if [ -z "$custom_themes" ]; then
        echo "Warning: could not find custom_themes.css to install the $flavour themes into"
    elif grep -q "name: \"$flavour\"" "$custom_themes" 2>/dev/null; then
        echo "$flavour themes already present in $custom_themes"
    else
        echo "Appending $flavour themes to $custom_themes"
        echo "" >> "$custom_themes"
        cat "$source_dir/themes/theme.css" >> "$custom_themes"
        echo "$flavour themes installed"
    fi
}

# Function to create multiple directories
create_dirs() {
    echo "Creating directories..."
    for dir in "$@"; do
        mkdir -p "$dir"
    done
}
