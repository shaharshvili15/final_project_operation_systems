#include "plugin_common.h"
const char* plugin_transform(const char* input){
    char* result = malloc(strlen(input)+1);

    if(input == NULL){
        return NULL;
    }
    for (int i = 0; i < strlen(input); i++) {
        result[i] = (unsigned char)input[strlen(input)-1-i];
    }
    result[strlen(input)] ='\0';
    free((void*)input);
    return result;
}

__attribute__((visibility("default")))
const char* plugin_init(int queue_size){
    return common_plugin_init(plugin_transform, "flipper", queue_size);
}