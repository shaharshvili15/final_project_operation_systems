#include "plugin_common.h"
#include <ctype.h>
#include <string.h>
#include <stdlib.h>

const char* plugin_transform(const char* input){
    char* result = malloc(strlen(input)+1);
    if(input == NULL){
        return NULL;
    }
    for (int i = 0; i < strlen(input); i++) {
        result[i] = toupper((unsigned char)input[i]);
    }
    result[strlen(input)] ='\0';
    return result;
}

const char* plugin_init(int queue_size) {
    return common_plugin_init(plugin_transform, "uppercaser", queue_size);
}