#!/bin/bash
set -e

echo "[BUILD] Creating output directory"
mkdir -p output

echo "[BUILD] Compiling main.c"
gcc -o output/analyzer main.c -ldl -lpthread -export-dynamic

PLUGINS="logger typewriter uppercaser rotator flipper expander"

for plugin in $PLUGINS; do
    echo "[BUILD] Compiling plugin: $plugin"
    gcc -fPIC -shared -o output/${plugin}.so \
        plugins/${plugin}.c \
        plugins/plugin_common.c \
        plugins/sync/consumer_producer.c\
        plugins/sync/monitor.c \
        -Iplugins -Iplugins/sync -lpthread
done

echo "[BUILD] Done."