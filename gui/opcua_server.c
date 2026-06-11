/*
 * opcua_server.c — minimal OPC UA server bridge for ThermoTwin-F.
 *
 * Wraps open62541 with a flat C API callable from Fortran via iso_c_binding.
 * The server runs non-threaded: ua_server_iterate() is called each GUI timer
 * tick (~4 Hz) to process pending OPC UA network events without blocking.
 *
 * Address space layout:
 *   Root > Objects > ThermoTwin > <CATEGORY> > <TAG>
 * where <CATEGORY> is the first component of the dot-separated tag name
 * (e.g. "GRID" from "GRID.FREQ_HZ").  Tags are Double AnalogItems with
 * EngineeringUnits populated from the units string.
 *
 * Tested with MinGW-w64 / gfortran on Windows 10/11.
 * Link flags required: -lws2_32 -liphlpapi
 */

#include "open62541.h"
#include <string.h>
#include <stdio.h>

/* ------------------------------------------------------------------ */
/*  Internal state                                                      */
/* ------------------------------------------------------------------ */

#define MAX_TAGS   256
#define TAG_NAMELEN 64
#define TAG_UNITLEN 16

typedef struct {
    char name[TAG_NAMELEN];
    char units[TAG_UNITLEN];
    UA_NodeId node_id;
    int registered;
} TagEntry;

static UA_Server   *g_server  = NULL;
static TagEntry     g_tags[MAX_TAGS];
static int          g_n_tags  = 0;
static int          g_running = 0;

/* ------------------------------------------------------------------ */
/*  Helpers                                                             */
/* ------------------------------------------------------------------ */

static TagEntry *find_tag(const char *name)
{
    int i;
    for (i = 0; i < g_n_tags; i++) {
        if (strncmp(g_tags[i].name, name, TAG_NAMELEN - 1) == 0)
            return &g_tags[i];
    }
    return NULL;
}

/* Return or create the folder node for a category string (e.g. "GRID"). */
static UA_NodeId ensure_category(const char *cat)
{
    /* We look for an existing Object node child of ThermoTwin folder. */
    char search[TAG_NAMELEN];
    strncpy(search, cat, TAG_NAMELEN - 1);
    search[TAG_NAMELEN - 1] = '\0';

    UA_NodeId cat_id = UA_NODEID_STRING_ALLOC(1, search);
    /* Attempt a browse to see if it exists */
    UA_BrowseDescription bd;
    UA_BrowseDescription_init(&bd);
    bd.nodeId = UA_NODEID_STRING(1, "ThermoTwin");
    bd.browseDirection = UA_BROWSEDIRECTION_FORWARD;
    bd.includeSubtypes = UA_TRUE;
    bd.nodeClassMask = UA_NODECLASS_OBJECT;
    bd.resultMask = UA_BROWSERESULTMASK_BROWSENAME;

    UA_BrowseResult br = UA_Server_browse(g_server, 0, &bd);
    int found = 0;
    if (br.statusCode == UA_STATUSCODE_GOOD) {
        UA_UInt32 i;
        for (i = 0; i < br.referencesSize; i++) {
            if (strncmp((char*)br.references[i].browseName.name.data,
                        cat, br.references[i].browseName.name.length) == 0) {
                found = 1;
                break;
            }
        }
    }
    UA_BrowseResult_clear(&br);
    UA_NodeId_clear(&cat_id);

    if (found) {
        return UA_NODEID_STRING_ALLOC(1, search);
    }

    /* Create the folder */
    UA_ObjectAttributes oa = UA_ObjectAttributes_default;
    oa.displayName = UA_LOCALIZEDTEXT("en-US", search);
    UA_NodeId parent  = UA_NODEID_STRING(1, "ThermoTwin");
    UA_NodeId ref_id  = UA_NODEID_NUMERIC(0, UA_NS0ID_ORGANIZES);
    UA_NodeId type_id = UA_NODEID_NUMERIC(0, UA_NS0ID_FOLDERTYPE);
    UA_QualifiedName qn = UA_QUALIFIEDNAME(1, search);
    UA_NodeId new_id   = UA_NODEID_STRING_ALLOC(1, search);

    UA_Server_addObjectNode(g_server, new_id, parent, ref_id, qn,
                            type_id, oa, NULL, NULL);
    return UA_NODEID_STRING_ALLOC(1, search);
}

/* Register a new tag node under its category folder. */
static void register_tag(TagEntry *te)
{
    char cat[TAG_NAMELEN];
    char *dot;

    strncpy(cat, te->name, TAG_NAMELEN - 1);
    cat[TAG_NAMELEN - 1] = '\0';
    dot = strchr(cat, '.');
    if (dot) *dot = '\0';

    UA_NodeId parent = ensure_category(cat);

    UA_VariableAttributes va = UA_VariableAttributes_default;
    va.displayName = UA_LOCALIZEDTEXT("en-US", (char*)te->name);
    va.description = UA_LOCALIZEDTEXT("en-US", (char*)te->units);
    va.dataType = UA_TYPES[UA_TYPES_DOUBLE].typeId;
    va.accessLevel = UA_ACCESSLEVELMASK_READ;

    UA_Double zero = 0.0;
    UA_Variant_setScalar(&va.value, &zero, &UA_TYPES[UA_TYPES_DOUBLE]);

    UA_NodeId var_id  = UA_NODEID_STRING_ALLOC(1, (char*)te->name);
    UA_QualifiedName qn = UA_QUALIFIEDNAME(1, (char*)te->name);
    UA_NodeId ref_id  = UA_NODEID_NUMERIC(0, UA_NS0ID_ORGANIZES);
    UA_NodeId type_id = UA_NODEID_NUMERIC(0, UA_NS0ID_BASEDATAVARIABLETYPE);

    UA_StatusCode sc = UA_Server_addVariableNode(
        g_server, var_id, parent, ref_id, qn,
        type_id, va, NULL, NULL);

    UA_NodeId_clear(&parent);
    UA_NodeId_clear(&var_id);

    te->registered = (sc == UA_STATUSCODE_GOOD) ? 1 : 0;
}

/* ------------------------------------------------------------------ */
/*  Public C API (called from Fortran)                                  */
/* ------------------------------------------------------------------ */

int ua_server_start(int port)
{
    if (g_server) return 0;   /* already running */

    UA_ServerConfig *cfg;
    g_server = UA_Server_new();
    if (!g_server) return -1;

    cfg = UA_Server_getConfig(g_server);
    UA_ServerConfig_setMinimal(cfg, (UA_UInt16)port, NULL);

    /* Application description */
    UA_String_clear(&cfg->applicationDescription.applicationUri);
    cfg->applicationDescription.applicationUri =
        UA_STRING_ALLOC("urn:thermotwin-f:ThermoTwin");
    UA_LocalizedText_clear(&cfg->applicationDescription.applicationName);
    cfg->applicationDescription.applicationName =
        UA_LOCALIZEDTEXT_ALLOC("en-US", "ThermoTwin-F Digital Twin");

    /* Root ThermoTwin folder */
    UA_ObjectAttributes oa = UA_ObjectAttributes_default;
    oa.displayName = UA_LOCALIZEDTEXT("en-US", "ThermoTwin");
    UA_NodeId folder_id = UA_NODEID_STRING_ALLOC(1, "ThermoTwin");
    UA_NodeId parent    = UA_NODEID_NUMERIC(0, UA_NS0ID_OBJECTSFOLDER);
    UA_NodeId ref_id    = UA_NODEID_NUMERIC(0, UA_NS0ID_ORGANIZES);
    UA_NodeId type_id   = UA_NODEID_NUMERIC(0, UA_NS0ID_FOLDERTYPE);
    UA_QualifiedName qn = UA_QUALIFIEDNAME(1, "ThermoTwin");
    UA_Server_addObjectNode(g_server, folder_id, parent, ref_id, qn,
                            type_id, oa, NULL, NULL);
    UA_NodeId_clear(&folder_id);

    memset(g_tags, 0, sizeof(g_tags));
    g_n_tags  = 0;
    g_running = 1;

    UA_StatusCode sc = UA_Server_run_startup(g_server);
    if (sc != UA_STATUSCODE_GOOD) {
        UA_Server_delete(g_server);
        g_server  = NULL;
        g_running = 0;
        return -2;
    }
    return 0;
}

void ua_server_stop(void)
{
    if (!g_server) return;
    UA_Server_run_shutdown(g_server);
    UA_Server_delete(g_server);
    g_server  = NULL;
    g_running = 0;
    g_n_tags  = 0;
}

/* Called each GUI timer tick: process network events without blocking. */
void ua_server_iterate(void)
{
    if (!g_server || !g_running) return;
    UA_Server_run_iterate(g_server, false);
}

/* Write or register+write a tag value. */
void ua_tag_write(const char *name, double value, const char *units)
{
    TagEntry *te;
    if (!g_server) return;

    te = find_tag(name);
    if (!te) {
        if (g_n_tags >= MAX_TAGS) return;
        te = &g_tags[g_n_tags++];
        strncpy(te->name,  name,  TAG_NAMELEN  - 1);
        strncpy(te->units, units, TAG_UNITLEN - 1);
        te->name[TAG_NAMELEN  - 1] = '\0';
        te->units[TAG_UNITLEN - 1] = '\0';
        te->registered = 0;
        register_tag(te);
    }

    if (!te->registered) return;

    UA_Variant val;
    UA_Variant_init(&val);
    UA_Variant_setScalar(&val, &value, &UA_TYPES[UA_TYPES_DOUBLE]);
    UA_NodeId nid = UA_NODEID_STRING(1, (char*)te->name);
    UA_Server_writeValue(g_server, nid, val);
}

/* Return 1 if server is active, 0 otherwise (for HMI indicator). */
int ua_server_active(void)
{
    return (g_server && g_running) ? 1 : 0;
}
