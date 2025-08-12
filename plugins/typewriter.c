#include "plugin_common.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
const char* plugin_transform(const char* input) {
    if (input == NULL) {
        return NULL;
    }

    for (int i = 0; input[i] != '\0'; i++) {
        printf("%c", input[i]);
        fflush(stdout);
        usleep(100000);
    }
    printf("\n");
    fflush(stdout);
    char* result = strdup(input);
    return result;
}
__attribute__((visibility("default")))
const char* plugin_init(int queue_size) {
    return common_plugin_init(plugin_transform, "typewriter", queue_size);
}