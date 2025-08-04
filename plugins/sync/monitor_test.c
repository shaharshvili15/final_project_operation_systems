#define _POSIX_C_SOURCE 199309L
#include <stdio.h>
#include <stdlib.h>
#include <pthread.h>
#include <unistd.h>
#include "monitor.h"
#include <time.h>

// test1-basic ===
void* waiter_thread(void* arg) {
    printf("[Test 1] [Waiter] Waiting on monitor...\n");
    monitor_wait((monitor_t*)arg);
    printf("[Test 1] [Waiter] Woke up!\n");
    return NULL;
}

void* signaler_thread(void* arg) {
    sleep(1);
    printf("[Test 1] [Signaler] Sending signal...\n");
    monitor_signal((monitor_t*)arg);
    return NULL;
}

void run_test1_basic_wait_signal() {
    printf("=== Test 1: Signal after wait ===\n");
    monitor_t mon;
    monitor_init(&mon);

    pthread_t t1, t2;
    pthread_create(&t1, NULL, waiter_thread, &mon);
    pthread_create(&t2, NULL, signaler_thread, &mon);

    pthread_join(t1, NULL);
    pthread_join(t2, NULL);

    monitor_destroy(&mon);
    printf("=== Test 1 Complete ===\n\n");
}

// test2 make the second one sleep before waits ===
void* early_signal_thread(void* arg) {
    monitor_t* mon = (monitor_t*)arg;
    printf("[Test 2] [Signaler] Sending signal early...\n");
    monitor_signal(mon);
    return NULL;
}
void* late_wait_thread(void* arg) {
    monitor_t* mon = (monitor_t*)arg;
    sleep(1);
    printf("[Test 2] [Waiter] Waiting after signal...\n");
    monitor_wait(mon);
    printf("[Test 2] [Waiter] Woke up!\n");
    return NULL;
}
void run_test2_early_signal() {
    printf("=== Test 2: Signal before wait ===\n");
    monitor_t mon;
    monitor_init(&mon);

    pthread_t t1, t2;
    pthread_create(&t1, NULL, early_signal_thread, &mon);
    pthread_create(&t2, NULL, late_wait_thread, &mon);

    pthread_join(t1, NULL);
    pthread_join(t2, NULL);

    monitor_destroy(&mon);
    printf("=== Test 2 Complete ===\n\n");
}


void* first_thread_wait(void* arg){
    monitor_t* mon = (monitor_t*)arg;
    printf("[Test 3] [Waiter] Waiting for signal...\n");
    monitor_wait(mon);
    printf("[Test 3] [Waiter] Woke up!\n");
    return NULL;
}
void* second_thread_signal(void* arg){
    printf("[Test 3] [Signaler] Sending signal...\n");
    monitor_signal((monitor_t*)arg);
    return NULL;
}
void run_test3_reuse_monitor(){
    printf("=== Test 3: Reuse monitor ===\n");
    monitor_t mon;
    monitor_init(&mon);

    pthread_t t1, t2;
    pthread_create(&t1, NULL, first_thread_wait, &mon);
    pthread_create(&t2, NULL, second_thread_signal, &mon);

    pthread_join(t1, NULL);
    pthread_join(t2, NULL);

    printf("[Test 3] reseting monitor...\n");
    pthread_t t3, t4;
    pthread_create(&t3, NULL, first_thread_wait, &mon);
    pthread_create(&t4, NULL, second_thread_signal, &mon);

    pthread_join(t3, NULL);
    pthread_join(t4, NULL);
    printf("=== Test 3 Complete ===\n\n");

}


void* first_thread_singal_two_times(void* arg){
    printf("[Test 4] [Signaler] Sending two signals...\n");
    monitor_signal((monitor_t*)arg);
    monitor_signal((monitor_t*)arg);
    return NULL;
}
void* second_thread_wait(void* arg){
    monitor_t* mon = (monitor_t*)arg;
    printf("[Test 4] [Waiter] Waiting for signal...\n");
    monitor_wait(mon);
    printf("[Test 4] [Waiter] Woke up!\n");
    printf("[Test 4] [Waiter] Waiting!\n");
    monitor_wait(mon);
    printf("[Test 4] [Waiter] Woke up!\n");
    return NULL;
}
void* delayed_signal_thread(void* arg) {
    sleep(2);  // Give time for second wait to start
    printf("[Test 4] [Final Signaler] Sending final signal...\n");
    monitor_signal((monitor_t*)arg);
    return NULL;
}
void run_test4_signal_twice_before_one_wait() {
    printf("=== Test 4: Signal twice before two waits ===\n");
    monitor_t mon;
    monitor_init(&mon);

    pthread_t t1, t2, t3;

    // Thread 1: sends two early signals
    pthread_create(&t1, NULL, first_thread_singal_two_times, &mon);
    sleep(1);  // Ensure signals happen before wait

    // Thread 2: performs two waits
    pthread_create(&t2, NULL, second_thread_wait, &mon);

    // Thread 3: sends a delayed final signal for the second wait
    pthread_create(&t3, NULL, delayed_signal_thread, &mon);

    pthread_join(t1, NULL);
    pthread_join(t2, NULL);
    pthread_join(t3, NULL);

    monitor_destroy(&mon);
    printf("=== Test 4 Complete ===\n\n");
}

void* test5_waiter(void* arg) {
    monitor_t* mon = (monitor_t*)arg;
    printf("[Test 5] [Waiter %ld] Waiting...\n", pthread_self());
    monitor_wait(mon);
    printf("[Test 5] [Waiter %ld] Woke up!\n", pthread_self());
    return NULL;
}
void run_test5_multiple_waiters_one_signal() {
    printf("=== Test 5: Multiple waiters, one signal ===\n");
    monitor_t mon;
    monitor_init(&mon);

    pthread_t t1, t2;

    // Both threads will wait
    pthread_create(&t1, NULL, test5_waiter, &mon);
    pthread_create(&t2, NULL, test5_waiter, &mon);

    sleep(1);  // Let both threads enter wait state

    // Only one signal — only one thread should wake
    printf("[Test 5] [Signaler] Sending ONE signal...\n");
    monitor_signal(&mon);

    sleep(2);  // Give time for only one to wake

    // Now check that second thread is still waiting
    printf("[Test 5] [Signaler] Sending final signal to wake remaining waiter...\n");
    monitor_signal(&mon);

    pthread_join(t1, NULL);
    pthread_join(t2, NULL);

    monitor_destroy(&mon);
    printf("=== Test 5 Complete ===\n\n");
}

void* test6_waiter(void* arg) {
    monitor_t* mon = (monitor_t*)arg;
    printf("[Test 6] [Waiter] Waiting without signal (should block)...\n");
    monitor_wait(mon);  // should block forever
    printf("[Test 6] [Waiter] Woke up! ❌ (should not happen)\n");
    return NULL;
}

void run_test6_wait_without_signal() {
    printf("=== Test 6: Wait without signal ===\n");
    monitor_t mon;
    monitor_init(&mon);

    pthread_t t1;
    pthread_create(&t1, NULL, test6_waiter, &mon);

    // Sleep to confirm it's stuck
    sleep(3);
    printf("[Test 6] Waiter is still blocked ✅\n");

    pthread_cancel(t1); // forcibly stop the blocked thread
    pthread_join(t1, NULL);
    printf("=== Test 6 Complete ===\n\n");
}

void* test7_loop_thread(void* arg) {
    monitor_t* mon = (monitor_t*)arg;

    for (int i = 1; i <= 3; i++) {
        printf("[Test 7] [Waiter] Waiting (%d)...\n", i);
        monitor_wait(mon);
        printf("[Test 7] [Waiter] Woke up (%d)!\n", i);
    }

    return NULL;
}

void* test7_signal_loop(void* arg) {
    monitor_t* mon = (monitor_t*)arg;

    for (int i = 1; i <= 3; i++) {
        sleep(1);
        printf("[Test 7] [Signaler] Signaling (%d)...\n", i);
        monitor_signal(mon);
    }

    return NULL;
}

void run_test7_loop_wait_signal() {
    printf("=== Test 7: Interleaved wait-signal loop ===\n");
    monitor_t mon;
    monitor_init(&mon);

    pthread_t t1, t2;
    pthread_create(&t1, NULL, test7_loop_thread, &mon);
    pthread_create(&t2, NULL, test7_signal_loop, &mon);

    pthread_join(t1, NULL);
    pthread_join(t2, NULL);

    monitor_destroy(&mon);
    printf("=== Test 7 Complete ===\n\n");
}

void* test8_delayed_signal(void* arg) {
    sleep(2);
    printf("[Test 8] [Signaler] Sending signal after 2 seconds...\n");
    monitor_signal((monitor_t*)arg);
    return NULL;
}

void* test8_timed_wait(void* arg) {
    monitor_t* mon = (monitor_t*)arg;
    struct timespec start, end;

    clock_gettime(CLOCK_MONOTONIC, &start);
    printf("[Test 8] [Waiter] Waiting...\n");
    monitor_wait(mon);
    clock_gettime(CLOCK_MONOTONIC, &end);

    double elapsed = end.tv_sec - start.tv_sec +
                     (end.tv_nsec - start.tv_nsec) / 1e9;

    printf("[Test 8] [Waiter] Woke up after %.2f seconds\n", elapsed);
    return NULL;
}

void run_test8_timed_wait() {
    printf("=== Test 8: Timing check ===\n");
    monitor_t mon;
    monitor_init(&mon);

    pthread_t t1, t2;
    pthread_create(&t1, NULL, test8_timed_wait, &mon);
    pthread_create(&t2, NULL, test8_delayed_signal, &mon);

    pthread_join(t1, NULL);
    pthread_join(t2, NULL);

    monitor_destroy(&mon);
    printf("=== Test 8 Complete ===\n\n");
}
// === main() to run all tests ===
int main() {
    run_test1_basic_wait_signal();
    run_test2_early_signal();
    run_test3_reuse_monitor();
    run_test4_signal_twice_before_one_wait();
    run_test5_multiple_waiters_one_signal();
    run_test6_wait_without_signal();
    run_test7_loop_wait_signal();
    run_test8_timed_wait();
    printf("[All Tests Finished]\n");
    return 0;
}
