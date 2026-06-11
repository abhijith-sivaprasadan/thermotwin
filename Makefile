# ===========================================================================
# Makefile for ThermoTwin-F (gfortran, no fpm required)
#
#   make            # build the thermotwin executable
#   make tests      # build the unit-test programs into build/tests/
#   make check      # build and run the full test suite
#   make debug      # build with bounds-checking and warnings
#   make run        # build, then run the design-point case
#   make gui        # build the optional native Windows GUI launcher
#   make gui-debug  # build the GUI with a console attached for diagnostics
#   make clean      # remove build artefacts
#
# fpm users can ignore this file and simply use `fpm build` / `fpm test`.
# ===========================================================================

FC      = gfortran
CXX     = g++
BUILD   := build
SRC     := src
APP     := app
TEST    := test

FFLAGS_COMMON := -J $(BUILD) -I $(BUILD) -ffree-line-length-none -std=f2008
FFLAGS_REL    := -O2
FFLAGS_DBG    := -O0 -g -fcheck=all -fbacktrace -Wall -Wextra -fimplicit-none
FFLAGS        := $(FFLAGS_COMMON) $(FFLAGS_REL)
CXXFLAGS_REL  := -O2 -std=c++17 -Wall -Wextra
CXXFLAGS_DBG  := -O0 -g -std=c++17 -Wall -Wextra

# Modules in strict dependency order.
MODS := precision_kinds constants types utilities fluid_properties ambient \
        compressor combustor turbine shaft_generator cycle_solver degradation \
        transient_thermal sensor_model uncertainty_analysis diagnostics_solver \
        csv_io sensitivity_driver off_design hrsg steam_cycle \
        tag_bus engine_state market_data fleet_dispatch grid_dynamics dispatch_agc plant_economics engine_core \
        scenario_runner opcua_bridge

OBJS := $(addprefix $(BUILD)/,$(addsuffix .o,$(MODS)))
TEST_SRCS := $(wildcard $(TEST)/test_*.f90)
TEST_BINS := $(patsubst $(TEST)/%.f90,$(BUILD)/tests/%,$(TEST_SRCS))

EXE := thermotwin
GUI_EXE := thermotwin-gui.exe
GUI_DEBUG_EXE := thermotwin-gui-debug.exe
GUI_ICON := gui/app_icon.ico
GUI_RES := $(BUILD)/gui_icon.res
GUI_NATIVE_OBJ := $(BUILD)/hmi_native_draw.o
OPCUA_OBJ := $(BUILD)/open62541.o $(BUILD)/opcua_server.o

OPCUA_VER := v1.5.4
OPCUA_URL := https://github.com/open62541/open62541/releases/download/$(OPCUA_VER)

.PHONY: all tests check debug run gui gui-debug clean download-opcua
.SECONDEXPANSION:

all: $(EXE)

$(BUILD):
	@mkdir -p $(BUILD)

# Pattern rule: each module object depends on its source. Ordering is enforced
# by the explicit prerequisite chain below.
$(BUILD)/%.o: $(SRC)/%.f90 | $(BUILD)
	$(FC) $(FFLAGS) -c $< -o $@

# Engine modules live one level down in src/engine/.
$(BUILD)/%.o: $(SRC)/engine/%.f90 | $(BUILD)
	$(FC) $(FFLAGS) -c $< -o $@

# Explicit inter-module dependencies (so parallel make is still correct).
$(BUILD)/constants.o:            $(BUILD)/precision_kinds.o
$(BUILD)/types.o:                $(BUILD)/precision_kinds.o
$(BUILD)/utilities.o:            $(BUILD)/precision_kinds.o $(BUILD)/constants.o
$(BUILD)/fluid_properties.o:     $(BUILD)/precision_kinds.o $(BUILD)/constants.o
$(BUILD)/ambient.o:              $(BUILD)/types.o $(BUILD)/utilities.o
$(BUILD)/compressor.o:           $(BUILD)/fluid_properties.o $(BUILD)/utilities.o
$(BUILD)/combustor.o:            $(BUILD)/fluid_properties.o $(BUILD)/utilities.o
$(BUILD)/turbine.o:              $(BUILD)/fluid_properties.o $(BUILD)/utilities.o
$(BUILD)/shaft_generator.o:      $(BUILD)/utilities.o
$(BUILD)/cycle_solver.o:         $(BUILD)/ambient.o $(BUILD)/compressor.o $(BUILD)/combustor.o \
                                 $(BUILD)/turbine.o $(BUILD)/shaft_generator.o $(BUILD)/fluid_properties.o
$(BUILD)/degradation.o:          $(BUILD)/types.o $(BUILD)/utilities.o
$(BUILD)/transient_thermal.o:    $(BUILD)/types.o $(BUILD)/utilities.o
$(BUILD)/sensor_model.o:         $(BUILD)/types.o $(BUILD)/utilities.o
$(BUILD)/uncertainty_analysis.o: $(BUILD)/cycle_solver.o $(BUILD)/utilities.o
$(BUILD)/diagnostics_solver.o:   $(BUILD)/cycle_solver.o $(BUILD)/degradation.o
$(BUILD)/csv_io.o:               $(BUILD)/types.o $(BUILD)/utilities.o
$(BUILD)/sensitivity_driver.o:   $(BUILD)/cycle_solver.o
$(BUILD)/off_design.o:           $(BUILD)/cycle_solver.o $(BUILD)/ambient.o $(BUILD)/types.o
$(BUILD)/hrsg.o:                 $(BUILD)/fluid_properties.o
$(BUILD)/steam_cycle.o:          $(BUILD)/hrsg.o
$(BUILD)/market_data.o:          $(BUILD)/engine_state.o
$(BUILD)/fleet_dispatch.o:       $(BUILD)/engine_state.o
$(BUILD)/tag_bus.o:              $(BUILD)/precision_kinds.o
$(BUILD)/engine_state.o:         $(BUILD)/precision_kinds.o
$(BUILD)/grid_dynamics.o:        $(BUILD)/engine_state.o $(BUILD)/off_design.o
$(BUILD)/dispatch_agc.o:         $(BUILD)/engine_state.o
$(BUILD)/plant_economics.o:      $(BUILD)/engine_state.o
$(BUILD)/engine_core.o:          $(BUILD)/engine_state.o $(BUILD)/grid_dynamics.o \
                                  $(BUILD)/dispatch_agc.o $(BUILD)/plant_economics.o \
                                  $(BUILD)/tag_bus.o $(BUILD)/cycle_solver.o \
                                  $(BUILD)/types.o $(BUILD)/constants.o \
                                  $(BUILD)/off_design.o $(BUILD)/fluid_properties.o \
                                  $(BUILD)/hrsg.o $(BUILD)/steam_cycle.o \
                                  $(BUILD)/fleet_dispatch.o $(BUILD)/market_data.o
$(BUILD)/scenario_runner.o:      $(BUILD)/engine_core.o $(BUILD)/engine_state.o \
                                 $(BUILD)/dispatch_agc.o $(BUILD)/tag_bus.o
$(BUILD)/opcua_bridge.o:         $(BUILD)/precision_kinds.o

$(EXE): $(OBJS) $(BUILD)/main.o
	$(FC) $(FFLAGS) $(OBJS) $(BUILD)/main.o -o $@

$(BUILD)/main.o: $(APP)/main.f90 $(OBJS) | $(BUILD)
	$(FC) $(FFLAGS) -c $< -o $@

tests: $(TEST_BINS)

$(BUILD)/tests:
	@mkdir -p $(BUILD)/tests

$(BUILD)/tests/%: $(TEST)/%.f90 $(OBJS) | $(BUILD)/tests
	$(FC) $(FFLAGS) -I $(TEST) -c $< -o $(BUILD)/$*.o
	$(FC) $(FFLAGS) $(OBJS) $(BUILD)/$*.o -o $@

check: tests $(EXE)
	@python scripts/run_tests.py

debug: FFLAGS := $(FFLAGS_COMMON) $(FFLAGS_DBG)
debug: clean all

run: $(EXE)
	./$(EXE) run cases/design_point.csv output/results_design_point.csv

gui: $(GUI_EXE)

$(BUILD)/hmi_native_draw.o: gui/hmi_native_draw.cpp | $(BUILD)
	$(CXX) $(CXXFLAGS_REL) -c $< -o $@

# open62541 amalgam — compiled once with -O1 (full optimisation is slow)
$(BUILD)/open62541.o: gui/open62541.c | $(BUILD)
	gcc -O1 -std=c99 -DUA_ARCHITECTURE_WIN32 -c $< -o $@ 2>/dev/null

# OPC UA server C wrapper
$(BUILD)/opcua_server.o: gui/opcua_server.c gui/open62541.h | $(BUILD)
	gcc -O2 -DUA_ARCHITECTURE_WIN32 -c $< -o $@

$(BUILD)/opcua_bridge.o: $(SRC)/engine/opcua_bridge.f90 | $(BUILD)
	$(FC) $(FFLAGS) -c $< -o $@

$(GUI_EXE): gui/gui_win32.f90 $(OBJS) $(GUI_RES) $(GUI_NATIVE_OBJ) $(OPCUA_OBJ)
	$(FC) $(FFLAGS_COMMON) $(FFLAGS_REL) $(OBJS) $< $(GUI_NATIVE_OBJ) $(OPCUA_OBJ) $(GUI_RES) -o $@ -mwindows -lstdc++ -lgdiplus -luser32 -lgdi32 -lcomctl32 -lkernel32 -lws2_32 -liphlpapi

gui-debug: $(GUI_DEBUG_EXE)

$(GUI_DEBUG_EXE): gui/gui_win32.f90 $(OBJS) $(GUI_RES) $(GUI_NATIVE_OBJ) $(OPCUA_OBJ)
	$(FC) $(FFLAGS_COMMON) $(FFLAGS_DBG) $(OBJS) $< $(GUI_NATIVE_OBJ) $(OPCUA_OBJ) $(GUI_RES) -o $@ -lstdc++ -lgdiplus -luser32 -lgdi32 -lcomctl32 -lkernel32 -lws2_32 -liphlpapi

$(GUI_RES): gui/app_icon.rc $(GUI_ICON) | $(BUILD)
	windres $< -O coff -o $@

$(GUI_ICON): scripts/generate_gui_icon.py
	python scripts/generate_gui_icon.py $@

clean:
	rm -rf $(BUILD) $(EXE) $(GUI_EXE) $(GUI_DEBUG_EXE)

download-opcua:
	curl -L $(OPCUA_URL)/open62541.c -o gui/open62541.c
	curl -L $(OPCUA_URL)/open62541.h -o gui/open62541.h
	sed -i 's|^#define UA_ARCHITECTURE_POSIX|/* #undef UA_ARCHITECTURE_POSIX */|' gui/open62541.h
	sed -i 's|^\/\* #undef UA_ARCHITECTURE_WIN32 \*\/|#define UA_ARCHITECTURE_WIN32|' gui/open62541.h
	sed -i 's|^#define UA_ENABLE_ENCRYPTION_MBEDTLS|/* #undef UA_ENABLE_ENCRYPTION_MBEDTLS */|' gui/open62541.h
