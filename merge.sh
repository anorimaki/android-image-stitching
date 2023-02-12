#!/bin/bash

# You can get images with take_screekshots.sh script

# Prerequisites:
# - Install hugin: flatpak install https://dl.flathub.org/repo/appstream/net.sourceforge.Hugin.flatpakref
# - Install imagemagick
# - Enable imagemagick PDF: https://stackoverflow.com/a/59193253


set -e
set -o posix
set -o pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null && pwd)
MIN_IMAGES_PER_PAGE=4
QUALITY=15


HUGIN_PTO_GEN="flatpak run --command=pto_gen net.sourceforge.Hugin"
HUGIN_PTO_LENSSTACK="flatpak run --command=pto_lensstack net.sourceforge.Hugin"
HUGIN_CPFIND="flatpak run --command=cpfind net.sourceforge.Hugin"
HUGIN_CPCLEAN="flatpak run --command=cpclean net.sourceforge.Hugin"
HUGIN_LINEFIND="flatpak run --command=linefind net.sourceforge.Hugin"
HUGIN_PTO_VAR="flatpak run --command=pto_var net.sourceforge.Hugin"
HUGIN_AUTOOPTIMISER="flatpak run --command=autooptimiser net.sourceforge.Hugin"
HUGIN_PANO_MODIFY="flatpak run --command=pano_modify net.sourceforge.Hugin"
HUGIN_HUGIN_EXECUTOR="flatpak run --command=hugin_executor net.sourceforge.Hugin"

function indent() {
    sed 's/^/  /'
}


function usage() {
    echo "Usage: `basename $0` [options] input1 input2..."
    echo
    echo "Create a PDF from the input image files"
    echo
    echo "Options:"
    echo "  -o,--output FILE         Output file"
    echo "  -l|--lines-per-page NUM  7 o 8. 7 by default."
    echo "  -h,--help                Display this help message"
}


function merge() {
    local tmp_dir="$1"
    local output="$2"
    shift 2

    if [ $# -eq 1 ]; then
        cp "$1" "$output"
        return
    fi

    rm -rf "$tmp_dir"
    mkdir -p "$tmp_dir"

    $HUGIN_PTO_GEN --projection=0 --fov=10 -o "${tmp_dir}/project.pto" "$@"

    local new_lens_param="i1"
    local i
    for i in $(seq 2 "$#"); do
        new_lens_param="${new_lens_param},i${i}"
    done    
    $HUGIN_PTO_LENSSTACK -o "${tmp_dir}/project1.pto" --new-lens "$new_lens_param" "${tmp_dir}/project.pto"

    $HUGIN_CPFIND -o "${tmp_dir}/project2.pto"  --linearmatch "${tmp_dir}/project1.pto"

    $HUGIN_CPCLEAN -o "${tmp_dir}/project3.pto" "${tmp_dir}/project2.pto"

    $HUGIN_LINEFIND -o "${tmp_dir}/project4.pto" "${tmp_dir}/project3.pto"

    #pto_var -o "${tmp_dir}/setoptim.pto" --opt r,d,e,!r0,!d0,!e0 "${tmp_dir}/project4.pto"
    $HUGIN_PTO_VAR -o "${tmp_dir}/setoptim.pto" --opt e,!e0 "${tmp_dir}/project4.pto"

    $HUGIN_AUTOOPTIMISER -n -o "${tmp_dir}/autoptim.pto" "${tmp_dir}/setoptim.pto"

    $HUGIN_PANO_MODIFY  --projection=0 --fov=AUTO --center --canvas=AUTO --crop=AUTO --ldr-file=JPG \
        -o "${tmp_dir}/autoptim2.pto" "${tmp_dir}/autoptim.pto"
        
    $HUGIN_HUGIN_EXECUTOR --stitching --prefix="${tmp_dir}/tmp" "${tmp_dir}/autoptim2.pto"

    cp "${tmp_dir}/tmp.jpg" "$output"
}


function initial_page_images() {
    local images=()
    while [ $# -gt 0 ] && [ ${#images[@]} -lt "$MIN_IMAGES_PER_PAGE" ]; do
        images+=("$1")
        shift
    done
    echo "${images[@]}"
}


function merge_images_in_pages() {
    local tmp_dir="$1"
    local pages_dir="$2"
    local max_page_image_height="$3"
    shift 3

    mkdir -p "$pages_dir"

    local page_index=0
    local images_in_current_page=()
    while [ $# -ne 0 ]; do
        if [ ${#images_in_current_page[@]} -eq 0 ]; then
            images_in_current_page=($(initial_page_images "$@"))
            shift "${#images_in_current_page[@]}"
            echo "- Merge ${images_in_current_page[@]} to page $page_index"
            merge "${tmp_dir}/merge" "${tmp_dir}/commited_page.jpg" "${images_in_current_page[@]}" |& indent
        else
            echo "- Merge ${images_in_current_page[@]} $1 to page $page_index"
            merge "${tmp_dir}/merge" "${tmp_dir}/page_under_test.jpg" "${images_in_current_page[@]}" "$1"  |& indent

            local current_page_height
            current_page_height=$(identify -ping -format '%h' "${tmp_dir}/page_under_test.jpg")
            if [ "$current_page_height" -gt "$max_page_image_height" ]; then
                echo "- Built page $page_index"
                cp "${tmp_dir}/commited_page.jpg" "${pages_dir}/page${page_index}.jpg"
                images_in_current_page=()
                page_index=$((page_index + 1))
                if [ $# -gt 1 ]; then
                    shift   # Discard this image to avoid that first image in the page repeats with the end of
                            # the previous page.
                            # This is possible because images overlap by more than 50%
                fi
            else
                echo "- Added $1 to page $page_index"
                cp "${tmp_dir}/page_under_test.jpg" "${tmp_dir}/commited_page.jpg"
                images_in_current_page+=("$1")
                shift
            fi
        fi       
    done

    echo "- Built page $page_index"
    cp "${tmp_dir}/commited_page.jpg" "${pages_dir}/page${page_index}.jpg"
}


if ! convert -version 2>&1 >/dev/null; then
    echo "convert utility cannot be found. Please install ImageMagick."
    exit -1
fi

declare -A  PAGE_HEIGHT_PER_LINES=([7]=3800 [8]=4500)

lines_per_page=7
output_file="result.pdf"
input_files=()
tmp_dir="${SCRIPT_DIR}/tmp"
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
            output_file="$2"
            shift 2
            ;;
        -l|--lines-per-page)
            lines_per_page="$2"
            shift 2
            ;;
        *)
            input_files+=("$1")
            shift
            ;;
    esac
done


if [ "${#input_files[@]}" -lt 2 ]; then
    echo "Illegal number of input files"
    usage
    exit 1
fi

max_page_height="${PAGE_HEIGHT_PER_LINES[$lines_per_page]}"
if [ -z "$max_page_height" ]; then
    echo "Unsupported $lines_per_page lines-per-page"
    usage
    exit 1
fi

rm -rf "$tmp_dir"
mkdir -p "$tmp_dir"

echo "- Build image pages ($lines_per_page lines per page)"
merge_images_in_pages "$tmp_dir" "${tmp_dir}/img_pages" "$max_page_height" "${input_files[@]}" |& indent

# Funciona bien pero el último trozo lo pone al final de la página
# convert -verbose ${tmp_dir}/img_pages/* -background white \
#   -density 72 -page a4 -format pdf -quality 40  \
#   "$output_file" |& indent

A4_HEIGHT=842
A4_WIDTH=595

page_images=(${tmp_dir}/img_pages/*.jpg)
last_page_image="${page_images[-1]}"
unset page_images[-1]

if [ "${#page_images[@]}" -gt 0 ]; then
    echo "Create PDF for all pages but last"
    convert -verbose "${page_images[@]}" -background white \
    -density 72 -page A4 -quality "$QUALITY"  \
    "${tmp_dir}/first_pages.pdf" |& indent
fi

echo "Resize the last imge to tha A4 size (keeping quality)"
width=$(identify -ping -format '%w' "${tmp_dir}/img_pages/page0.jpg")
ratio=$((width / A4_WIDTH))
last_image_height=$((A4_HEIGHT * ratio))
last_image_width=$((A4_WIDTH * ratio))
convert -verbose "$last_page_image" -resize "${last_image_width}x${last_image_height}" "${tmp_dir}/last_page_image.jpg" |& indent
last_page_image="${tmp_dir}/last_page_image.jpg"

# Create a PDF for the last page. ImageMagick places the image on the botton of the page but we 
# needed on the top.
last_page_height=$(identify -ping -format '%h' "$last_page_image")
point_to_insert_last_imge=$((A4_HEIGHT - ( last_page_height / ratio ) ))
echo "Create PDF for last page. Insert image at $point_to_insert_last_imge position (Page height: $A4_HEIGHT)"
convert -verbose "$last_page_image" -background white \
  -density 72 -page "A4+0+${point_to_insert_last_imge}" -quality "$QUALITY" \
  "${tmp_dir}/last_page.pdf" |& indent

# Join the PDFs
if [ "${#page_images[@]}" -gt 0 ]; then
    echo "Join PDFs"
    pdfunite "${tmp_dir}/first_pages.pdf" "${tmp_dir}/last_page.pdf" "$output_file" |& indent
else
    cp "${tmp_dir}/last_page.pdf" "$output_file"
fi
