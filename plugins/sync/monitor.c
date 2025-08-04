#include <pthread.h>
#include "monitor.h"
#include <stdio.h>
int monitor_init(monitor_t* monitor){
    if(pthread_mutex_init(&monitor->mutex,NULL)!=0){
        return -1;
    }
    if(pthread_cond_init(&monitor->condition,NULL)!=0){
        return -1;
    }
    monitor->signaled = 0;
    return 0;
}

void monitor_destroy(monitor_t* monitor){
    //we get a monitor to detroy
    //1. free the mutex 
    //2. free the condition
    int result_mutex_destroy = pthread_mutex_destroy(&monitor->mutex);
    if(result_mutex_destroy !=0){
        //write an error here since the mutex was not able to be destroyed 
        fprintf(stderr, "[ERROR] Failed to destroy mutex (code %d)\n", result_mutex_destroy);
    }
    int result_condition_destroy = pthread_cond_destroy(&monitor->condition);
    if(result_condition_destroy!=0){
        //write an error here since the condition was not able to be destroyed 
        fprintf(stderr, "[ERROR] Failed to destroy condition variable (code %d)\n", result_condition_destroy);
    }
}

void monitor_signal(monitor_t* monitor){
    //1. lock the mutex 
    //2. change the signaled to 1
    //3. use cond variable signal 
    //4. unlock the mutex 
    if(pthread_mutex_lock(&monitor->mutex) != 0){
        fprintf(stderr, "[ERROR] Failed to lock monitor mutex\n");
        return;
    }
    monitor->signaled = 1;
    if(pthread_cond_signal(&monitor->condition) != 0){
        fprintf(stderr, "[ERROR] Failed to signal condition variable\n");
    }
    if(pthread_mutex_unlock(&monitor->mutex) != 0){
        fprintf(stderr, "[ERROR] Failed to unlock monitor mutex\n");
    }
}

void monitor_reset(monitor_t* monitor){
    //1. lock the mutex 
    //2. change the signaled to 0 
    //3. unlock the mutex
    if(pthread_mutex_lock(&monitor->mutex) != 0){
        fprintf(stderr, "[ERROR] Failed to lock monitor mutex\n");
        return;
    }
    monitor->signaled = 0;
    if(pthread_mutex_unlock(&monitor->mutex) != 0){
        fprintf(stderr, "[ERROR] Failed to unlock monitor mutex\n");
    }
}
int monitor_wait(monitor_t* monitor){
    if(pthread_mutex_lock(&monitor->mutex) !=0){
        fprintf(stderr, "[ERROR] Failed to lock monitor mutex\n");
        return -1;
    }
    while(monitor->signaled == 0){
        if(pthread_cond_wait(&monitor->condition,&monitor->mutex) != 0){
            fprintf(stderr, "[ERROR] Failed to wait on condition variable\n");
            pthread_mutex_unlock(&monitor->mutex);
            return -1;
        }
    }
    monitor->signaled=0;
    if(pthread_mutex_unlock(&monitor->mutex) != 0){
        fprintf(stderr, "[ERROR] Failed to unlock monitor mutex\n");
        return -1;
    }
    return 0;
}