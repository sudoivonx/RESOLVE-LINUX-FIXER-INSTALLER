#!/bin/bash

# Ensure at least one argument is provided
if [ "$#" -lt 1 ]; then
    echo "Usage: $0 <file1> <file2> ..."
    exit 1
fi

# Maximum number of simultaneous video conversions
# You can adjust this based on your CPU core count (e.g., 2, 4, or 8)
MAX_JOBS=4

# Create a function for the conversion process
convert_to_mp4() {
    input_file="$1"

    # Separate the filename and extension
    input_file_name=$(basename "$input_file")
    input_file_name="${input_file_name%.*}"

    # Set the output filename
    output_mp4="${input_file_name}-converted.mp4"

    echo "[STARTED] $input_file -> $output_mp4"

    # MP4 conversion using FFmpeg
    # Calls the standard system 'ffmpeg' command instead of a hardcoded path.
    ffmpeg -y -i "$input_file" -c:v libx264 -crf 23 -preset fast -pix_fmt yuv420p -c:a aac -b:a 192k "$output_mp4" </dev/null >/dev/null 2>&1

    echo "[FINISHED] $output_mp4"
}

# Export the function so xargs can use it in parallel
export -f convert_to_mp4

echo "Found $# files in total. $MAX_JOBS videos will be converted to MP4 simultaneously..."

# Process all arguments in parallel using xargs
printf "%s\n" "$@" | xargs -n 1 -P "$MAX_JOBS" -I {} bash -c 'convert_to_mp4 "{}"'

echo "All conversion processes completed successfully!"
