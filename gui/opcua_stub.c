/* Explicit offline GUI backend; no OPC UA sockets or telemetry exposure.

   Link ONLY into thermotwin-gui-offline.exe. The regular make gui target
   remains linked against the real pinned open62541 implementation.
*/
#include <stdio.h>

int ua_server_start(int port) {
    (void)port;
    puts("OPC UA disabled: this is the explicitly offline GUI build.");
    return 0;
}
void ua_server_stop(void) {}
void ua_server_iterate(void) {}
void ua_tag_write(const char *name, double value, const char *units) {
    (void)name;
    (void)value;
    (void)units;
}
int ua_server_active(void) { return 0; }
