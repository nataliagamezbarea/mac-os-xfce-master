#!/bin/bash

DIR=$(cd "$(dirname "$0")" && pwd)
source "$DIR/comun.sh"



if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "nautilus_panel.sh: funciones de script eliminadas (ya no se usan)"
fi
