#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "Uso: $0 [-p RUTA_INICIO] [-i] [-w] <NOMBRE_O_PATRON>"
  echo "  -p RUTA_INICIO  Carpeta donde iniciar (por defecto: .)"
  echo "  -i               Ignorar mayúsc/minúsc (case-insensitive)"
  echo "  -w               Coincidencia por palabra exacta (sin comodines)"
  echo
  echo "Ejemplos:"
  echo "  $0 TheGambler.mkv              # busca (insensible a may/min) en '.'"
  echo "  $0 -p / -i TheGambler.mkv      # busca desde raíz, sin may/min"
  echo "  $0 -p /media -w 'foto.jpg'     # coincidencia exacta en /media"
  echo "  $0 '*gambler*.mkv'             # patrón con comodines"
  exit 1
}

START="."
CASE_INS="-iname"
WORD=false

# Parseo de flags
while getopts ":p:iw" opt; do
  case "$opt" in
    p) START="$OPTARG" ;;
    i) CASE_INS="-iname" ;;     # por claridad, dejamos -iname siempre
    w) WORD=true ;;
    *) usage ;;
  esac
done
shift $((OPTIND-1))

[[ $# -ge 1 ]] || usage
QUERY="$1"

# Si el usuario NO pidió coincidencia exacta (-w) y no incluyó comodines,
# añadimos comodines para buscar por patrón parcial.
if ! $WORD; then
  case "$QUERY" in
    *"*"*|*"?"*|*[]"[]"* ) ;;  # ya trae comodines
    * ) QUERY="*${QUERY}*" ;;
  esac
fi

# Función portable para tamaño de archivo
get_size() {
  local f="$1"
  if stat -f%z "$f" >/dev/null 2>&1; then          # macOS/BSD
    stat -f%z "$f"
  else                                             # GNU/Linux
    stat -c%s "$f"
  fi
}

FOUND=0
# -print0 para manejar espacios y caracteres raros en rutas
# 2>/dev/null para silenciar permisos denegados
while IFS= read -r -d $'\0' file; do
  size=$(get_size "$file" 2>/dev/null || echo "?")
  printf "Tamaño: %s bytes\tUbicación: %s\n" "$size" "$file"
  FOUND=$((FOUND+1))
done < <(find "$START" -type f $CASE_INS "$QUERY" -print0 2>/dev/null)

if [[ $FOUND -eq 0 ]]; then
  echo "No se encontraron archivos que coincidan con: $QUERY en $START"
  echo "Tips:"
  echo "  • Prueba desde la raíz: sudo $0 -p / -i \"$1\""
  echo "  • En macOS también puedes probar: mdfind -name \"$1\""
  echo "  • Verifica mayúsculas/minúsculas o usa comodines: '*$1*'"
fi
