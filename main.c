#include <stdio.h>
#include <stdlib.h>
#include <dlfcn.h>
#include <string.h>
#include <unistd.h>

typedef const char* (*plugin_init_func_t)(int);
typedef const char* (*plugin_place_work_func_t)(const char*);
typedef void        (*plugin_attach_func_t)(const char* (*)(const char*));
typedef const char* (*plugin_fini_func_t)(void);
typedef const char* (*plugin_wait_finished_func_t)(void);

typedef struct {
    plugin_init_func_t init;
    plugin_fini_func_t fini;
    plugin_place_work_func_t place_work;
    plugin_attach_func_t attach;
    plugin_wait_finished_func_t wait_finished;
    char* name;
    void* handle;
} plugin_handle_t;

void print_helper(){
    printf("Usage: ./analyzer <queue_size> <plugin1> <plugin2> ... <pluginN>\n");
    printf("Arguments:\n");
    printf("  queue_size    Maximum number of items in each plugin's queue\n");
    printf("  plugin1..N    Names of plugins to load (without .so extension)\n");
    printf("Available plugins:\n");
    printf("  logger        - Logs all strings that pass through\n");
    printf("  typewriter    - Simulates typewriter effect with delays\n");
    printf("  uppercaser    - Converts strings to uppercase\n");
    printf("  rotator       - Move every character to the right. Last character moves to the beginning.\n");
    printf("  flipper       - Reverses the order of characters\n");
    printf("  expander      - Expands each character with spaces\n");
    printf("Example:\n");
    printf("  ./analyzer 20 uppercaser rotator logger\n");
    printf("  echo 'hello' | ./analyzer 20 uppercaser rotator logger\n");
    printf("  echo '<END>' | ./analyzer 20 uppercaser rotator logger\n");

}
int main(int argc, char* argv[]){
    printf("hi0");
    if(argc < 2){
        fprintf(stderr, "No arguments were send\n");
        print_helper();
        exit(1);
    }
    int queueSize = atoi(argv[1]);
    if(queueSize == 0){
        fprintf(stderr, "Queue size is not valid\n");
        print_helper();
        exit(1);
    }
    int pluginCount = argc - 2;
    plugin_handle_t plugins[pluginCount];
    //construct the filename by appending .so
    for(int i = 2; i<argc; i++){
        char fileName[256];
        snprintf(fileName, sizeof(fileName), "%s.so", argv[i]);
        void* handle = dlopen(fileName,RTLD_NOW | RTLD_LOCAL);
        plugin_init_func_t init = (plugin_init_func_t)dlsym(handle, "plugin_init");
        if(!init){
            fprintf(stderr,"plugin_init not found %s\n",dlerror());
            exit(1);
        }
        plugin_place_work_func_t placeWorkFunc = (plugin_place_work_func_t)dlsym(handle, "plugin_place_work");
        if(!placeWorkFunc){
            fprintf(stderr,"plugin_place_work not found %s\n",dlerror());
            exit(1);
        }
        plugin_attach_func_t attachFunc = (plugin_attach_func_t)dlsym(handle, "plugin_attach");
        if(!attachFunc){
            fprintf(stderr,"plugin_attach not found %s\n",dlerror());
            exit(1);
        }
        plugin_fini_func_t finiFunc = (plugin_fini_func_t)dlsym(handle, "plugin_fini");
        if(!finiFunc){
            fprintf(stderr,"plugin_fini not found %s\n",dlerror());
            exit(1);
        }
        plugin_wait_finished_func_t waitFinishedFunc = (plugin_wait_finished_func_t)dlsym(handle, "plugin_wait_finished");
        if(!waitFinishedFunc){
            fprintf(stderr,"plugin_wait_finished not found %s\n",dlerror());
            exit(1);
        }
        plugin_handle_t plugin;
        plugin.init = init;
        plugin.place_work = placeWorkFunc;
        plugin.attach = attachFunc;
        plugin.fini = finiFunc;
        plugin.wait_finished = waitFinishedFunc;
        plugin.name = strdup(argv[i]);
        plugin.handle = handle;
        plugins[i - 2] = plugin;
    }
    //initialize all the plugins 
    for(int i =0; i<pluginCount; i++){
        const char* err = plugins[i].init(queueSize);
        if (err != NULL) {
            fprintf(stderr, "Failed to initialize plugin %s: %s\n", plugins[i].name, err);
            // Optionally: cleanup and exit
            exit(2);
        }
    }
    //step 4: attach plugins together
    for(int i= 0; i<pluginCount-1;i++){
        plugins[i].attach(plugins[i+1].place_work);
    }
    FILE *in = stdin;
    // If stdin is *not* a terminal (e.g., VS Code launch gave you nothing), fall back to the real tty
    //fprintf(stdin);

    if (!isatty(fileno(stdin))) {
        FILE *tty = fopen("/dev/tty", "r");
        if (tty) in = tty;
    }
    //Read Input from STDIN
    char line[1024];
    while (fgets(line, sizeof(line), stdin)) {
        printf(line);
        // Remove trailing newline
        line[strcspn(line, "\n")] = 0;

        // Duplicate string because place_work takes ownership
        char* input = strdup(line);

        plugins[0].place_work(input);

        if (strcmp(line, "<END>") == 0) {
            break;
        }
    }
    for (int i = 0; i < pluginCount; i++) {
        const char* err = plugins[i].wait_finished();
        if (err != NULL) {
            fprintf(stderr, "Error waiting for plugin %s: %s\n", plugins[i].name, err);
        }
    }
    for (int i = 0; i < pluginCount; i++) {
        plugins[i].fini();
        dlclose(plugins[i].handle);
        free(plugins[i].name);
    }
    printf("Pipeline shutdown complete\n");
    return 0;
}