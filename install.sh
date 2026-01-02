#!/bin/bash

# Exit on any error
set -e

FLAVOUR="community"

# Get the script's directory
SOURCE_DIR="$(cd "$(dirname "$0")" && pwd)"

# Source the functions file
source "$(dirname "$0")/functions.sh"

# Parse command line arguments
AUTO_YES=${AUTO_YES:-false}
for arg in "$@"; do
    case $arg in
        -y|--yes)
            echo "Existing files will be overridden without prompting"
            export AUTO_YES=true
            shift
            ;;
    esac
done


# Show mode
if [ "$AUTO_YES" = true ]; then
    echo "Running in automatic override mode (-y flag detected)"
fi

echo -e "\nInstalling flavour(s) this one depends on first..."
run_installers ember social || exit 1

echo -e "\nCreating directories..."
create_dirs "lib/" "config/current_flavour/"

echo -e "\nCopying deps files..."
copy_glob_with_prompt "$SOURCE_DIR" "deps.*" "config/current_flavour/"

echo -e "\nCopying flavour config"
copy_with_prompt "$SOURCE_DIR/config/$FLAVOUR.exs" "config/"

echo -e "\nCopying DB migrations"
copy_dir_with_prompt "$SOURCE_DIR/priv/repo/" "priv/repo/"

echo -e "\nCopying custom templates..."
copy_dir_with_prompt "$SOURCE_DIR/priv/templates/lib/" "lib/"

echo -e "\n$FLAVOUR installation complete!"
