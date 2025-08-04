#include "plugin_common.h"
const char* plugin_transform(const char* input){
    if(input == NULL){
        return NULL;
    }
    int len = strlen(input);
    char* result = malloc(len+1);
    result[0] = input[len-1];
    for (int i = 0; i < len-1; i++) {
        result[i+1] = input[i];
    }
    result[len] ='\0';
    free((void*)input);
    return result;
}

__attribute__((visibility("default")))
const char* plugin_init(int queue_size){
    return common_plugin_init(plugin_transform, "rotator", queue_size);
}