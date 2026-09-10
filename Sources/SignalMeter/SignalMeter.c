#include "SignalMeter.h"
#include <stdatomic.h>
#include <stdlib.h>
#include <math.h>
#include <time.h>
struct SGMeter { _Atomic uint64_t buffer; _Atomic uint64_t sound; _Atomic int invalid; };
SGMeter *sg_create(void) { return calloc(1, sizeof(SGMeter)); }
void sg_destroy(SGMeter *m) { free(m); }
void sg_consume(SGMeter *m, const float *samples, size_t count, uint64_t now) {
    if (!samples || !count) return;
    for (size_t i = 0; i < count; i++) {
        if (!isfinite(samples[i])) { atomic_store(&m->invalid, 1); break; }
        // Exact digital silence: even very quiet finite audio keeps the output open.
        if (samples[i] != 0.0f) { atomic_store(&m->sound, now); break; }
    }
    atomic_store(&m->buffer, now);
}
uint64_t sg_last_buffer(SGMeter *m) { return atomic_load(&m->buffer); }
uint64_t sg_last_sound(SGMeter *m) { return atomic_load(&m->sound); }
int sg_invalid(SGMeter *m) { return atomic_load(&m->invalid); }
uint64_t sg_now(void) { return clock_gettime_nsec_np(CLOCK_UPTIME_RAW); }
