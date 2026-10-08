#!/bin/bash
#
# Finder hands this script the selected files and folders. It works out which
# of them SIPS can read, asks the conversion window which format to write, and
# saves each converted copy beside its original.
#
# macOS still ships Bash 3.2 as /bin/bash, so this file avoids associative
# arrays, mapfile, and case-changing expansions.

set -u

# Each tool can be swapped through the environment. The tests rely on this to
# run the whole flow with stand-ins on machines that have no SIPS at all. The
# Finder actions start this script with a cleared environment, so these
# overrides cannot be set for them from outside.
SIPS="${SIPS_BIN:-/usr/bin/sips}"
OSASCRIPT="${OSASCRIPT_BIN:-/usr/bin/osascript}"
LOG_DIR="${HOME:-/tmp}/Library/Logs/Scrippy"
LOG_FILE="$LOG_DIR/scrippy.log"

# A log larger than this is cut back to its most recent half before a run adds
# to it, so a Mac that converts every day never collects megabytes of history.
LOG_LIMIT_BYTES=1048576

# Scrippy.app is looked for in two fixed places only. Searching Spotlight for
# its bundle identifier would also find any other program claiming that
# identifier, and this script would then run it. /Applications needs an
# administrator to write to, so a copy moved there is as trustworthy as the
# one the installer placed in the person's own Applications folder.
find_app() {
  local bundle
  if [[ -n "${SCRIPPY_APP:-}" ]]; then
    bundle="$SCRIPPY_APP"
  elif [[ -x "${HOME}/Applications/Scrippy.app/Contents/MacOS/Scrippy" ]]; then
    bundle="${HOME}/Applications/Scrippy.app"
  else
    bundle="/Applications/Scrippy.app"
  fi
  if [[ -x "$bundle/Contents/MacOS/Scrippy" ]]; then
    printf '%s' "$bundle/Contents/MacOS/Scrippy"
  fi
}
UI_HELPER="$(find_app)"

if [[ ! -x "$SIPS" ]]; then
  "$OSASCRIPT" -e 'display alert "Scrippy" message "The image conversion tool built into macOS is not available on this Mac." as critical'
  exit 1
fi

# The one-step Finder actions, such as Convert to JPEG with Scrippy, pass
# "--to FORMAT" ahead of the selection and skip the window. Finder only ever
# passes absolute paths, so a selected file can never be mistaken for it.
direct_format=""
if [[ "${1:-}" == "--to" ]]; then
  direct_format="${2:-}"
  shift
  [[ $# -gt 0 ]] && shift
fi

# Finder can run a Quick Action with nothing selected. There is nothing to do.
if [[ $# -eq 0 ]]; then
  exit 0
fi

WORK_DIR="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/scrippy.XXXXXX")" || exit 1
READABLE_FILE="$WORK_DIR/readable.txt"
SEEN_FILE="$WORK_DIR/seen.txt"
SKIPPED_FILE="$WORK_DIR/skipped.txt"
SOURCE_FORMATS_FILE="$WORK_DIR/source-formats.txt"
FORMATS_FILE="$WORK_DIR/formats.tsv"
CHOICES_FILE="$WORK_DIR/choices.tsv"
QUALITY_CHOICES_FILE="$WORK_DIR/quality-choices.tsv"
ERRORS_FILE="$WORK_DIR/errors.txt"
CONVERT_PROGRESS_FILE="$WORK_DIR/convert-progress.tsv"
CONVERT_DONE_FILE="$WORK_DIR/convert.done"
# The progress window creates this file when the person clicks Stop.
STOP_FILE="$WORK_DIR/stop.request"
convert_progress_pid=""
stage_dir=""

/bin/mkdir -p "$LOG_DIR" 2>/dev/null || true

# shellcheck disable=SC2329  # Called through the trap below.
cleanup() {
  # The progress window watches for this file. Creating it first lets the
  # window close on its own even when the script is interrupted.
  : > "$CONVERT_DONE_FILE" 2>/dev/null || true
  if [[ -n "$convert_progress_pid" ]]; then
    kill "$convert_progress_pid" >/dev/null 2>&1 || true
  fi
  # A staging folder sits beside the person's images, so one left behind by
  # an interrupted run would be visible clutter in their own folder.
  if [[ -n "$stage_dir" ]]; then
    /bin/rm -rf "$stage_dir"
  fi
  /bin/rm -rf "$WORK_DIR"
}

# Finder can stop a Quick Action midway, so the work folder and the progress
# window are cleaned up on every way the script can end.
trap cleanup EXIT HUP INT TERM

# Every list starts empty so a count of lines is a count of files, even for
# lists that never receive an entry.

: > "$READABLE_FILE"
: > "$SEEN_FILE"
: > "$SKIPPED_FILE"
: > "$SOURCE_FORMATS_FILE"
: > "$FORMATS_FILE"
: > "$CHOICES_FILE"
: > "$QUALITY_CHOICES_FILE"
: > "$ERRORS_FILE"

# Log failures are diagnostic, never fatal. A log that cannot be written must
# not stop a conversion that would otherwise succeed.
log_line() {
  printf '%s  %s\n' "$(/bin/date '+%Y-%m-%d %H:%M:%S')" "$1" >> "$LOG_FILE" 2>/dev/null || true
}

trim_log() {
  [[ -f "$LOG_FILE" ]] || return 0
  local size
  size="$(file_size_bytes "$LOG_FILE")"
  if [[ "$size" -gt "$LOG_LIMIT_BYTES" ]]; then
    /usr/bin/tail -c $((LOG_LIMIT_BYTES / 2)) "$LOG_FILE" > "$WORK_DIR/log.tmp" 2>/dev/null \
      && /bin/mv "$WORK_DIR/log.tmp" "$LOG_FILE"
  fi
}

# Turns the short names SIPS uses into the names people see in the menu. A few
# formats have no extension in `sips --formats` and appear only as a type
# identifier, so those are read from the identifier instead.
format_label() {
  local ext="$1"
  local uti="${2:-}"
  case "$ext" in
    jpeg|jpg) printf '%s' "JPEG" ;;
    tiff|tif) printf '%s' "TIFF" ;;
    jp2) printf '%s' "JPEG 2000" ;;
    heic) printf '%s' "HEIC" ;;
    heics) printf '%s' "HEICS" ;;
    avif) printf '%s' "AVIF" ;;
    png) printf '%s' "PNG" ;;
    gif) printf '%s' "GIF" ;;
    bmp) printf '%s' "BMP" ;;
    psd) printf '%s' "PSD" ;;
    pdf) printf '%s' "PDF" ;;
    ico) printf '%s' "ICO" ;;
    icns) printf '%s' "ICNS" ;;
    tga) printf '%s' "TGA" ;;
    exr) printf '%s' "EXR" ;;
    dds) printf '%s' "DDS" ;;
    pbm) printf '%s' "PBM" ;;
    pvr) printf '%s' "PVR" ;;
    ktx) printf '%s' "KTX" ;;
    ktx2) printf '%s' "KTX2" ;;
    astc) printf '%s' "ASTC" ;;
    atx) printf '%s' "ATX" ;;
    --)
      case "$uti" in
        *astc*) printf '%s' "ASTC" ;;
        *ktx2*) printf '%s' "KTX2" ;;
        *atx*) printf '%s' "ATX" ;;
        *) printf '%s' "${uti##*.}" | /usr/bin/tr '[:lower:]' '[:upper:]' ;;
      esac
      ;;
    *) printf '%s' "$ext" | /usr/bin/tr '[:lower:]' '[:upper:]' ;;
  esac
}

# The extension given to a converted copy. JPEG and TIFF use their short,
# more familiar spellings. A format known only by type identifier borrows the
# last part of that identifier, cleaned so it is safe in a filename.
output_suffix() {
  local ext="$1"
  local uti="$2"
  case "$ext" in
    jpeg) printf '%s' "jpg" ;;
    tiff) printf '%s' "tif" ;;
    --)
      local tail="${uti##*.}"
      tail="${tail%-image}"
      tail="${tail//[^A-Za-z0-9_-]/}"
      [[ -z "$tail" ]] && tail="image"
      printf '%s' "$tail"
      ;;
    *) printf '%s' "$ext" ;;
  esac
}

# BSD stat on macOS and GNU stat elsewhere disagree on flags, so both are
# tried before falling back to counting bytes.
file_size_bytes() {
  local path="$1"
  local size=""
  size="$(/usr/bin/stat -f%z "$path" 2>/dev/null || true)"
  if [[ ! "$size" =~ ^[0-9]+$ ]]; then
    size="$(/usr/bin/stat -c%s "$path" 2>/dev/null || true)"
  fi
  if [[ ! "$size" =~ ^[0-9]+$ ]]; then
    size="$(/usr/bin/wc -c < "$path" | /usr/bin/tr -d ' ')"
  fi
  printf '%s' "$size"
}

human_size() {
  /usr/bin/awk -v bytes="$1" 'BEGIN {
    if (bytes < 1024) printf "%d B", bytes;
    else if (bytes < 1048576) printf "%.1f KB", bytes / 1024;
    else if (bytes < 1073741824) printf "%.1f MB", bytes / 1048576;
    else printf "%.2f GB", bytes / 1073741824;
  }'
}

# Sets BENEFIT and TRADEOFF for the summary card. Globals are used because
# Bash 3.2 has no clean way to return two strings from one function.
BENEFIT=""
TRADEOFF=""
set_tradeoff() {
  local target="$1"
  local source="$2"
  case "$target" in
    "JPEG")
      BENEFIT="Usually smaller than $source for photos and widely supported."
      TRADEOFF="Lossy and cannot keep transparency. Fine detail can change."
      ;;
    "PNG")
      BENEFIT="No lossy compression and can keep transparency."
      TRADEOFF="Often larger than JPEG, HEIC, or AVIF. Lost detail from $source cannot be restored."
      ;;
    "HEIC"|"HEICS")
      BENEFIT="Often smaller than $source for photos while keeping strong visible detail."
      TRADEOFF="Some older apps, websites, and non-Apple devices may not accept it."
      ;;
    "AVIF")
      BENEFIT="Often very small for photos and can keep transparency."
      TRADEOFF="Some older apps and services may not open it."
      ;;
    "TIFF")
      BENEFIT="Editing and archival work where file size matters less."
      TRADEOFF="Usually much larger than $source."
      ;;
    "JPEG 2000")
      BENEFIT="Compressed images when another app specifically supports JPEG 2000."
      TRADEOFF="Far less widely supported than JPEG or PNG."
      ;;
    "GIF")
      BENEFIT="Simple graphics with few colors."
      TRADEOFF="Limited to 256 colors. Photos may look worse, and Scrippy does not create animation."
      ;;
    "BMP")
      BENEFIT="Compatibility with older bitmap tools."
      TRADEOFF="Usually large and uncommon for modern sharing."
      ;;
    "PDF")
      BENEFIT="Putting the image into a document-style file."
      TRADEOFF="Image apps and websites may treat PDF differently from image files."
      ;;
    "PSD")
      BENEFIT="Opening the copy in Photoshop or another PSD-aware app."
      TRADEOFF="SIPS creates a flat image, not editable layers, and the file may be larger than $source."
      ;;
    "EXR")
      BENEFIT="Professional graphics work that needs high dynamic range."
      TRADEOFF="Files can be large, and ordinary photo apps may not support EXR."
      ;;
    "ICO"|"ICNS")
      BENEFIT="Icon work that specifically needs $target."
      TRADEOFF="Not intended for normal photos or screenshots."
      ;;
    "ASTC"|"ATX"|"DDS"|"KTX"|"KTX2"|"PVR")
      BENEFIT="Graphics or texture work that specifically needs $target."
      TRADEOFF="Specialized format. Ordinary photo apps may not open it."
      ;;
    "PBM")
      BENEFIT="Simple bitmap data and some technical work."
      TRADEOFF="Not practical for most photos, screenshots, or web use."
      ;;
    "TGA")
      BENEFIT="Some graphics, game, and video work."
      TRADEOFF="Less common for everyday use and can be larger than modern photo formats."
      ;;
    *)
      BENEFIT="Work that specifically requires $target."
      TRADEOFF="App support and file size vary. Keep the original until you check the new copy."
      ;;
  esac
  # Converting to the same type is allowed, since it is a way to recompress,
  # but the general advice above would be misleading for it.
  if [[ "$target" == "$source" ]]; then
    BENEFIT="Keeps the same file type while creating a new copy."
    TRADEOFF="Saving again can still change file size or image detail."
  fi
}

source_total_bytes=0
representative_size=0
representative_path=""
folder_count=0

# Records one file if SIPS can read it. A file the person picked directly is
# reported when it cannot be read. A file found inside a folder is skipped
# quietly, because folders routinely hold documents and other non-images.
add_candidate() {
  local candidate="$1"
  local origin="$2"
  # Every list here holds one path per line, so a name containing a line break
  # would be read back as two paths, the second of which could name a
  # different file. Such names are skipped and reported instead.
  case "$candidate" in
    *$'\n'*)
      [[ "$origin" == "explicit" ]] && printf '%s\n' "(a file whose name contains a line break)" >> "$SKIPPED_FILE"
      return
      ;;
  esac
  [[ -f "$candidate" ]] || return
  # Selecting a folder and a file inside it would otherwise convert that file
  # twice. Paths from Finder are absolute, so a plain text match is enough.
  if /usr/bin/grep -Fxq -- "$candidate" "$SEEN_FILE" 2>/dev/null; then
    return
  fi
  printf '%s\n' "$candidate" >> "$SEEN_FILE"

  local query_output query_status source_format source_label bytes
  query_output="$("$SIPS" -g format "$candidate" 2>&1)"
  query_status=$?
  # SIPS can exit cleanly on a file it does not understand, so success also
  # requires the format line in its output.
  if [[ $query_status -eq 0 ]] && printf '%s\n' "$query_output" | /usr/bin/grep -q 'format:'; then
    source_format="$(printf '%s\n' "$query_output" | /usr/bin/awk -F': *' '/format:/ {print $2; exit}')"
    source_label="$(format_label "$source_format" "$source_format")"
    printf '%s\n' "$candidate" >> "$READABLE_FILE"
    printf '%s\n' "$source_label" >> "$SOURCE_FORMATS_FILE"
    bytes="$(file_size_bytes "$candidate")"
    source_total_bytes=$((source_total_bytes + bytes))
    # The largest file stands in for the whole group when the window
    # estimates output size. It is the one most likely to show a real
    # difference between settings.
    if [[ "$bytes" -gt "$representative_size" ]]; then
      representative_size="$bytes"
      representative_path="$candidate"
    fi
  elif [[ "$origin" == "explicit" ]]; then
    printf '%s\n' "$candidate" >> "$SKIPPED_FILE"
  fi
}

# Folders are read one level deep on purpose. Converting everything below a
# folder could reach far more files than the person expected to touch.
# nullglob turns an empty folder into no iterations rather than one pass over
# the literal pattern text.
shopt -s nullglob
for input_path in "$@"; do
  # Finder always passes absolute paths. Anyone running the script by hand
  # might not, and a relative name beginning with a dash would reach SIPS
  # looking like an option, so every path is made absolute first.
  [[ "$input_path" == /* ]] || input_path="$PWD/$input_path"
  if [[ -d "$input_path" ]]; then
    folder_count=$((folder_count + 1))
    for candidate in "$input_path"/*; do
      [[ -f "$candidate" ]] && add_candidate "$candidate" "folder"
    done
  elif [[ -f "$input_path" ]]; then
    add_candidate "$input_path" "explicit"
  else
    case "$input_path" in
      *$'\n'*) printf '%s\n' "(a file whose name contains a line break)" >> "$SKIPPED_FILE" ;;
      *) printf '%s\n' "$input_path" >> "$SKIPPED_FILE" ;;
    esac
  fi
done
shopt -u nullglob

readable_count="$(/usr/bin/wc -l < "$READABLE_FILE" | /usr/bin/tr -d ' ')"
skipped_count="$(/usr/bin/wc -l < "$SKIPPED_FILE" | /usr/bin/tr -d ' ')"

# Every AppleScript below is a quoted heredoc that receives its values as
# arguments. File names and counts never become part of the script text, so a
# name containing quotes cannot change what the script does.
if [[ "$readable_count" -eq 0 ]]; then
  "$OSASCRIPT" - "$folder_count" <<'APPLESCRIPT'
on run argv
  set folderCount to (item 1 of argv) as integer
  if folderCount > 0 then
    display alert "No images found" message "SIPS could not read any image files directly inside the selected folder. Files inside subfolders are not included." as warning
  else
    display alert "This file cannot be converted" message "SIPS cannot read the selected file." as warning
  end if
end run
APPLESCRIPT
  exit 0
fi

# Saying so before the window opens lets the person back out of a batch that
# is not what they meant to select.
if [[ "$skipped_count" -gt 0 ]]; then
  if ! "$OSASCRIPT" - "$readable_count" "$skipped_count" <<'APPLESCRIPT'
on run argv
  set readableCount to item 1 of argv
  set skippedCount to item 2 of argv
  if skippedCount is "1" then
    set skippedText to "1 selected file cannot be read by SIPS."
  else
    set skippedText to skippedCount & " selected files cannot be read by SIPS."
  end if
  if readableCount is "1" then
    set readableText to "1 image can still be converted."
  else
    set readableText to readableCount & " images can still be converted."
  end if
  display dialog skippedText & "\n\n" & readableText with title "Some selected files will be skipped" buttons {"Cancel", "Continue"} default button "Continue" cancel button "Cancel" with icon caution
end run
APPLESCRIPT
  then
    exit 0
  fi
fi

# The menu is built from what this Mac reports it can write, rather than a
# fixed list, so new formats in a macOS update appear without a new release.
# Each line of `sips --formats` reads: type identifier, extension (or "--"
# when there is none), then Readable and Writable flags.
while read -r uti ext marker remainder; do
  [[ -z "${uti:-}" ]] && continue
  [[ "$uti" == "Supported" ]] && continue
  [[ "$uti" == "-------------------------------------------" ]] && continue
  [[ "${marker:-}" != "Writable" && "${remainder:-}" != *"Writable"* ]] && continue

  format_arg="$ext"
  [[ "$ext" == "--" ]] && format_arg="$uti"
  suffix="$(output_suffix "$ext" "$uti")"
  label="$(format_label "$ext" "$uti")"
  printf '%s\t%s\t%s\t%s\n' "$format_arg" "$label" "$suffix" "$uti" >> "$FORMATS_FILE"
# Process substitution rather than a pipe keeps the loop in this shell, which
# matters if it ever needs to set a variable that outlives the loop.
done < <("$SIPS" --formats 2>/dev/null)

if [[ ! -s "$FORMATS_FILE" ]]; then
  "$OSASCRIPT" -e 'display alert "No output formats are available" message "SIPS did not report any image formats it can write on this Mac." as critical'
  exit 1
fi

# Some formats are listed under more than one identifier. Keeping one row per
# label stops the menu from showing the same name twice.
LC_ALL=C /usr/bin/sort -t $'\t' -k2,2f -u "$FORMATS_FILE" -o "$FORMATS_FILE"

# The formats most people want come first, in a fixed order, and the window
# sets them apart from the rest with a separator. Everything else follows
# alphabetically. A rank column is added for sorting and then removed.
COMMON_FORMATS="JPEG PNG HEIC AVIF TIFF PDF"
/usr/bin/awk -F '\t' -v common="$COMMON_FORMATS" 'BEGIN {
    OFS = "\t"
    n = split(common, names, " ")
    for (i = 1; i <= n; i++) rank[names[i]] = sprintf("0%02d", i)
  }
  { print (($2 in rank) ? rank[$2] : "1"), $0 }' "$FORMATS_FILE" \
  | LC_ALL=C /usr/bin/sort -t $'\t' -k1,1 -k3,3f \
  | /usr/bin/cut -f2- > "$WORK_DIR/formats-ranked.tsv"
/bin/mv "$WORK_DIR/formats-ranked.tsv" "$FORMATS_FILE"
# LC_ALL=C gives the same order on every Mac, whatever its language setting.
unique_source_count="$(LC_ALL=C /usr/bin/sort -u "$SOURCE_FORMATS_FILE" | /usr/bin/wc -l | /usr/bin/tr -d ' ')"
if [[ "$unique_source_count" -eq 1 ]]; then
  source_name="$(LC_ALL=C /usr/bin/sort -u "$SOURCE_FORMATS_FILE" | /usr/bin/head -n 1)"
else
  source_name="the selected image types"
fi
source_size_display="$(human_size "$source_total_bytes")"

while IFS=$'\t' read -r format_arg label suffix uti; do
  set_tradeoff "$label" "$source_name"
  group="other"
  case " $COMMON_FORMATS " in
    *" $label "*) group="common" ;;
  esac
  printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$format_arg" "$label" "$suffix" "$BENEFIT" "$TRADEOFF" "$group" >> "$CHOICES_FILE"

  # Only lossy formats get the detail menu. SIPS reads the number as a
  # quality percentage, and "auto" leaves its own default in place.
  case "$format_arg" in
    jpeg|heic|heics|avif|jp2)
      quality_specs=("auto|Automatic" "60|Smaller file" "75|Balanced" "85|High quality" "90|Very high quality" "95|Highest detail")
      for spec in "${quality_specs[@]}"; do
        key="${spec%%|*}"
        title="${spec#*|}"
        case "$key" in
          auto)
            q_good="Uses the standard SIPS compression setting."
            q_tradeoff="File size can vary more."
            ;;
          60)
            q_good="Makes the smallest files among these choices."
            q_tradeoff="Fine detail may look softer."
            ;;
          75)
            q_good="Balances detail and file size for everyday use."
            q_tradeoff="Some fine detail may be reduced."
            ;;
          85)
            q_good="Keeps more detail without the largest files."
            q_tradeoff="Usually larger than Balanced."
            ;;
          90)
            q_good="Keeps high detail when file size matters less."
            q_tradeoff="Files are larger and gains may be subtle."
            ;;
          95)
            q_good="Keeps the most detail among these choices."
            q_tradeoff="Usually the largest file. Gains over 90 percent may be hard to see."
            ;;
        esac
        printf '%s\t%s\t%s\t%s\t%s\n' "$format_arg" "$key" "$title" "$q_good" "$q_tradeoff" >> "$QUALITY_CHOICES_FILE"
      done
      ;;
  esac
done < "$FORMATS_FILE"

# The caption under the preview describes the picture shown. For one image
# that is its format, pixel size, and file size. For several it says which
# one the preview shows, since the window can only show one.
image_dimensions() {
  local output width height
  output="$("$SIPS" -g pixelWidth -g pixelHeight "$1" 2>/dev/null)" || return 0
  width="$(printf '%s\n' "$output" | /usr/bin/awk -F': *' '/pixelWidth:/ {print $2; exit}')"
  height="$(printf '%s\n' "$output" | /usr/bin/awk -F': *' '/pixelHeight:/ {print $2; exit}')"
  if [[ "$width" =~ ^[0-9]+$ && "$height" =~ ^[0-9]+$ ]]; then
    printf '%s × %s pixels' "$width" "$height"
  fi
}

dimensions=""
if [[ -z "$direct_format" ]]; then
  dimensions="$(image_dimensions "$representative_path")"
fi
if [[ "$readable_count" -eq 1 ]]; then
  prompt_text="$source_name • ${dimensions:+$dimensions • }$source_size_display"
else
  prompt_text="$readable_count images • $source_size_display in total. The preview shows the largest, ${representative_path##*/}."
fi

trim_log

if [[ -n "$direct_format" ]]; then
  # A one-step action uses the SIPS default detail. It still goes through the
  # same check against this Mac's writable formats as a choice from the window.
  selection="$direct_format"$'\t'"auto"
else
  if [[ -z "$UI_HELPER" ]]; then
    "$OSASCRIPT" -e 'display alert "Scrippy.app could not be found" message "Scrippy looks for its app in the Applications folder in your home folder, or in the main Applications folder. Move it back to one of those, or reinstall Scrippy." as critical'
    exit 1
  fi

  # The window prints one line, "format<TAB>detail", or __CANCEL__. Anything
  # it writes to standard error goes to the log so a failure can be diagnosed.
  picker_error="$WORK_DIR/picker-error.txt"
  selection="$("$UI_HELPER" choice "$CHOICES_FILE" "$QUALITY_CHOICES_FILE" "Convert with Scrippy" "$prompt_text" "Convert" "$representative_path" "$representative_size" "$source_total_bytes" "$readable_count" "$WORK_DIR" 2>"$picker_error")"
  picker_status=$?
  if [[ $picker_status -ne 0 ]]; then
    log_line "The conversion window exited with status $picker_status."
    /bin/cat "$picker_error" >> "$LOG_FILE" 2>/dev/null || true
    "$OSASCRIPT" -e 'display alert "The conversion window could not open" message "Please try the conversion again. If the problem continues, the error is recorded in Library/Logs/Scrippy/scrippy.log." as critical'
    exit 1
  fi
fi

if [[ -z "$selection" || "$selection" == "__CANCEL__" ]]; then
  exit 0
fi

# A tab separates the two answers because neither a format key nor a quality
# setting can contain one.
IFS=$'\t' read -r chosen_format quality_choice <<< "$selection"
# The choice is checked against this run's own list rather than trusted as
# given, so only a format SIPS reported as writable ever reaches it.
selected_row="$(/usr/bin/awk -F '\t' -v key="$chosen_format" '$1 == key { print; exit }' "$FORMATS_FILE")"
if [[ -z "$selected_row" ]]; then
  if [[ -n "$direct_format" ]]; then
    "$OSASCRIPT" - "$(format_label "$direct_format" "$direct_format")" <<'APPLESCRIPT'
on run argv
  display alert "Format unavailable" message ("This Mac cannot write " & (item 1 of argv) & " images. Use Convert with Scrippy to see the formats it can write.") as warning
end run
APPLESCRIPT
  else
    "$OSASCRIPT" -e 'display alert "Format unavailable" message "That image format is no longer available. Please start the conversion again." as warning'
  fi
  exit 1
fi

IFS=$'\t' read -r format_arg chosen_display suffix _ <<< "$selected_row"
# Only a whole number reaches SIPS as a quality. "auto" and "__NONE__" both
# mean leave the SIPS default alone, and anything else is ignored.
quality=""
if [[ "${quality_choice:-}" =~ ^[0-9]+$ ]]; then
  quality="$quality_choice"
fi

# Finds a name beside the original that is not taken yet. Nothing is ever
# overwritten, including an earlier converted copy.
next_output_path() {
  local source="$1"
  local target_suffix="$2"
  local dir name stem candidate counter
  dir="$(/usr/bin/dirname "$source")"
  name="$(/usr/bin/basename "$source")"
  # A name such as ".hidden" is all stem. Treating its leading dot as the
  # start of an extension would leave an empty name.
  if [[ "$name" == *.* && "$name" != .* ]]; then
    stem="${name%.*}"
  else
    stem="$name"
  fi
  candidate="$dir/$stem.$target_suffix"
  counter=1
  # -e alone is false for a symbolic link whose target is missing, and writing
  # to such a name would create a file wherever the link points. -L catches it.
  while [[ -e "$candidate" || -L "$candidate" ]]; do
    candidate="$dir/$stem-$counter.$target_suffix"
    counter=$((counter + 1))
  done
  printf '%s' "$candidate"
}

# Moves a finished copy from its staging folder to a free name beside the
# original. A hard link fails outright when the name already exists, so even a
# file created at that name a moment earlier is never overwritten. Volumes
# without hard links fall back to mv -n, which also refuses to overwrite.
place_output() {
  local staged="$1"
  local source="$2"
  local target_suffix="$3"
  local destination
  for _ in 1 2 3 4 5 6 7 8 9 10; do
    destination="$(next_output_path "$source" "$target_suffix")"
    if /bin/ln "$staged" "$destination" 2>/dev/null; then
      /bin/rm -f "$staged"
      return 0
    fi
    if [[ ! -e "$destination" && ! -L "$destination" ]]; then
      /bin/mv -n "$staged" "$destination" 2>/dev/null
      if [[ ! -e "$staged" ]]; then
        return 0
      fi
    fi
  done
  return 1
}

success_count=0
failure_count=0
completed_count=0
stopped_count=0
printf '0\tStarting conversion\n' > "$CONVERT_PROGRESS_FILE"

# The progress window waits two seconds before it appears, so a quick
# conversion finishes without a window flashing on screen.
if [[ "$readable_count" -eq 1 ]]; then
  progress_heading="Converting image"
else
  progress_heading="Converting images"
fi
# A one-step action can run without the app, so the window is optional here.
if [[ -n "$UI_HELPER" ]]; then
  "$UI_HELPER" progress "$CONVERT_PROGRESS_FILE" "$CONVERT_DONE_FILE" "$readable_count" "2.0" "Scrippy" "$progress_heading" "$STOP_FILE" >>"$LOG_FILE" 2>&1 &
  convert_progress_pid=$!
fi

# One SIPS call per image keeps a bad file from stopping the rest of a batch.
# Each failure is recorded and the loop moves on.
while IFS= read -r source_path; do
  [[ -z "$source_path" ]] && continue
  # Stop is honored between images, never in the middle of one, so every copy
  # that exists afterward is complete.
  if [[ -e "$STOP_FILE" ]]; then
    stopped_count=$((readable_count - completed_count))
    break
  fi

  # SIPS writes into a private folder beside the original rather than to the
  # final name. A half written file is never visible, and the final name is
  # claimed in one step by place_output. The staging folder is on the same
  # volume as the original, which a hard link requires.
  stage_dir="$(/usr/bin/mktemp -d "$(/usr/bin/dirname "$source_path")/.scrippy-XXXXXX" 2>/dev/null)" || stage_dir=""
  if [[ -z "$stage_dir" ]]; then
    failure_count=$((failure_count + 1))
    printf '%s\n%s\n\n' "$source_path" "The folder cannot be written to, so the copy could not be saved beside the original." >> "$ERRORS_FILE"
  else
    staged="$stage_dir/converted.$suffix"
    if [[ -n "$quality" ]]; then
      conversion_output="$("$SIPS" -s format "$format_arg" -s formatOptions "$quality" "$source_path" --out "$staged" 2>&1)"
    else
      conversion_output="$("$SIPS" -s format "$format_arg" "$source_path" --out "$staged" 2>&1)"
    fi
    conversion_status=$?

    # SIPS has been seen to exit cleanly after writing nothing, so an empty
    # result counts as a failure.
    if [[ $conversion_status -eq 0 && -s "$staged" ]]; then
      if place_output "$staged" "$source_path" "$suffix"; then
        success_count=$((success_count + 1))
      else
        failure_count=$((failure_count + 1))
        printf '%s\n%s\n\n' "$source_path" "No free name could be claimed beside the original." >> "$ERRORS_FILE"
      fi
    else
      failure_count=$((failure_count + 1))
      printf '%s\n%s\n\n' "$source_path" "$conversion_output" >> "$ERRORS_FILE"
    fi
    /bin/rm -rf "$stage_dir"
    stage_dir=""
  fi

  completed_count=$((completed_count + 1))
  if [[ "$readable_count" -eq 1 ]]; then
    progress_text="Finishing conversion"
  else
    progress_text="$completed_count of $readable_count complete"
  fi
  # Rewritten whole each time, so the window never reads half a line.
  printf '%s\t%s\n' "$completed_count" "$progress_text" > "$CONVERT_PROGRESS_FILE"
done < "$READABLE_FILE"

# Waiting for the window to close before the final alert keeps the two from
# appearing on screen at the same time.
: > "$CONVERT_DONE_FILE"
if [[ -n "$convert_progress_pid" ]]; then
  wait "$convert_progress_pid" 2>/dev/null || true
  convert_progress_pid=""
fi

# The work folder is deleted on exit, so failures are copied to the log first.
# Without this the alert below would point to details that no longer exist.
if [[ "$failure_count" -gt 0 ]]; then
  log_line "Converting to $chosen_display: $failure_count of $readable_count could not be converted."
  /bin/cat "$ERRORS_FILE" >> "$LOG_FILE" 2>/dev/null || true
fi

# A clean run gets a notification, which does not interrupt. Anything that
# went wrong gets an alert, which waits to be read.
if [[ "$stopped_count" -gt 0 ]]; then
  log_line "Converting to $chosen_display: stopped by the person with $stopped_count of $readable_count not started."
fi

if [[ "$failure_count" -eq 0 && "$skipped_count" -eq 0 && "$stopped_count" -eq 0 ]]; then
  "$OSASCRIPT" - "$success_count" "$chosen_display" <<'APPLESCRIPT'
on run argv
  set n to item 1 of argv
  set fmt to item 2 of argv
  if n is "1" then
    display notification ("Converted 1 image to " & fmt & ". The new copy is beside the original.") with title "Scrippy"
  else
    display notification ("Converted " & n & " images to " & fmt & ". The new copies are beside the originals.") with title "Scrippy"
  end if
end run
APPLESCRIPT
else
  "$OSASCRIPT" - "$success_count" "$failure_count" "$skipped_count" "$LOG_FILE" "$stopped_count" <<'APPLESCRIPT'
on run argv
  set convertedCount to item 1 of argv
  set failedCount to item 2 of argv
  set skippedCount to item 3 of argv
  set logPath to item 4 of argv
  set stoppedCount to item 5 of argv
  set messageText to convertedCount & " converted"
  if failedCount is not "0" then set messageText to messageText & ", " & failedCount & " could not be converted"
  if skippedCount is not "0" then set messageText to messageText & ", " & skippedCount & " skipped"
  if stoppedCount is not "0" then set messageText to messageText & ", " & stoppedCount & " not started because you clicked Stop"
  if stoppedCount is not "0" then
    set titleText to "Conversion stopped"
  else
    set titleText to "Conversion finished"
  end if
  if failedCount is "0" then
    display alert titleText message messageText as warning
  else
    set reply to display alert titleText message (messageText & ". The reason for each failure is in the log.") as warning buttons {"Show Log", "OK"} default button "OK"
    -- open -R selects the log in Finder without asking Finder through Apple
    -- Events, which would trigger a separate Automation permission prompt.
    if button returned of reply is "Show Log" then do shell script "/usr/bin/open -R " & quoted form of logPath
  end if
end run
APPLESCRIPT
fi

exit 0
