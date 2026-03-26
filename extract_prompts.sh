#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INPUT_JSON="${1:-$ROOT_DIR/models.json}"
OUTPUT_DIR="${2:-$ROOT_DIR/prompts}"

if ! command -v jq >/dev/null 2>&1; then
  echo "jq is required but not installed." >&2
  exit 1
fi

if [[ ! -f "$INPUT_JSON" ]]; then
  echo "Input file not found: $INPUT_JSON" >&2
  exit 1
fi

mkdir -p "$OUTPUT_DIR"

index_file="$(mktemp)"
prompt_count=0

write_prompt() {
  local file_path="$1"
  local model_slug="$2"
  local field_path="$3"
  local prompt_kind="$4"
  local body="$5"

  mkdir -p "$(dirname "$file_path")"
  {
    printf '# %s\n\n' "$model_slug"
    printf -- '- Source: `models.json`\n'
    printf -- '- Field: `%s`\n' "$field_path"
    printf -- '- Kind: `%s`\n\n' "$prompt_kind"
    printf '%s\n\n' '---'
    printf '%s\n' "$body"
  } > "$file_path"

  printf -- '- [%s](%s)\n' "${file_path#$OUTPUT_DIR/}" "${file_path#$OUTPUT_DIR/}" >> "$index_file"
  prompt_count=$((prompt_count + 1))
}

while IFS= read -r slug; do
  model_dir="$OUTPUT_DIR/$slug"

  base_instructions="$(jq -r --arg slug "$slug" '.models[] | select(.slug == $slug) | .base_instructions // empty' "$INPUT_JSON")"
  if [[ -n "$base_instructions" ]]; then
    write_prompt \
      "$model_dir/base_instructions.md" \
      "$slug" \
      "base_instructions" \
      "system prompt" \
      "$base_instructions"
  fi

  instructions_template="$(jq -r --arg slug "$slug" '.models[] | select(.slug == $slug) | .model_messages.instructions_template? // empty' "$INPUT_JSON")"
  if [[ -n "$instructions_template" ]]; then
    write_prompt \
      "$model_dir/model_messages.instructions_template.md" \
      "$slug" \
      "model_messages.instructions_template" \
      "template prompt" \
      "$instructions_template"
  fi

  while IFS= read -r entry; do
    key="$(printf '%s' "$entry" | jq -r '.key')"
    value="$(printf '%s' "$entry" | jq -r '.value')"

    if [[ -z "$value" ]]; then
      continue
    fi

    write_prompt \
      "$model_dir/model_messages.instructions_variables.$key.md" \
      "$slug" \
      "model_messages.instructions_variables.$key" \
      "prompt variable" \
      "$value"
  done < <(
    jq -c --arg slug "$slug" '
      .models[]
      | select(.slug == $slug)
      | .model_messages.instructions_variables? // {}
      | to_entries[]
    ' "$INPUT_JSON"
  )
done < <(jq -r '.models[].slug' "$INPUT_JSON")

{
  printf '# Extracted Prompts\n\n'
  printf 'Generated from `%s`.\n\n' "${INPUT_JSON#$ROOT_DIR/}"
  printf 'Total prompt files: `%d`\n\n' "$prompt_count"
  cat "$index_file"
} > "$OUTPUT_DIR/README.md"

rm -f "$index_file"

printf 'Wrote %d prompt files to %s\n' "$prompt_count" "$OUTPUT_DIR"
