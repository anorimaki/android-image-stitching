#!/bin/bash

set -e
set -o posix
set -o pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null && pwd)

ANDROID_SDK_ROOT="${HOME}/develop/android-sdk"
SCREENSHOT_APP="${ANDROID_SDK_ROOT}/cmdline-tools/latest/bin/screenshot2"


function usage() {
    echo "Usage: `basename $0` [options] input1 input2..."
    echo
    echo "Create a PDF from the input image files"
    echo
    echo "Options:"
    echo "  -o,--output FILE     Output directory for screenshots"
    echo "  -h,--help            Display this help message"
}


function indent() {
    sed 's/^/  /'
}


function take_screenshots() {
    local output_dir="$1"

    local index=1
    local filename
    while true; do
        echo "Press any kay to take screenshot $index, 'e' to finish,"
        read -n1 c
        if [ "$c" == 'e' ]; then
            return
        fi
        filename=$(printf "img%02d.jpg" "$index")
        "$SCREENSHOT_APP" -d "${output_dir}/${filename}"
        let index=$index+1
    done
}



output_directory="${SCRIPT_DIR}/screenshots"
input_files=()
while [ $# -ne 0 ]; do
    case "$1" in
        --help)
            usage
            exit 0
            ;;
        --tmp)
            tmp_dir="$2"
            shift 2
            ;;
        -o|--output)
            output_directory="$2"
            shift 2
            ;;
        *)
            input_files+=("$1")
            shift
            ;;
    esac
done

mkdir -p "$output_directory"

echo "- Take screenshots"
take_screenshots "$output_directory" |& indent

# echo "- Create PDF"
# "${SCRIPT_DIR}/merge.sh" --tmp "${tmp_dir}/merger" --output "$output_file" "${tmp_dir}/screenshots"/*