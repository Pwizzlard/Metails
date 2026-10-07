import pathlib, tempfile
import records

ME = 'Player-1,"Skin-ClassicBetaPvP2-",0x511,0x80000000'
PET = 'Pet-7,"Kitty",0x1111,0x80000000'
MOB = 'Creature-9,"Hogger",0x10a48,0x80000000'
ADV = 'Creature-9,0000000000000000,3400,3726,115,0,981,0,0,0,0,1704,1704,0,2890.55,-810.98,1420,0.3840,30'
LOG = f"""10/7/2026 09:12:03.688-4  COMBAT_LOG_VERSION,22,ADVANCED_LOG_ENABLED,0,BUILD_VERSION,1.60.1,PROJECT_ID,18
10/7/2026 09:12:10.000-4  ENCOUNTER_START,1,"Hogger",1,5,36
10/7/2026 09:12:10.500-4  SPELL_DAMAGE,{ME},{MOB},8724,"Ambush",0x1,{ADV},253,337,-1,1,0,0,0,nil,nil,nil,ST
10/7/2026 09:12:11.200-4  SWING_DAMAGE,{ME},{MOB},{ADV},73,96,-1,1,0,0,0,nil,nil,nil
10/7/2026 09:12:12.100-4  SWING_DAMAGE,{PET},{MOB},{ADV},10,10,-1,1,0,0,0,nil,nil,nil
10/7/2026 09:12:12.900-4  SWING_DAMAGE,{MOB},{ME},{ADV},40,40,-1,1,0,0,0,nil,nil,nil
10/7/2026 09:12:13.000-4  ENCOUNTER_END,1,"Hogger",1,5,1,3000
10/7/2026 09:20:00.000-4  ENCOUNTER_START,1,"Hogger",1,5,36
10/7/2026 09:20:01.000-4  SWING_DAMAGE,{ME},{MOB},{ADV},500,500,-1,1,0,0,0,nil,nil,nil
10/7/2026 09:20:02.000-4  UNIT_DIED,0000000000000000,nil,0x80000000,0x80000000,Player-1,"Skin-ClassicBetaPvP2-",0x511,0x80000000,0
10/7/2026 09:20:03.000-4  ENCOUNTER_END,1,"Hogger",1,5,1,3000
10/7/2026 09:30:00.000-4  ENCOUNTER_START,2,"Edwin",1,5,36
10/7/2026 09:30:01.000-4  SWING_DAMAGE,{ME},{MOB},{ADV},999,999,-1,1,0,0,0,nil,nil,nil
10/7/2026 09:30:03.000-4  ENCOUNTER_END,2,"Edwin",1,5,0,3000
"""

with tempfile.TemporaryDirectory() as d:
    log = pathlib.Path(d) / "WoWCombatLog-1.txt"
    log.write_text(LOG, encoding="utf-8")
    recs = records.build([str(log)])
    assert list(recs) == ["Skin"], recs
    hog = recs["Skin"]["Hogger"]
    assert hog["best"]["total"] == 336 and hog["best"]["time"] == 3.0 and hog["best"]["curve"] == [253, 326, 336, 336], hog["best"]
    assert hog["best"]["date"] == "2026-10-07" and not hog["best"]["died"]
    assert hog["last"]["total"] == 500 and hog["last"]["died"], "the later kill with a death is previous but not best"
    assert "Edwin" not in recs["Skin"], "a wipe records nothing"
    out = records.write(recs, pathlib.Path(d))
    text = (out / "Records.lua").read_text(encoding="utf-8")
    assert text.startswith("MetailsRecords = {") and '["Hogger"]' in text and "curve" in text and "true" in text, text[:200]
    assert (out / "Metails_Records.toc").read_text().startswith("## Interface: 16001")
import watch
assert watch.is_kill('10/7/2026 09:13:00.000-4  ENCOUNTER_END,1,"Hogger",1,5,1,3000')
assert not watch.is_kill('10/7/2026 09:13:00.000-4  ENCOUNTER_END,1,"Hogger",1,5,0,3000')
assert not watch.is_kill('10/7/2026 09:13:00.000-4  ENCOUNTER_START,1,"Hogger",1,5,36')
print("ok")
