#!/bin/bash

# Ensure at least one argument is provided
if [ "$#" -lt 1 ]; then
    echo "Usage: $0 <file1> <file2> ..."
    exit 1
fi

# Maximum number of simultaneous video conversions
# DNxHR conversion is highly disk and CPU intensive; you can lower this to 2 if your system struggles.
MAX_JOBS=4

# Create a function for the conversion process
convert_to_mov() {
    input_file="$1"
    input_file_name=$(basename "$input_file")
    input_file_name="${input_file_name%.*}"
    output_mov="${input_file_name}-converted.mov"

    echo "[STARTED] $input_file -> $output_mov"

    # DaVinci Resolve's preferred format: DNxHR HQ codec, YUV422p color, and PCM 16-bit audio
    # Using the global "ffmpeg" command
    ffmpeg -y -i "$input_file" -c:v dnxhd -profile:v dnxhr_hq -pix_fmt yuv422p -c:a pcm_s16le -f mov "$output_mov" </dev/null >/dev/null 2>&1

    echo "[FINISHED] $output_mov"
}

# Export the function
export -f convert_to_mov

echo "Found $# files in total."
echo "$MAX_JOBS videos will be simultaneously converted to the DNxHR format for DaVinci Resolve..."
echo "------------------------------------------------------------"

# Process all files in parallel (-P) using xargs
printf "%s\n" "$@" | xargs -n 1 -P "$MAX_JOBS" -I {} bash -c 'convert_to_mov "{}"'

echo "------------------------------------------------------------"
echo "✅ All MOV conversion processes completed successfully!"
