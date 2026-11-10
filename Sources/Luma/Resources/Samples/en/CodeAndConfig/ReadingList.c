#include <stdbool.h>
#include <stdio.h>

struct Document {
    const char *title;
    bool read;
};

int main(void) {
    struct Document note = {"Luma", false};
    printf("Continue reading: %s\n", note.title);
    return 0;
}
