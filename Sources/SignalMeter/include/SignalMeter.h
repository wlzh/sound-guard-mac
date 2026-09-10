#ifndef SIGNAL_METER_H
#define SIGNAL_METER_H
#include <stdint.h>
#include <stddef.h>
typedef struct SGMeter SGMeter;
SGMeter *sg_create(void);
void sg_destroy(SGMeter *meter);
void sg_consume(SGMeter *meter, const float *samples, size_t count, uint64_t now);
uint64_t sg_last_buffer(SGMeter *meter);
uint64_t sg_last_sound(SGMeter *meter);
int sg_invalid(SGMeter *meter);
uint64_t sg_now(void);
#endif
