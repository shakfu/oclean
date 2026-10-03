OCAMLOPT ?= ocamlopt
BUILD    ?= build
PREFIX   ?= $(HOME)/.local
FLAGS    := -w +a-4-9-40-41-42-44-45-70 -strict-sequence -I $(BUILD) -I +unix
LIBS     := unix.cmxa

# Modules in dependency order.
LIB   := src/util.ml src/glob.ml src/options.ml src/target.ml src/preset.ml \
         src/scan.ml src/delete.ml src/style.ml src/report.ml src/config.ml
APP   := bin/progress.ml bin/cli.ml
TESTS := test/harness.ml test/test_util.ml test/test_glob.ml test/test_preset.ml \
         test/test_scan.ml test/test_report.ml test/test_config.ml test/test_delete.ml \
         test/test_cli.ml test/test_progress.ml test/test_main.ml test/run_tests.ml

cmx = $(addprefix $(BUILD)/,$(notdir $(1:.ml=.cmx)))

# Compile each file to $(BUILD), its .mli first when there is one.
define compile
	@mkdir -p $(BUILD)
	@for f in $(1); do \
	  m=$(BUILD)/$$(basename $${f%.ml}); \
	  if [ -f $${f}i ]; then $(OCAMLOPT) $(FLAGS) -c -o $$m.cmi $${f}i || exit 1; fi; \
	  $(OCAMLOPT) $(FLAGS) -c -o $$m.cmx $$f || exit 1; \
	done
endef

.PHONY: all test clean install

all: oclean

oclean: $(LIB) $(wildcard src/*.mli) $(APP) $(wildcard bin/*.mli) bin/main.ml
	$(call compile,$(LIB) $(APP) bin/main.ml)
	$(OCAMLOPT) $(FLAGS) -o $@ $(LIBS) $(call cmx,$(LIB) $(APP) bin/main.ml)

$(BUILD)/run_tests: oclean $(TESTS)
	$(call compile,$(TESTS))
	$(OCAMLOPT) $(FLAGS) -o $@ $(LIBS) $(call cmx,$(LIB) $(APP) $(TESTS))

test: $(BUILD)/run_tests
	OCLEAN=$(CURDIR)/oclean $(BUILD)/run_tests

install: oclean
	install -Dm755 oclean $(DESTDIR)$(PREFIX)/bin/oclean

clean:
	rm -rf oclean $(BUILD)
