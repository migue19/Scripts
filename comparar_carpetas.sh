#!/usr/bin/env bash
# macOS-only
set -euo pipefail

usage() {
  echo "Uso: $0 [-c] [-o salida.csv] [-x PATRON]... <DIR_A> <DIR_B>"
  echo
  echo "Compara DIR_A -> DIR_B con rsync en modo simulación (sin copiar)."
  echo "Agrupa en: Solo en A, Solo en B, y Difieren (mismo path; distinto contenido/metadatos)."
  echo
  echo "Opciones:"
  echo "  -c              Usa --checksum (más exacto; más lento)."
  echo "  -o salida.csv   Genera CSV: status,path,size_in_A,size_in_B"
  echo "  -x PATRON       Excluye patrón (repetible). Ej: -x 'node_modules/' -x '*.log'"
  echo
  echo "Ejemplos:"
  echo "  $0 \"/ruta/Dir A\" \"/ruta/Dir B\""
  echo "  $0 -c -o diff.csv -x 'node_modules/' -x '*.tmp' \"/A\" \"/B\""
  exit 1
}

# ---- Parseo de flags ----
CHECKSUM=0
CSV_OUT=""
EXCLUDES=()

while getopts ":co:x:" opt; do
  case "$opt" in
    c) CHECKSUM=1 ;;
    o) CSV_OUT="$OPTARG" ;;
    x) EXCLUDES+=("$OPTARG") ;;
    *) usage ;;
  esac
done
shift $((OPTIND-1))

[[ $# -eq 2 ]] || usage
DIR_A="$1"
DIR_B="$2"

# ---- Normalización de rutas (añade / final si falta) ----
[[ "$DIR_A" == */ ]] || DIR_A="${DIR_A}/"
[[ "$DIR_B" == */ ]] || DIR_B="${DIR_B}/"

[[ -d "$DIR_A" ]] || { echo "No existe: $DIR_A" >&2; exit 2; }
[[ -d "$DIR_B" ]] || { echo "No existe: $DIR_B" >&2; exit 2; }

# ---- Opciones de rsync ----
RSYNC_OPTS=(-a -n -i --delete)   # -i: salida itemizada
(( CHECKSUM )) && RSYNC_OPTS+=("--checksum")
for pat in "${EXCLUDES[@]:-}"; do
  RSYNC_OPTS+=("--exclude=$pat")
done

# ---- Arrays de resultados ----
declare -a ONLY_A=()
declare -a ONLY_B=()
declare -a DIFF=()

# ---- Tamaño (macOS) ----
get_size() {
  local f="$1"
  if [ -d "$f" ]; then
    echo ""
  elif [ -e "$f" ]; then
    # BSD/macOS stat
    stat -f%z "$f" 2>/dev/null || echo "?"
  else
    echo ""
  fi
}

# ---- Comparación usando rsync --dry-run ----
# Parsea la salida itemizada (-i). Líneas típicas:
#   *deleting path          -> existe en B, no en A
#   >f..t...... path        -> archivo desde A hacia B (nuevo o actualizado)
#   cd+++++++++ dir/        -> directorio nuevo en B
while IFS= read -r line; do
  [[ -z "$line" ]] && continue
  [[ "$line" =~ ^sending\ incremental\ file\ list$ ]] && continue
  [[ "$line" =~ ^sent\  ]] && continue
  [[ "$line" =~ ^total\ size\ is\  ]] && continue

  if [[ "$line" =~ ^\*deleting\  ]]; then
    path="${line#*deleting }"
    [[ "$path" == "." ]] && continue
    ONLY_B+=("$path")
    continue
  fi

  code="${line:0:11}"
  path="${line:12}"
  [[ "$path" == "." ]] && continue

  # Si el path ya existe en B, entonces se actualizaría (difieren); si no, es solo-en-A
  if [ -e "${DIR_B}${path}" ]; then
    DIFF+=("$path")
  else
    ONLY_A+=("$path")
  fi
done < <(rsync "${RSYNC_OPTS[@]}" "$DIR_A" "$DIR_B")

# ---- Impresión legible ----
print_section() {
  local title="$1"; shift
  local -a arr=("$@")
  echo "==== $title (${#arr[@]}) ===="
  if ((${#arr[@]})); then
    printf '%s\n' "${arr[@]}" | sort
  else
    echo "(vacío)"
  fi
  echo
}

print_section "Solo en A (se copiarían a B)" "${ONLY_A[@]:-}"
print_section "Solo en B (se borrarían en B si sincronizas desde A)" "${ONLY_B[@]:-}"
print_section "Difieren (se actualizarían en B desde A)" "${DIFF[@]:-}"

# ---- CSV opcional ----
if [[ -n "$CSV_OUT" ]]; then
  # Si es ruta relativa, conviértela a absoluta para que quede claro dónde se guardó
  if [[ "$CSV_OUT" != /* ]]; then
    CSV_OUT="$(pwd)/$CSV_OUT"
  fi

  csv_escape() {
    local s="$1"
    if [[ "$s" == *','* || "$s" == *'"'* ]]; then
      s="${s//\"/\"\"}"
      printf '"%s"' "$s"
    else
      printf '%s' "$s"
    fi
  }

  {
    echo "status,path,size_in_A,size_in_B"
    for p in "${ONLY_A[@]:-}"; do
      sa="$(get_size "${DIR_A}${p}")"
      printf '%s,%s,%s,%s\n' "ONLY_A" "$(csv_escape "$p")" "$(csv_escape "$sa")" ""
    done
    for p in "${ONLY_B[@]:-}"; do
      sb="$(get_size "${DIR_B}${p}")"
      printf '%s,%s,%s,%s\n' "ONLY_B" "$(csv_escape "$p")" "" "$(csv_escape "$sb")"
    done
    for p in "${DIFF[@]:-}"; do
      sa="$(get_size "${DIR_A}${p}")"
      sb="$(get_size "${DIR_B}${p}")"
      printf '%s,%s,%s,%s\n' "DIFF" "$(csv_escape "$p")" "$(csv_escape "$sa")" "$(csv_escape "$sb")"
    done
  } > "$CSV_OUT"

  echo "CSV generado: $CSV_OUT"
fi

# ---- Exit code útil para CI ----
if (( ${#ONLY_A[@]:-0} + ${#ONLY_B[@]:-0} + ${#DIFF[@]:-0} > 0 )); then
  exit 1
else
  exit 0
fi
