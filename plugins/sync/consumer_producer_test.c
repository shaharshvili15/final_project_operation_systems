#include "consumer_producer.h"
#include <stdio.h>
#include <stdlib.h>
#include <pthread.h>
#include <unistd.h>
#include <time.h>
#define TOTAL_ITEMS 20
#define CONSUMER_COUNT 3
#define QUEUE_CAPACITY 5

typedef struct {
    consumer_producer_t* queue;
    int producer_id;
} producer_arg_t;

typedef struct{
    consumer_producer_t* queue;
    int consumer_id;
} consumer_arg_t;

char* received_items[TOTAL_ITEMS];
int received_count = 0;
pthread_mutex_t received_mutex = PTHREAD_MUTEX_INITIALIZER;

void* consumer_thread(void* arg) {
    printf("[Test 1] [Consumer] waiting to get item...\n");
    char* result = consumer_producer_get((consumer_producer_t*)arg);
    if (result) {
        printf("[Test 1] [Consumer] got item: %s\n", result);
        free(result);
    } else {
        printf("[Test 1] [Consumer] got NULL (unexpected)\n");
    }
    return NULL;
}
void* producer_thread(void* arg) {
    printf("[Test 1] [Producer] putting item: Shahar\n");
    consumer_producer_put((consumer_producer_t*)arg, "Shahar");
    return NULL;
}
void run_test1_single_producer_single_consumer() {
    printf("=== Test 1 [CONSUMER-PRODUCER]: Single producer, single consumer ===\n");

    consumer_producer_t copo;
    consumer_producer_init(&copo, 2);

    pthread_t prod, cons;
    pthread_create(&prod, NULL, producer_thread, &copo);
    pthread_create(&cons, NULL, consumer_thread, &copo);

    pthread_join(prod, NULL);
    pthread_join(cons, NULL);

    consumer_producer_destroy(&copo);

    printf("=== Test 1 Complete ===\n\n");
}

void* consumer_thread_test2(void* arg){
    printf("[Test 2] [Consumer] waiting to get item...\n");
    char* result = consumer_producer_get((consumer_producer_t*)arg);
    if (result) {
        printf("[Test 2] [Consumer] got item: %s\n", result);
        free(result);
    } else {
        printf("[Test 2] [Consumer] got NULL (unexpected)\n");
    }
    return NULL;
}
void* producer_thread_test2(void* arg){
    sleep(1);
    printf("[Test 2] [Producer] putting item: TEST2\n");
    consumer_producer_put((consumer_producer_t*)arg, "TEST2");
    return NULL;
}
void run_test2_get_before_put(){
    printf("=== Test 2 [CONSUMER-PRODUCER]: Get consumer before put producer ===\n");
    consumer_producer_t copo;
    consumer_producer_init(&copo, 2);

    pthread_t prod, cons;
    pthread_create(&prod, NULL, consumer_thread_test2, &copo);
    pthread_create(&cons, NULL, producer_thread_test2, &copo);

    pthread_join(prod, NULL);
    pthread_join(cons, NULL);

    consumer_producer_destroy(&copo);

    printf("=== Test 2 Complete ===\n\n");
}

void* producer_fill_queue(void* arg){
    printf("[Test 3] [Producer] putting item: TEST(1)\n");
    consumer_producer_put((consumer_producer_t*)arg, "TEST3(1)");
    printf("[Test 3] [Producer] putting item: TEST(2)\n");
    consumer_producer_put((consumer_producer_t*)arg, "TEST3(2)");
    printf("[Producer] trying to put 3rd item (should block)\n");
    consumer_producer_put((consumer_producer_t*)arg, "TEST3(3)");
    printf("[Producer] put 3rd item (unblocked)\n");
    return NULL;
}
void* consumer_thread_test3(void* arg){
    sleep(1);
    printf("[Test 3] [Consumer] waiting to get item...\n");
    char* result = consumer_producer_get((consumer_producer_t*)arg);
    if (result) {
        printf("[Test 3] [Consumer] got item: %s\n", result);
        free(result);
    } else {
        printf("[Test 3] [Consumer] got NULL (unexpected)\n");
    }
    return NULL;
}
void run_test3_put_until_full(){
    printf("=== Test 3 [CONSUMER-PRODUCER]: fill queue ===\n");
    consumer_producer_t copo;
    consumer_producer_init(&copo, 2);

    pthread_t prod, cons;
    pthread_create(&prod, NULL, producer_fill_queue, &copo);
    pthread_create(&cons, NULL, consumer_thread_test3, &copo);

    pthread_join(prod, NULL);
    pthread_join(cons, NULL);

    consumer_producer_destroy(&copo);

    printf("=== Test 3 Complete ===\n\n");
}

void* consumer_waiting_for_finish_test4(void* arg){
    printf("[Test 4] [Consumer] waiting for finished signal\n");
    int result = consumer_producer_wait_finished((consumer_producer_t*)arg);
    if (result ==0) {
        printf("[Test 4] [Consumer] recevied finished signal");
    } else {
        printf("[Test 4] [Consumer] [ERROR] consumer waiting for finish got an error");
    }
    return NULL;
}
void run_test4_consumer_waits_for_finished_monitor(){
    printf("=== Test 4 [CONSUMER-PRODUCER]: wait for finish monitor ===\n");
    consumer_producer_t copo;
    consumer_producer_init(&copo, 1);

    pthread_t cons;
    pthread_create(&cons, NULL, consumer_waiting_for_finish_test4, &copo);

    sleep(1);
    consumer_producer_signal_finished(&copo);
    pthread_join(cons, NULL);

    consumer_producer_destroy(&copo);

    printf("=== Test 4 Complete ===\n\n");
}

void* consumer_trying_to_get_when_empty_queue_test5(void* arg){
    printf("[Test 5] [Consumer] trying to get but gets blocked\n");
    char* result = consumer_producer_get((consumer_producer_t*)arg);
    if (result) {
        printf("[Test 5] [Consumer] got item: %s (unexpected)\n ", result);
        free(result);
    } else {
        printf("[Test 5] [Consumer] got NULL\n");
    }
    return NULL;
}
void run_test5_consumer_tries_to_get_when_queue_empty(){
    printf("=== Test 5 [CONSUMER-PRODUCER]: try to get when queue is empty ===\n");
    consumer_producer_t copo;
    consumer_producer_init(&copo, 1);

    pthread_t cons;
    pthread_create(&cons, NULL, consumer_trying_to_get_when_empty_queue_test5, &copo);

    sleep(1);
    consumer_producer_signal_finished(&copo);
    pthread_join(cons, NULL);

    consumer_producer_destroy(&copo);

    printf("=== Test 5 Complete ===\n\n");
}
void* producer_thread_test6(void* arg) {
    producer_arg_t* args = (producer_arg_t*)arg;
    consumer_producer_t* queue = args->queue;
    int id = args->producer_id;

    char buffer[64];
    for (int i = 0; i < 10; i++) {
        snprintf(buffer, sizeof(buffer), "Producer %d - item %d", id, i);
        consumer_producer_put(queue, buffer);
    }
    free(arg);  // cleanup dynamic allocation
    return NULL;
}
void* consumer_thread_test6(void* arg) {
    consumer_producer_t* queue = (consumer_producer_t*)arg;
    for (int i = 0; i < 30; i++) {
        char* item = consumer_producer_get(queue);
        if (item) {
            printf("[Consumer] got item: %s\n", item);
            free(item);
        } else {
            printf("[Consumer] got NULL (unexpected)\n");
        }
    }
    return NULL;
}
void run_test6_multiple_producers_one_consumer() {
    printf("=== Test 6 [CONSUMER-PRODUCER]: multiple producers, one consumer ===\n");

    consumer_producer_t copo;
    consumer_producer_init(&copo, 5);

    pthread_t producers[3];
    pthread_t consumer;

    // Start 3 producers
    for (int i = 0; i < 3; i++) {
        producer_arg_t* arg = malloc(sizeof(producer_arg_t));
        arg->queue = &copo;
        arg->producer_id = i + 1;
        pthread_create(&producers[i], NULL, producer_thread_test6, arg);
    }

    // Start 1 consumer
    pthread_create(&consumer, NULL, consumer_thread_test6, &copo);

    // Join producers
    for (int i = 0; i < 3; i++) {
        pthread_join(producers[i], NULL);
    }

    // Join consumer
    pthread_join(consumer, NULL);

    consumer_producer_destroy(&copo);

    printf("=== Test 6 Complete ===\n\n");
}

void* test_producer_test7(void* arg) {
    consumer_producer_t* queue = (consumer_producer_t*)arg;
    char buffer[64];
    for (int i = 0; i < TOTAL_ITEMS; ++i) {
        snprintf(buffer, sizeof(buffer), "ITEM_%d", i);
        consumer_producer_put(queue, buffer);
    }
    return NULL;
}

void* test_consumer_test7(void* arg) {
    consumer_producer_t* queue = (consumer_producer_t*)arg;
    while (1) {
        char* item = consumer_producer_get(queue);
        if (!item) break;

        pthread_mutex_lock(&received_mutex);
        if (received_count < TOTAL_ITEMS) {
            received_items[received_count++] = strdup(item);
        }
        pthread_mutex_unlock(&received_mutex);
        free(item);
    }
    return NULL;
}

//TODO:CHECK WHY THIS DOES NOT WORK 
void run_test7_multiple_consumers_one_producer() {
    printf("=== Clean Test [Multiple Consumers, One Producer] ===\n");

    consumer_producer_t queue;
    consumer_producer_init(&queue, QUEUE_CAPACITY);

    pthread_t producer;
    pthread_t consumers[CONSUMER_COUNT];
    for (int i = 0; i < CONSUMER_COUNT; ++i) {
        pthread_create(&consumers[i], NULL, test_consumer_test7, &queue);
    }

    pthread_create(&producer, NULL, test_producer_test7, &queue);

    pthread_join(producer, NULL);
    consumer_producer_signal_finished(&queue);

    for (int i = 0; i < CONSUMER_COUNT; ++i) {
        pthread_join(consumers[i], NULL);
    }

    // Validate results
    int seen[TOTAL_ITEMS] = {0};
    int ok = 1;

    for (int i = 0; i < received_count; ++i) {
        int n;
        if (sscanf(received_items[i], "ITEM_%d", &n) == 1 && n >= 0 && n < TOTAL_ITEMS) {
            seen[n]++;
        } else {
            printf("[ERROR] Invalid format: %s\n", received_items[i]);
            ok = 0;
        }
    }

    for (int i = 0; i < TOTAL_ITEMS; ++i) {
        if (seen[i] != 1) {
            printf("[FAIL] ITEM_%d seen %d times (expected once)\n", i, seen[i]);
            ok = 0;
        }
    }

    if (ok) {
        printf("[PASS] All %d items received exactly once.\n", TOTAL_ITEMS);
    } else {
        printf("[FAIL] Duplicate or missing items detected.\n");
    }

    for (int i = 0; i < received_count; ++i) {
        free(received_items[i]);
    }

    consumer_producer_destroy(&queue);
    printf("=== Test Complete ===\n\n");
}
void run_test8_destroy_after_use() {
    printf("=== Test 8 [CONSUMER-PRODUCER]: destroy after use ===\n");
    consumer_producer_t q;
    consumer_producer_init(&q, 2);

    consumer_producer_put(&q, "test1");
    char* item = consumer_producer_get(&q);
    if (item) {
        printf("[Test 8] got item: %s\n", item);
        free(item);
    }

    consumer_producer_destroy(&q);
    printf("=== Test 8 Complete ===\n\n");
}

int main(){
    run_test1_single_producer_single_consumer();
    run_test2_get_before_put();
    run_test3_put_until_full();
    run_test4_consumer_waits_for_finished_monitor();
    run_test5_consumer_tries_to_get_when_queue_empty();
    run_test6_multiple_producers_one_consumer();
    //run_test7_multiple_consumers_one_producer();
    run_test8_destroy_after_use();
    return 0;
}