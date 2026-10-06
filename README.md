# Reduced Pulse Engine Fuel Costs

Scale down **pulse engine** fuel consumption in No Man's Sky - the fuel you burn
during a pulse jump, which you recharge with Tritium or Pyrite. Pick a
percentage at install time. Built natively on Linux with the
[AMUMSS Linux port](https://github.com/SavageCore/AMUMSS/tree/feat/linux-support).

The approach is ported from Cykron0271's
[Reduced Ship Launch Fuel Costs (Or Increased)](https://www.nexusmods.com/nomanssky/mods/3490)
(original mod by Lexman6 and Lo2k), retargeted from launch cost to pulse fuel.

## Usage

During installation, pick how much fuel pulse jumps should use.

| Variant | Factor | `SHIPJUMP1` (Pulse) | `SHIPJUMP_ALIEN` (Luminance) | `SHIPJUMP_SPEC` (Royal) | `SHIPJUMP_ROBO` (Robo) |
| --- | --- | --- | --- | --- | --- |
| *unmodified* | 1.00 | 1.0 | 0.5 | 1.0 | 1.0 |
| `Half` | 0.50 | 0.5 | 0.25 | 0.5 | 0.5 |
| `Quarter` | 0.25 | 0.25 | 0.125 | 0.25 | 0.25 |
| `Tenth` | 0.10 | 0.1 | 0.05 | 0.1 | 0.1 |

Each column is that engine's final `Ship_PulseDrive_MiniJumpFuelSpending`
multiplier. The italic row is the unmodified baseline, shown for reference only.

## Compatibility

Modifies
`METADATA/REALITY/TABLES/NMS_REALITY_GCTECHNOLOGYTABLE.MBIN` only. It may
conflict with any other mod editing that file, which is a lot of mods. The
generated patch is minimal: four `Bonus` values and nothing else, so
load-order conflicts with unrelated tech mods should be rare, but a mod that
rewrites the whole technology table will conflict outright.

**Upgrade technologies are not modified.** `UT_PULSEFUEL` (Instability Drive),
`PHOTONIX_CORE` (Photonix Core) and `SOLAR_SAIL` (Vesper Sail) all reduce pulse
fuel on top of the base engine and are deliberately left alone, so those
upgrades keep working exactly as in vanilla and any reduction they grant still
stacks on top of the variant you picked.

## Build (on Linux)

Requires a full AMUMSS install at `~/AMUMSS` (override with
`AMUMSS_HOME=...`) with `MBINCompiler-linux` fetched
(`linux/scripts/fetch_mbincompiler.sh` in the AMUMSS repo).

```sh
make release      # clean rebuild + verify + pack dist/ zip (default)
make verify       # sanity-check the built outputs
make clean        # remove build/ and dist/
make assets       # regenerate Nexus page images (needs assets/src/pulse-fuel.jpg)

make release VERSION=0.1.0   # override the version in the zip name
```

`VERSION` in the `Makefile` is currently **0.0.0**. It is a development build:
the generated patch is verified against the v7.04 technology table, and the
fuel drain change has been confirmed in game, but the shipped variants have not
been signed off yet. It becomes 0.1.0 in its own commit once they have.

`make build` temporarily stages the variant scripts into
`$(AMUMSS_HOME)/ModScript` (existing content moved aside and restored),
runs one `buildmod.sh --run-pipeline`, and collects the outputs.

`make verify` is the load-bearing step, not a formality. It asserts, per
variant, that each of the four techs got the requested value in the correct
`StatBonuses` slot, and that **exactly four** `Bonus` values were patched in
total. That last check exists because of how AMUMSS fails: a
`SPECIAL_KEY_WORDS` path that stops matching does not error, it silently
applies the change to every `StatBonuses` in the table (501 of them in v7.04)
and ships that. See the comment on `SPECIAL_KEY_WORDS` in
`src/pulsefuel.lua.in`.

## Release

`make release` creates `dist/Reduced Pulse Engine Fuel Costs <VERSION>.zip`,
which is the zip to import into
[Amethyst](https://github.com/ChrisDKN/Amethyst-Mod-Manager)/[Vortex](https://github.com/Nexus-Mods/Vortex)
or upload to Nexus. `fomod/` sits at the zip root, which is how mod managers
detect an installer.

## Game updates / versioning

The mod version is `VERSION` in the `Makefile`. The game version the scripts
target is `GameVersion` in `src/pulsefuel.lua.in`.

When No Man's Sky updates:

1. Fetch the new matching compiler from the AMUMSS repo (use
   `MBINCOMPILER_TAG=vX` to pin):
   `AMUMSS_HOME=~/AMUMSS linux/scripts/fetch_mbincompiler.sh`
   If the AMUMSS core itself changed, re-run the pipeline once so the
   linux patches re-verify (`apply_linux_patches.sh --verify`).
2. Bump `GameVersion` in `src/pulsefuel.lua.in`.
3. Bump `VERSION` in the `Makefile`.
4. Re-check the assumptions in the source table below (see below).
5. `make release`, import, deploy, test.

### Re-checking the source values after a game update

The four engine values and the `_index` they live at are game data, not
constants this mod owns. To re-derive them:

```sh
PAK=~/.local/share/Steam/steamapps/common/"No Man's Sky"/GAMEDATA/PCBANKS/NMSARC.Precache.pak
hgpaktool -O /tmp/probe -f "*NMS_REALITY_GCTECHNOLOGYTABLE.MBIN" "$PAK"
cd /tmp/probe/metadata/reality/tables
~/AMUMSS/MODBUILDER/MBINCompiler-linux -q -y -f -iMBIN nms_reality_gctechnologytable.mbin
```

Then find every tech carrying `Ship_PulseDrive_MiniJumpFuelSpending`:

```sh
python3 - <<'EOF'
import xml.etree.ElementTree as ET
t = ET.parse('nms_reality_gctechnologytable.MXML')
STAT = 'Ship_PulseDrive_MiniJumpFuelSpending'
for tech in t.getroot().find('Property').findall('Property'):
    p = {x.get('name'): x for x in tech.findall('Property')}
    tid = p.get('ID')
    sb = p.get('StatBonuses')
    if sb is None: continue
    for b in sb.findall('Property'):
        bp = {x.get('name'): x for x in b.findall('Property')}
        st = bp.get('Stat')
        if st is None: continue
        leaf = st.find('Property')
        if leaf is None or leaf.get('value') != STAT: continue
        print(f"{tid:18s} Bonus={bp['Bonus'].get('value'):10s} _index={b.get('_index')}")
EOF
```

Expected as of v7.04: the four `SHIPJUMP*` engines at `_index=1`, plus
`UT_PULSEFUEL` / `PHOTONIX_CORE` / `SOLAR_SAIL` at `_index=0` (which this mod
ignores). If the four engines move off `_index=1`, update `PULSE_BONUS_INDEX`
in the `Makefile` or `make verify` will fail loudly rather than quietly
patching the wrong stat.
