#include "plugin_common.h"
#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdbool.h>

#define RED   "\033[0;31m"
#define GREEN "\033[0;32m"
#define YELLOW "\033[1;33m"
#define NC    "\033[0m"
//global variables
static plugin_context_t context;
//this plugin assumes only one instance of this plugin is loaded

const char* common_plugin_init(const char* (*process_function)(const char*),const char* name, int queue_size){
    context.name = name;
    context.process_function = process_function;
    context.queue = malloc(sizeof(consumer_producer_t));
    if (context.queue == NULL) {
        fprintf(stderr, "[ERROR] Failed to allocate item buffer\n");
        return "Memory allocation failed";
    }
    //add check here that if this failed reutnr error message 
    const char* err = consumer_producer_init(context.queue, queue_size);
    if (err != NULL) {
        free(context.queue);
        return err;
    }
    if(pthread_create(&context.consumer_thread, NULL, plugin_consumer_thread, &context) != 0){
        consumer_producer_destroy(context.queue);
        free(context.queue);
        return "Failed to create consumer thread";
    }
    //add check here that if this failed return error message and destroy 
    context.initialized=1;
    context.finished= 0;
    log_info(&context, "Plugin initialized successfully");
    return NULL;
    //1. initialize process_function
    //2. initialize queue with queue size 
    //3. set the initialized flag 
}

void* plugin_consumer_thread(void* arg){
    plugin_context_t* ctx = (plugin_context_t*)arg;
    while(1){
        char* result = consumer_producer_get(ctx->queue);
        if(result == NULL){ //CHECK IF GOT NULL
            break;
        }
        char msg[256];
        snprintf(msg, sizeof(msg), "got item: %s", result);
        log_info(ctx, msg);
        if(strcmp(result,"<END>") == 0){ //CHECK IF GOT <END> AND NEED TO FINISH
            if (ctx->next_place_work != NULL) {
                ctx->next_place_work(strdup("<END>"));
            }
            free(result);
            consumer_producer_signal_finished(ctx->queue);
            break;
        }
        const char* transformedText = ctx->process_function(result);
        snprintf(msg, sizeof(msg), "transformed result: %s", transformedText);
        log_info(ctx, msg);
        if(ctx->next_place_work != NULL){
            snprintf(msg, sizeof(msg), "forwarding: %s", transformedText);
            log_info(ctx, msg);
            ctx->next_place_work(transformedText);
        }
        else{
            log_info(ctx, "no next plugin — freeing output");
            free((void*)transformedText);
        }
        free(result);
    }
    log_info(ctx, "plugin thread finished");
    ctx->finished = 1;
    return NULL; 
}

void log_error(plugin_context_t* context, const char* message) {
    fprintf(stderr, "%s[ERROR][%s] - %s%s\n", RED, context->name, message, NC);
    fflush(stdout);
}

void log_info(plugin_context_t* context, const char* message) {
    printf("%s[INFO][%s] - %s%s\n", GREEN, context->name, message, NC);
    fflush(stdout);
}

const char* plugin_get_name(void){
    return context.name; 
}

__attribute__((visibility("default")))
const char* plugin_place_work(const char* str){
    if (str == NULL) {
        return "NULL input not allowed";
    }
    if(context.initialized!=1){
        return "Plugin not initialized";
    }
    return consumer_producer_put(context.queue, str);
}

__attribute__((visibility("default")))
void plugin_attach(const char* (*next_place_work)(const char*)){
    context.next_place_work = next_place_work;
}

__attribute__((visibility("default")))
const char* plugin_wait_finished(void){
    if(context.initialized!=1){
        return "Plugin not initialized";
    }
    pthread_join(context.consumer_thread, NULL);
    return NULL;
}

__attribute__((visibility("default")))
const char* plugin_fini(void) {
    if (context.initialized != 1) {
        return "Plugin not initialized";
    }
    // Signal that no more items will be added
    consumer_producer_signal_finished(context.queue);
    // Wait for the consumer thread to finish
    pthread_join(context.consumer_thread, NULL);
    // Clean up the queue and free memory
    consumer_producer_destroy(context.queue);
    free(context.queue);
    // Mark as uninitialized
    context.initialized = 0;
    context.finished = 1;
    return NULL;
}