# Reduced Pulse Engine Fuel Costs
# Builds the FOMOD installer (Half / Quarter / Tenth) with the
# AMUMSS Linux port.
#
# What it does: scales down Ship_PulseDrive_MiniJumpFuelSpending on the four
# ship pulse engine technologies (SHIPJUMP1, SHIPJUMP_ALIEN, SHIPJUMP_SPEC,
# SHIPJUMP_ROBO) in NMS_REALITY_GCTECHNOLOGYTABLE. That is the multiplier for
# pulse engine fuel, i.e. the fuel you burn during a pulse jump and recharge
# with Tritium or Pyrite. LOWER is cheaper. The upgrade technologies that cut
# pulse fuel on top of the engine (UT_PULSEFUEL, PHOTONIX_CORE, SOLAR_SAIL)
# are deliberately left untouched so upgrades keep working as in vanilla.
#
# Usage:
#   make release      clean rebuild + verify + pack dist/ zip (default)
#   make verify       sanity-check the built outputs
#   make assets       regenerate the Nexus page images (needs a screenshot)
#   make clean        remove build/ and dist/
#
# Override the AMUMSS install location if needed:
#   make AMUMSS_HOME=/path/to/AMUMSS release
#
# Game-update playbook (see README.md):
#   1. fetch latest MBINCompiler into AMUMSS_HOME
#   2. bump GameVersion in src/pulsefuel.lua.in to the new game version
#   3. make release VERSION=x.y.z   (bump the mod version too)
#   4. import + deploy + test in game

AMUMSS_HOME ?= $(HOME)/AMUMSS
AMUMSS_LINUX ?= $(HOME)/Git/AMUMSS/linux

# Mod version
VERSION      := 0.1.0

MOD_SET      := Reduced Pulse Engine Fuel Costs

SRC_TEMPLATE := src/pulsefuel.lua.in

BUILD := build
DIST  := dist
STAMP := $(BUILD)/.built

# Technology table this mod patches, relative to a built variant folder.
EXML_RELPATH := METADATA/REALITY/TABLES/NMS_REALITY_GCTECHNOLOGYTABLE.EXML

# Index of the Ship_PulseDrive_MiniJumpFuelSpending entry inside a ship
# engine's StatBonuses list, as of v7.04. All four ship engines carry it at
# index 1 (the three fuel-reducing upgrades carry it at index 0). verify
# asserts the patch landed here, so a game update that reorders the list
# fails loudly instead of quietly editing the wrong stat.
PULSE_BONUS_INDEX := 1

# Installer variants. Each variant label names the rendered script, the
# CreatedMODS folder, the fomod source folder and the in-game MOD_FILENAME
# suffix, so it must match ModuleConfig.xml exactly. Ordered most to least
# fuel reduction. There is deliberately no "vanilla" option: a variant that
# rewrote the values to the unmodified ones would still install a patch on the
# technology table, gaining nothing while adding conflict surface with every
# other mod that touches that file. To play unmodified, do not install it.
VARIANT   := Half Quarter Tenth
RENDERED  := $(addprefix $(BUILD)/,$(addsuffix .lua,$(VARIANT)))

# Per-tech final value of Ship_PulseDrive_MiniJumpFuelSpending to write. These
# are the vanilla values scaled by the variant factor, not one flat absolute
# number, so the Luminance engine keeps its built-in 50% efficiency advantage.
#
#              factor  SHIPJUMP1  SHIPJUMP_ALIEN  SHIPJUMP_SPEC  SHIPJUMP_ROBO
#   (vanilla)   1.00      1.0         0.5            1.0            1.0
#   Half         0.50      0.5         0.25           0.5            0.5
#   Quarter      0.25      0.25        0.125          0.25           0.25
#   Tenth        0.10      0.1         0.05           0.1            0.1
#
# There is deliberately no 0.0 (free fuel) variant. A zero multiplier does not
# work - it was tested in game and the pulse jump fails - so do not re-add one
# without re-testing from scratch. The lowest vanilla value for this stat is
# 0.20 (Vesper Sail), so 0.1 is already well past anything the game ships.
JUMP1_Half     := 0.5
JUMP1_Quarter  := 0.25
JUMP1_Tenth    := 0.1

JUMP_ALIEN_Half     := 0.25
JUMP_ALIEN_Quarter  := 0.125
JUMP_ALIEN_Tenth    := 0.05

JUMP_SPEC_Half     := 0.5
JUMP_SPEC_Quarter  := 0.25
JUMP_SPEC_Tenth    := 0.1

JUMP_ROBO_Half     := 0.5
JUMP_ROBO_Quarter  := 0.25
JUMP_ROBO_Tenth    := 0.1

# Descriptions shown in the FOMOD menu and in the in-game mod list.
# No "%" problem: these go through sed and zip.
DESC_Half     := 50% pulse engine fuel
DESC_Quarter  := 25% pulse engine fuel
DESC_Tenth    := 10% pulse engine fuel

# Base engine value per variant, for the verify summary line.
BASEVALS := $(foreach v,$(VARIANT),$(v)=$(JUMP1_$(v)))

# The four ship pulse engine technologies this mod patches. Keep in sync with
# PulseTechs in src/pulsefuel.lua.in (build checks this).
PULSE_TECHS := SHIPJUMP1 SHIPJUMP_ALIEN SHIPJUMP_SPEC SHIPJUMP_ROBO

# Which per-tech value variable holds each tech's multiplier.
JUMPVAR_SHIPJUMP1      := JUMP1
JUMPVAR_SHIPJUMP_ALIEN := JUMP_ALIEN
JUMPVAR_SHIPJUMP_SPEC  := JUMP_SPEC
JUMPVAR_SHIPJUMP_ROBO  := JUMP_ROBO

# Multiplier for one tech in one variant, e.g. jumptval Half SHIPJUMP_SPEC -> 0.5
jumptval = $($(JUMPVAR_$(2))_$(1))

# "TECH=value" pairs for one variant, for the awk value check.
jumpwant = $(foreach t,$(PULSE_TECHS),$(t)=$(call jumptval,$(1),$(t)))

# clean runs before build runs before verify, so release must not be parallel.
.NOTPARALLEL:

.PHONY: all release build verify assets clean

all: release

release: clean build verify
	@rm -rf "$(BUILD)/fomodz" && mkdir -p "$(BUILD)/fomodz/fomod" $(addprefix "$(BUILD)/fomodz/",$(VARIANT))
	@set -e; for v in $(VARIANT); do cp -a "$(BUILD)/$(MOD_SET) - $$v/METADATA" "$(BUILD)/fomodz/$$v/"; done
	@cp ModuleConfig.xml "$(BUILD)/fomodz/fomod/"
	@mkdir -p "$(DIST)" && rm -f "$(FOMOD_ZIP)" && cd "$(BUILD)/fomodz" && zip -qr "$(shell pwd)/$(FOMOD_ZIP)" fomod $(VARIANT)
	@echo "packed: $(FOMOD_ZIP)"
	@python3 -c "import xml.dom.minidom; xml.dom.minidom.parse('$(BUILD)/fomodz/fomod/ModuleConfig.xml'); print('ModuleConfig.xml: well-formed XML')"

# Render the variant scripts from the single template. One pattern rule for
# every variant: the file stem is the variant label, so $* drives the
# substitutions. The guard turns a typo in VARIANT into a loud failure rather
# than a script with a blank multiplier.
$(BUILD)/%.lua: $(SRC_TEMPLATE)
	@mkdir -p "$(BUILD)"
	@test -n "$(JUMP1_$*)" -a -n "$(JUMP_ALIEN_$*)" -a -n "$(JUMP_SPEC_$*)" -a -n "$(JUMP_ROBO_$*)" -a -n "$(DESC_$*)" || { echo "ERROR: unknown variant '$*' - add JUMP1_$*, JUMP_ALIEN_$*, JUMP_SPEC_$*, JUMP_ROBO_$* and DESC_$* to the Makefile" >&2; exit 1; }
	@sed -e "s/@VARIANT_LABEL@/$*/" -e "s/@JUMP1@/$(JUMP1_$*)/" -e "s/@JUMP_ALIEN@/$(JUMP_ALIEN_$*)/" -e "s/@JUMP_SPEC@/$(JUMP_SPEC_$*)/" -e "s/@JUMP_ROBO@/$(JUMP_ROBO_$*)/" -e "s/@DESC@/$(DESC_$*)/" "$(SRC_TEMPLATE)" > "$@"

# One pipeline run builds every variant as an individual mod.
build: $(RENDERED)
	@test -d "$(AMUMSS_HOME)/MODBUILDER" || (echo "ERROR: no AMUMSS install at $(AMUMSS_HOME) (set AMUMSS_HOME=...)" >&2; exit 1)
	@test -x "$(AMUMSS_HOME)/MODBUILDER/MBINCompiler-linux" || (echo "ERROR: run $(AMUMSS_LINUX)/scripts/fetch_mbincompiler.sh with AMUMSS_HOME=$(AMUMSS_HOME) first" >&2; exit 1)
	@mkdir -p "$(BUILD)"
	@set -e; \
	if [ -d "$(AMUMSS_HOME)/ModScript" ]; then mv "$(AMUMSS_HOME)/ModScript" "$(AMUMSS_HOME)/ModScript.makebak"; trap 'rm -rf "$(AMUMSS_HOME)/ModScript"; mv "$(AMUMSS_HOME)/ModScript.makebak" "$(AMUMSS_HOME)/ModScript"' EXIT; fi; \
	mkdir -p "$(AMUMSS_HOME)/ModScript"; \
	cp $(RENDERED) "$(AMUMSS_HOME)/ModScript/"; \
	AMUMSS_HOME="$(AMUMSS_HOME)" "$(AMUMSS_LINUX)/buildmod.sh" --run-pipeline; \
	rm -rf "$(AMUMSS_HOME)/ModScript"; \
	if [ -d "$(AMUMSS_HOME)/ModScript.makebak" ]; then mv "$(AMUMSS_HOME)/ModScript.makebak" "$(AMUMSS_HOME)/ModScript"; fi; \
	trap - EXIT
	@set -e; for v in $(VARIANT); do \
		rm -rf "$(BUILD)/$(MOD_SET) - $$v"; \
		mkdir -p "$(BUILD)/$(MOD_SET) - $$v"; \
		cp -a "$(AMUMSS_HOME)/CreatedMODS/$(MOD_SET) - $$v/METADATA" "$(BUILD)/$(MOD_SET) - $$v/"; \
	done
	@touch "$(STAMP)"
	@echo "built: $(foreach v,$(VARIANT),$(BUILD)/$(MOD_SET) - $(v) )"

# Single zip with a FOMOD installer menu (choose a fuel usage).
# fomod/ lives at the zip root (that is how managers detect installers).
# Version travels in the zip filename (Nexus convention).
FOMOD_ZIP := $(DIST)/$(MOD_SET) $(VERSION).zip

# Path to a variant's generated EXML.
exml = $(BUILD)/$(MOD_SET) - $(1)/$(EXML_RELPATH)

# One check chain per variant, expanded at make time so each value is baked in.
# The generated EXML is a minimal patch, keyed by _id rather than name="ID",
# and carries no StatsType leaf, so verify has two jobs:
#   1. each of the four techs got the value we asked for, in the right
#      StatBonuses slot
#   2. nothing ELSE got touched - the total Bonus count must be exactly 4.
#      This is the load-bearing check. If a SPECIAL_KEY_WORDS path ever stops
#      matching, AMUMSS silently applies the change to every StatBonuses in
#      the table (501 of them in v7.04) and ships that as the patch.
define VERIFY_VARIANT
test -f "$(call exml,$(1))" || { echo "MISSING $(1) EXML" >&2; exit 1; }; \
awk -v tag="$(1)" -v ntech="$(words $(PULSE_TECHS))" -v wantidx="$(PULSE_BONUS_INDEX)" -v want="$(call jumpwant,$(1))" \
 'BEGIN{n=split(want,W," ");for(i=1;i<=n;i++){split(W[i],kv,"=");want_v[kv[1]]=kv[2]+0}} \
  /name="Table" value="GcTechnology"/{if(match($$0,/_id="[^"]*"/)){x=substr($$0,RSTART+5,RLENGTH-6);if(x in want_v){t=x;ix=-1}}} \
  /name="StatBonuses" value="GcStatsBonus"/{if(match($$0,/_index="[^"]*"/)){ix=substr($$0,RSTART+8,RLENGTH-9)+0}} \
  /name="Bonus" value=/{total++;if(t!=""){if(match($$0,/value="[^"]*"/)){got[t]=substr($$0,RSTART+7,RLENGTH-8)+0};gotix[t]=ix}} \
  END{rc=0;for(k in want_v){if(!(k in got)){printf "MISSING %s bonus in %s\n",k,tag> "/dev/stderr";rc=1}else if(got[k]!=want_v[k]){printf "BAD %s bonus in %s: got %s want %s\n",k,tag,got[k],want_v[k]> "/dev/stderr";rc=1}else if(gotix[k]!=wantidx){printf "BAD %s StatBonuses index in %s: got %s want %s - the keyword path may have drifted onto another stat\n",k,tag,gotix[k],wantidx> "/dev/stderr";rc=1}};if(total!=ntech){printf "LEAK in %s: %s Bonus values patched, want %s - the keyword path is not matching and AMUMSS is rewriting the whole table\n",tag,total,ntech> "/dev/stderr";rc=1};exit rc}' \
 "$(call exml,$(1))" || { echo "VERIFY FAILED: $(1)" >&2; exit 1; }; \
if grep -q '!#' "$(call exml,$(1))"; then echo "marker tags present in $(1)" >&2; exit 1; fi
endef

verify: build
	@set -e; for v in $(VARIANT); do \
		for t in $(PULSE_TECHS); do \
			grep -qF "\"$$t\"," "$(BUILD)/$$v.lua" \
				|| { echo "ERROR: $$t is missing from PulseTechs in $(SRC_TEMPLATE) - PULSE_TECHS in the Makefile and the template have drifted apart" >&2; exit 1; }; \
		done; \
		kw=$$(grep -o '\["SPECIAL_KEY_WORDS"\][^}]*}' "$(BUILD)/$$v.lua" | head -1); \
		n=$$(printf '%s' "$$kw" | tr -cd ',' | wc -c); \
		n=$$((n + 1)); \
		if [ $$((n % 2)) -ne 0 ]; then \
			echo "ERROR: SPECIAL_KEY_WORDS in $(SRC_TEMPLATE) has $$n entries (odd)." >&2; \
			echo "       AMUMSS silently discards the last entry, the path stops matching, and" >&2; \
			echo "       the Bonus change is applied to EVERY StatBonuses in the table." >&2; \
			exit 1; \
		fi; \
	done
	@set -e; $(foreach v,$(VARIANT),$(call VERIFY_VARIANT,$(v));)
	@echo "verify: OK ($(BASEVALS) pulse engine multiplier, $(words $(PULSE_TECHS)) techs each, no marker tags)"

# Nexus page images from assets/src (Pillow required). Outputs are
# generated artifacts (gitignored) - reproducible via this target.
assets: assets/src/pulse-fuel.jpg assets/generate.py
	python3 assets/generate.py

clean:
	rm -rf "$(BUILD)" "$(DIST)"
