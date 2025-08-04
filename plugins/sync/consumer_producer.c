#include "consumer_producer.h"
#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdbool.h>

//global variables 

const char* consumer_producer_init(consumer_producer_t* queue, int capacity){
    //1. check if the capacity is valid 
    if(capacity <= 0){
        fprintf(stderr, "[ERROR] The capacity is not valid\n");
        return "The capacity is not valid";
    }
    //4. allocate memory for sizeof(char**)*capacity 
    queue->items = calloc(capacity, sizeof(char*));
    if (queue->items == NULL) {
        fprintf(stderr, "[ERROR] Failed to allocate item buffer\n");
        return "Memory allocation failed";
    }
    //2. set the capacity if the queue 
    queue->capacity = capacity;
    //3. set count,head,tail to zero (no items yet)
    queue->count = 0;
    queue->head= 0;
    queue->tail= 0;
    queue->is_finished=false;
    pthread_mutex_init(&queue->lock, NULL);
    //5. initialize 3 monitors not_full_monitor,not_empty_monitor,finished_monitor
    if(monitor_init(&queue->finished_monitor) != 0 || monitor_init(&queue->not_empty_monitor) != 0  || monitor_init(&queue->not_full_monitor) != 0){
        fprintf(stderr, "[ERROR] Failed to create one of finished_monitor,not_empty_monitor,not_full_monitor \n");
        free(queue->items);
        return "Failed to create one of finished_monitor,not_empty_monitor,not_full_monitor";
    }
    return NULL; 
}

void consumer_producer_destroy(consumer_producer_t* queue){
    //1. destroy all 3 monitors not_full_monitor,not_empty_monitor,finished_monitor
    pthread_mutex_lock(&queue->lock);
    monitor_destroy(&queue->finished_monitor);
    monitor_destroy(&queue->not_empty_monitor);
    monitor_destroy(&queue->not_full_monitor);
    //TODO : check if destroy succeeded

    //2. free all the space of the items(array)
    for(int i=0; i< queue->capacity ; i++){
        if(queue->items[i]!=NULL){
            free(queue->items[i]);
        }
    }
    free(queue->items);
    pthread_mutex_unlock(&queue->lock);
    pthread_mutex_destroy(&queue->lock);
}

const char* consumer_producer_put(consumer_producer_t* queue, const char* item){
    //1. check if queue is full using not_full_monitor , maybe need to use while and cond_var ?
    while (1) {
        pthread_mutex_lock(&queue->lock);
        if (queue->count < queue->capacity) {
            char* newItem = strdup(item);
            if(newItem == NULL){
                pthread_mutex_unlock(&queue->lock);
                return "Memory allocation failed for item";
            }
            queue->items[queue->tail] = newItem;
            //3. change tail = tail+1
            queue->tail  = (queue->tail+1) % queue->capacity;
            queue->count++;
            monitor_signal(&queue->not_empty_monitor);
            pthread_mutex_unlock(&queue->lock);
            //4. return NULL if success error else 
            return NULL;
        }
        pthread_mutex_unlock(&queue->lock);
        // Now wait until space becomes available
        if (monitor_wait(&queue->not_full_monitor) != 0) {
            return "Wait for not full monitor failed";
        }
    }
    //2. add to tail+1 of the queue item 
    
}

char* consumer_producer_get(consumer_producer_t* queue){
    //1. check if exist an item in the queue 
    while (1) {
        pthread_mutex_lock(&queue->lock);
        if (queue->count > 0) {
            char* itemToReturn = queue ->items[queue->head];
            queue->items[queue->head] = NULL;
            queue->head  = (queue->head+1) % queue->capacity;
            queue->count--;
            monitor_signal(&queue->not_full_monitor);
            pthread_mutex_unlock(&queue->lock);
            //2. pop item and return  
            return itemToReturn;
        }
        if(queue->is_finished && queue->count == 0){
            pthread_mutex_unlock(&queue->lock);
            return NULL;
        }
        pthread_mutex_unlock(&queue->lock);
        if (monitor_wait(&queue->not_empty_monitor) != 0) {
            return NULL;
        }
    }    
}

void consumer_producer_signal_finished(consumer_producer_t* queue){
    pthread_mutex_lock(&queue->lock);
    queue->is_finished= true;
    pthread_mutex_unlock(&queue->lock);
    monitor_signal(&queue->finished_monitor);
    monitor_signal(&queue->not_empty_monitor);
}
int consumer_producer_wait_finished(consumer_producer_t* queue){
    return monitor_wait(&queue->finished_monitor);
}