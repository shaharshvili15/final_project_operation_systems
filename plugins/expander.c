#include "plugin_common.h"
const char* plugin_transform(const char* input){
    if(input == NULL){
        return NULL;
    }
    int len = strlen(input);
    char* result = malloc(len*2+1);
    //somthing went wrong with the malloc
    if (result == NULL) { 
        free((void*)input);
        return NULL;
    }
    int i = 0;
    int j = 0;
    while(i<len){
        result[j] = input[i];
        result[j+1] = ' ';
        i++;
        j = j+2;
    }
    if(j>0){
        j--;
    }
    result[j] ='\0';
    free((void*)input);
    return result;
}

__attribute__((visibility("default")))
const char* plugin_init(int queue_size){
    return common_plugin_init(plugin_transform, "expender", queue_size);
}