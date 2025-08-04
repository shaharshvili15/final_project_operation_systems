#include "plugin_common.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
const char* plugin_transform(const char* input) {
    if (input == NULL) {
        return NULL;
    }

    printf("[logger] %s\n", input);
    fflush(stdout); 

    char* result = strdup(input);
    free((void*)input);
    return result;
}
__attribute__((visibility("default")))
const char* plugin_init(int queue_size) {
    return common_plugin_init(plugin_transform, "logger", queue_size);
}