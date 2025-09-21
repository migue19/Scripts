#!/usr/bin/env bash
# Uso:
#   ./biggest_in_folder.sh /ruta/a/carpeta           # considera archivos y carpetas
#   ./biggest_in_folder.sh /ruta/a/carpeta --solo-carpetas  # solo carpetas

set -euo pipefail

if [ $# -lt 1 ]; then
  echo "Uso: $0 /ruta/a/carpeta [--solo-carpetas]" >&2
  exit 1
fi

BASE="$1"
ONLY_DIRS="${2:-}"

if [ ! -d "$BASE" ]; then
  echo "Error: '$BASE' no es una carpeta" >&2
  exit 1
fi

# Expansión de entradas inmediatas (maneja espacios por las comillas)
entries=( "$BASE"/* )

# Si la carpeta está vacía, el patrón no matchea a nada
if [ ! -e "${entries[0]:-}" ]; then
  echo "No hay entradas dentro de: $BASE"
  exit 0
fi

largest_size=-1
largest_path=""

for p in "${entries[@]}"; do
  # Si pidieron solo carpetas, filtra
  if [ "$ONLY_DIRS" = "--solo-carpetas" ] && [ ! -d "$p" ]; then
    continue
  fi
  # 'du -sk' sirve para archivos y carpetas; es portable
  size_kb=$(du -sk "$p" 2>/dev/null | awk '{print $1}')
  # si du falló (permisos u otros), sáltate
  if [ -z "${size_kb:-}" ]; then
    continue
  fi
  if [ "$size_kb" -gt "$largest_size" ]; then
    largest_size="$size_kb"
    largest_path="$p"
  fi
done

if [ "$largest_size" -lt 0 ] || [ -z "$largest_path" ]; then
  if [ "$ONLY_DIRS" = "--solo-carpetas" ]; then
    echo "No hay subcarpetas en: $BASE"
  else
    echo "No se pudo calcular tamaño (¿permisos?)."
  fi
  exit 0
fi

human() {
  local kb=$1 v=$1 unit="KB"
  for u in KB MB GB TB; do
    unit=$u
    if [ "$v" -lt 1024 ]; then break; fi
    v=$(( (v + 512) / 1024 ))
  done
  echo "$v $unit"
}

echo "Mayor en '$BASE':"
echo "• Ruta: $largest_path"
echo "• Tamaño: $(human "$largest_size")"
