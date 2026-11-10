/* Offline GUI backend. Enable WITH_OPCUA=1 to link the real server. */
#include <stdio.h>

int ua_server_start(int port) {
    (void)port;
    puts("OPC UA disabled in this build (enable WITH_OPCUA=1 to include it).");
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
