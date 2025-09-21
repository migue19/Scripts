#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "Uso: $0 [-c] [-o salida.csv] [-x PATRON]... <DIR_A> <DIR_B>"
  echo
  echo "Compara diferencias entre DIR_A y DIR_B usando rsync --dry-run (sin copiar)."
  echo "Agrupa en:"
  echo "  • Solo en A"
  echo "  • Solo en B"
  echo "  • Difieren (mismo path; distinto contenido/metadatos)"
  echo
  echo "Opciones:"
  echo "  -c                Usa --checksum (más exacto; más lento)."
  echo "  -o salida.csv     Exporta también a CSV (UTF-8): status,path,size_in_A,size_in_B."
  echo "  -x PATRON         Excluir patrón (repetible). Ej: -x 'node_modules/' -x '*.tmp'"
  echo "                    (se pasa tal cual a rsync --exclude)"
  echo
  echo "Ejemplos:"
  echo "  $0 dirA dirB"
  echo "  $0 -c -o diff.csv -x 'node_modules/' -x '*.log' dirA dirB"
  exit 1
}

CHECKSUM=0
CSV_OUT=""
EXCLUDES=()

# Parseo corto con getopts
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

# Normaliza rutas
[[ "${DIR_A}" == */ ]] || DIR_A="${DIR_A}/"
[[ "${DIR_B}" == */ ]] || DIR_B="${DIR_B}/"
[[ -d "$DIR_A" ]] || { echo "No existe: $DIR_A" >&2; exit 2; }
[[ -d "$DIR_B" ]] || { echo "No existe: $DIR_B" >&2; exit 2; }

# rsync options
RSYNC_OPTS=(-a -n -i --delete)
(( CHECKSUM )) && RSYNC_OPTS+=("--checksum")
for pat in "${EXCLUDES[@]:-}"; do
  RSYNC_OPTS+=("--exclude=$pat")
done

# Arrays para resultados
declare -a ONLY_A=()
declare -a ONLY_B=()
declare -a DIFF=()

# Tamaño portable
get_size() {
  local f="$1"
  if [ -d "$f" ]; then
    echo ""
    return 0
  fi
  if stat -f%z "$f" >/dev/null 2>&1; then
    stat -f%z "$f"    # macOS/BSD
  else
    stat -c%s "$f"    # GNU/Linux
  fi
}

# Ejecuta y parsea salida itemizada de rsync
while IFS= read -r line; do
  [[ -z "$line" ]] && continue
  [[ "$line" =~ ^sending\ incremental\ file\ list$ ]] && continue
  [[ "$line" =~ ^sent\  ]] && continue
  [[ "$line" =~ ^total\ size\ is\  ]] && continue

  if [[ "$line" =~ ^\*deleting\  ]]; then
    path="${line#*deleting }"
    ONLY_B+=("$path")
    continue
  fi

  code="${line:0:11}"
  path="${line:12}"

  [[ "$path" == "." ]] && continue

  if [ -e "${DIR_B}${path}" ]; then
    DIFF+=("$path")
  else
    ONLY_A+=("$path")
  fi
done < <(rsync "${RSYNC_OPTS[@]}" "$DIR_A" "$DIR_B")

# Impresión
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

print_section "Solo en A (se copiarían a B)" "${ONLY_A[@]}"
print_section "Solo en B (se borrarían en B si sincronizas desde A)" "${ONLY_B[@]}"
print_section "Difieren (se actualizarían en B desde A)" "${DIFF[@]}"

# CSV opcional
if [[ -n "$CSV_OUT" ]]; then
  csv_escape() {
    local s="$1"
    if [[ "$s" == *'"'* || "$s" == *','* ]]; then
      s="${s//\"/\"\"}"
      printf '"%s"' "$s"
    else
      printf '%s' "$s"
    fi
  }

  {
    echo "status,path,size_in_A,size_in_B"
    for p in "${ONLY_A[@]}"; do
      sa="$(get_size "${DIR_A}${p}")"
      printf '%s,%s,%s,%s\n' "ONLY_A" "$(csv_escape "$p")" "$(csv_escape "$sa")" ""
    done
    for p in "${ONLY_B[@]}"; do
      sb="$(get_size "${DIR_B}${p}")"
      printf '%s,%s,%s,%s\n' "ONLY_B" "$(csv_escape "$p")" "" "$(csv_escape "$sb")"
    done
    for p in "${DIFF[@]}"; do
      sa="$(get_size "${DIR_A}${p}")"
      sb="$(get_size "${DIR_B}${p}")"
      printf '%s,%s,%s,%s\n' "DIFF" "$(csv_escape "$p")" "$(csv_escape "$sa")" "$(csv_escape "$sb")"
    done
  } > "$CSV_OUT"

  echo "CSV generado: $CSV_OUT"
fi

# Exit code: 0 sin diferencias; 1 si hubo diferencias
if (( ${#ONLY_A[@]} + ${#ONLY_B[@]} + ${#DIFF[@]} > 0 )); then
  exit 1
else
  exit 0
fi
