-- Finite source-only fixtures for the frozen stored-position undo contract.
-- No private helper/upvalue access: every operation reaches registered hooks.
-- This file is authored but unexecuted until a separately approved release.
local M = {}
local candidate, witness, names = {}, {}, {}
local active
local CAP = {commands=32, lifecycle=5, source_loads=2, file_ops=160,
    api_calls=12000, messages=192, rows=16, codec_snapshots=48, callback_depth=8}
local CANONICAL, LEGACY, BACKUP = "devonsspawninfo.json", "DevonsSpawnInfo.json", "devonsspawninfo.backup.json"
local kinds = {
    enemy={field="enemySpawnPositions", add="!setEnemySpawn", move="!moveEnemySpawn", remove="!removeEnemySpawn"},
    activator={field="activatorSpawnPositions", add="!setActivatorSpawn", move="!moveActivatorSpawn", remove="!removeActivatorSpawn"},
}

local function equal(actual, expected, message)
    assert(actual == expected, (message or "value mismatch") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
end
local function same(actual, expected, message)
    assert(rawequal(actual, expected), message or "raw identity changed")
end
local function vector(value, x, y, z)
    assert(value ~= nil, "missing stored Vector")
    equal(value.x, x, "x"); equal(value.y, y, "y"); equal(value.z, z, "z")
end
local function count(values)
    local n=0; for _ in pairs(values) do n=n+1 end; return n
end
local function register(name, group, fn, mode)
    assert(not names[name], "duplicate fixture name")
    names[name]=true
    local target = mode == "witness" and witness or candidate
    target[#target+1] = {name=name, group=group, run=fn}
end
local function bump(f, key)
    f.counts[key]=(f.counts[key] or 0)+1
    assert(f.counts[key] <= CAP[key], "fixed fixture ceiling exceeded: " .. key)
end
local function api(f)
    bump(f, "api_calls")
end
local function present(text, fragment)
    return type(text)=="string" and text:find(fragment, 1, true) ~= nil
end
local function chatContains(ply, fragment, start)
    for i=start or 1,#ply.chats do if present(ply.chats[i],fragment) then return true end end
    return false
end

local function newFixture(helper, source)
    -- M.new normally bootstraps two product files. Build only its API doubles:
    -- intercept those exact source requests before any file I/O and compile
    -- empty chunks instead. The bound configuration is loaded once below.
    local retainedSource=helper.source
    local bootstrap={"roleplayAddon/lua/autorun/server/sv_config.lua", "roleplayAddon/lua/entities/activatorent/init.lua"}
    local skipped=0
    helper.source=function(path)
        skipped=skipped+1
        assert(bootstrap[skipped]==path,"unexpected helper bootstrap source request")
        return ""
    end
    local constructed,env=pcall(helper.new)
    helper.source=retainedSource
    assert(constructed,env)
    equal(skipped,2,"exactly two empty helper bootstrap chunks")
    same(helper.source,retainedSource,"retained source adapter must be restored")
    assert(next(env.hooks)==nil and next(env.receivers)==nil and next(env.timers)==nil
        and next(env.ENT)==nil and next(env.networkStrings)==nil,"helper bootstrap loaded product behavior")
    env.include=function() error("only the explicitly bound configuration may be loaded") end
    local f={env=env, counts={commands=0,lifecycle=0,source_loads=0,file_ops=0,api_calls=0},
        files={}, fileTrace={}, codec={}, codecCount=0, effects={entity=0,rng=0,timer=0,net=0}, depth=0}
    active=f
    local nativeVector, nativeIsVector = env.Vector, env.isvector
    f.nativeVector=nativeVector
    function f.clone(value)
        if nativeIsVector(value) then return nativeVector(value.x,value.y,value.z) end
        if type(value) ~= "table" then return value end
        local result={}; for key,entry in pairs(value) do result[key]=f.clone(entry) end; return result
    end
    local function serial(value)
        if nativeIsVector(value) then return "v("..tostring(value.x)..","..tostring(value.y)..","..tostring(value.z)..")" end
        if type(value)=="string" then return string.format("%q",value) end
        if type(value)~="table" then return tostring(value) end
        local keys={}; for key in pairs(value) do keys[#keys+1]=key end
        assert(#keys <= CAP.rows,"fixture row ceiling")
        table.sort(keys,function(a,b) if type(a)==type(b) then return a<b end; return type(a)<type(b) end)
        local out={"{"}; for _,key in ipairs(keys) do out[#out+1]=serial(key).."="..serial(value[key])..";" end
        out[#out+1]="}"; return table.concat(out)
    end
    function f.bytes(value)
        local bytes="fixture:"..serial(value)
        if f.codec[bytes]==nil then
            f.codecCount=f.codecCount+1
            assert(f.codecCount<=CAP.codec_snapshots,"fixture codec snapshot ceiling")
            f.codec[bytes]=f.clone(value)
        end
        return bytes
    end
    local function fileop(operation,path)
        api(f); bump(f,"file_ops")
        assert(path==CANONICAL or path==LEGACY or path==BACKUP,"unexpected DATA path")
        f.fileTrace[#f.fileTrace+1]=operation..":"..path
    end
    env.file.Exists=function(path,realm)
        fileop("exists",path); equal(realm,"DATA")
        if f.onExists then f.onExists(path) end
        return f.files[path]~=nil
    end
    env.file.Read=function(path,realm)
        fileop("read",path); equal(realm,"DATA")
        if f.onRead then local handled,result=f.onRead(path); if handled then return result end end
        return f.files[path]
    end
    env.file.Write=function(path,bytes)
        fileop("write",path); assert(type(bytes)=="string")
        if f.onWrite then local handled,result=f.onWrite(path,bytes); if handled then return result end end
        f.files[path]=bytes; return true
    end
    env.util.TableToJSON=function(value)
        api(f)
        if f.onEncode then local handled,result=f.onEncode(value); if handled then return result end end
        return f.bytes(value)
    end
    env.util.JSONToTable=function(bytes)
        api(f)
        if f.onDecode then local handled,result=f.onDecode(bytes); if handled then return result end end
        return f.clone(f.codec[bytes])
    end
    env.Vector=function(...) api(f); return nativeVector(...) end
    env.isvector=function(value) api(f); return nativeIsVector(value) end
    env.IsValid=function(value) api(f); return type(value)=="table" and value.valid==true end
    env.game.GetMap=function() api(f); return env.map end
    env.print=function() api(f) end
    env.ErrorNoHalt=function(text) api(f); env.errors[#env.errors+1]=text end
    env.include=function() error("fixture may load only the bound configuration source") end
    env.math=setmetatable({random=function() f.effects.rng=f.effects.rng+1; error("unexpected RNG") end},{__index=math})
    env.ents.Create=function() f.effects.entity=f.effects.entity+1; error("unexpected entity creation") end
    for _,method in ipairs({"Create","Start","Stop","Simple","Remove","Adjust","Pause","UnPause","Toggle"}) do
        env.timer[method]=function() f.effects.timer=f.effects.timer+1; error("unexpected timer operation") end
    end
    local send=env.net.Send
    env.net.Send=function(...) f.effects.net=f.effects.net+1; return send(...) end
    function f.load()
        bump(f,"source_loads")
        local translated=helper.source(source)
        local chunk
        if _VERSION=="Lua 5.1" then chunk=assert(loadstring(translated,"@"..source)); setfenv(chunk,env)
        else chunk=assert(load(translated,"@"..source,"t",env)) end
        chunk()
        assert(env.hooks.PlayerSay and env.hooks.PlayerSay.setUpSpawnPoints,"real PlayerSay registration absent")
        assert(env.hooks.Initialize and env.hooks.Initialize.loadTheTables,"real Initialize registration absent")
        assert(env.hooks.PlayerDisconnected and env.hooks.PlayerDisconnected.clearSpawnInspection,"real disconnect registration absent")
    end
    function f.lifecycle(event,ply)
        bump(f,"lifecycle")
        return env.fire(event,ply)
    end
    function f.player()
        local ply=env.entity("player"); ply.admin=true
        function ply:IsPlayer() api(f); return self.class=="player" end
        function ply:IsAdmin() api(f); return self.admin==true end
        function ply:Alive() api(f); return self.alive~=false end
        function ply:GetPos() api(f); return self.pos end
        function ply:ChatPrint(text)
            api(f); assert(type(text)=="string","non-text chat")
            assert(#text<=768,"unbounded private reply")
            assert(#self.chats<CAP.messages,"fixed chat ceiling")
            self.chats[#self.chats+1]=text
        end
        function ply:Remove() f.effects.entity=f.effects.entity+1; error("unexpected entity removal") end
        function ply:SteamID() return "STEAM_0:1:314159" end
        return ply
    end
    function f.say(ply,text)
        bump(f,"commands"); f.depth=f.depth+1
        assert(f.depth<=CAP.callback_depth,"fixture callback depth ceiling")
        local ok,result=pcall(env.hooks.PlayerSay.setUpSpawnPoints,ply,text)
        f.depth=f.depth-1
        if not ok then error(result,0) end
        return result
    end
    function f.undo(ply)
        local prior={entity=f.effects.entity,rng=f.effects.rng,timer=f.effects.timer,net=f.effects.net}
        local result=f.say(ply or f.owner,"!undoSpawnEdit")
        equal(result,"","undo command must remain private")
        for key,value in pairs(prior) do equal(f.effects[key],value,"undo side effect: "..key) end
        return result
    end
    function f.list(kind,ply) return f.say(ply or f.owner,"!listSpawns "..kind) end
    function f.positions(kind) return env.SpawnPositions[1][kinds[kind].field] end
    function f.edit(kind,form,ply)
        ply=ply or f.owner
        if form=="add" then return f.say(ply,kinds[kind].add) end
        if form=="move" or form=="indexed_remove" then f.list(kind,ply) end
        return f.say(ply,form=="move" and (kinds[kind].move.." 5") or
            (kinds[kind].remove..(form=="indexed_remove" and " 5" or "")))
    end
    function f.trace(expected)
        equal(table.concat(f.fileTrace,"|"),table.concat(expected,"|"),"exact file operation trace")
    end
    function f.clearTrace() f.fileTrace={} end
    function f.snapshot() return f.bytes(env.SpawnPositions) end
    function f.noSaveUndo(ply)
        local memory=f.snapshot(); f.clearTrace(); f.undo(ply)
        equal(f.snapshot(),memory,"refused undo changed stored state")
        f.trace({})
    end
    function f.assertInvariants()
        equal(f.effects.entity,0,"entity effects")
        equal(f.effects.rng,0,"RNG effects")
        equal(f.effects.timer,0,"timer effects")
        assert(f.effects.net<=1,"only explicit pre-undo marker may send")
    end
    f.load()
    env.SpawnPositions={{map=env.map,enemySpawnPositions={[2]=nativeVector(2,20,200),[5]=nativeVector(5,50,500)},
        activatorSpawnPositions={[2]=nativeVector(-2,-20,-200),[5]=nativeVector(-5,-50,-500)}}}
    f.owner,f.other=f.player(),f.player()
    f.owner.pos=nativeVector(9,90,900); f.other.pos=nativeVector(8,80,800)
    f.lifecycle("Initialize")
    f.clearTrace()
    return f
end

local function fresh(helper,source) return newFixture(helper,source) end
local function acceptedMove(f,kind)
    f.edit(kind or "enemy","move")
    vector(f.positions(kind or "enemy")[5],9,90,900)
end
local function oneInverse(f,kind,form)
    local list=f.positions(kind); local old=list[5]; local untouched=list[2]
    local opposite=f.positions(kind=="enemy" and "activator" or "enemy")
    local opposite2,opposite5=opposite[2],opposite[5]
    local x,y,z=old.x,old.y,old.z
    f.edit(kind,form)
    local changed=form=="add" and 6 or 5
    if form=="add" or form=="move" then vector(list[changed],9,90,900) else equal(list[5],nil) end
    f.undo()
    if form=="add" then equal(list[6],nil); same(list[5],old)
    else vector(list[5],x,y,z); assert(not rawequal(list[5],old),"inverse must construct detached Vector") end
    equal(list[1],nil); equal(list[3],nil); equal(list[4],nil); equal(count(list),2)
    same(list[2],untouched); same(opposite[2],opposite2); same(opposite[5],opposite5)
    f.noSaveUndo()
end

-- Group 1: both kinds and all four accepted mutation forms.
register("enemy_add_one_inverse",1,function(h,s) oneInverse(fresh(h,s),"enemy","add") end)
register("activator_add_one_inverse",1,function(h,s) oneInverse(fresh(h,s),"activator","add") end)
register("enemy_indexed_move_one_inverse",1,function(h,s) oneInverse(fresh(h,s),"enemy","move") end)
register("activator_indexed_move_one_inverse",1,function(h,s) oneInverse(fresh(h,s),"activator","move") end)
register("enemy_indexed_remove_one_inverse",1,function(h,s) oneInverse(fresh(h,s),"enemy","indexed_remove") end)
register("activator_indexed_remove_one_inverse",1,function(h,s) oneInverse(fresh(h,s),"activator","indexed_remove") end)
register("enemy_highest_remove_one_inverse",1,function(h,s) oneInverse(fresh(h,s),"enemy","highest_remove") end)
register("activator_highest_remove_one_inverse",1,function(h,s) oneInverse(fresh(h,s),"activator","highest_remove") end)

-- Group 2: structural scope and accepted no-op move.
local function missingMap(h,s,kind)
    local f=fresh(h,s); f.env.SpawnPositions={}; f.edit(kind,"add")
    local record=f.env.SpawnPositions[1]; assert(record)
    f.undo(); same(f.env.SpawnPositions[1],record)
    equal(count(record.enemySpawnPositions),0); equal(count(record.activatorSpawnPositions),0)
    f.noSaveUndo()
end
register("enemy_first_add_retains_empty_container",2,function(h,s) missingMap(h,s,"enemy") end)
register("activator_first_add_retains_empty_container",2,function(h,s) missingMap(h,s,"activator") end)
register("same_coordinate_move_replaces_previous_receipt",2,function(h,s)
    local f=fresh(h,s); acceptedMove(f); local first=f.positions("enemy")[5]
    f.edit("enemy","move"); local second=f.positions("enemy")[5]; assert(not rawequal(first,second))
    f.undo(); vector(f.positions("enemy")[5],9,90,900); f.noSaveUndo()
end)

-- Group 3: one global chronological receipt; no previous history resurrection.
register("different_admin_latest_edit_owns_receipt",3,function(h,s)
    local f=fresh(h,s); f.edit("enemy","add"); f.edit("enemy","add",f.other)
    f.noSaveUndo(f.owner); f.undo(f.other)
    vector(f.positions("enemy")[6],9,90,900); equal(f.positions("enemy")[7],nil); f.noSaveUndo(f.owner)
end)
register("different_kind_latest_edit_replaces_receipt",3,function(h,s)
    local f=fresh(h,s); f.edit("enemy","add"); f.edit("activator","highest_remove")
    f.undo(); vector(f.positions("activator")[5],-5,-50,-500)
    vector(f.positions("enemy")[6],9,90,900); f.noSaveUndo()
end)
register("accepted_a_b_a_restores_only_previous_b",3,function(h,s)
    local f=fresh(h,s); acceptedMove(f)
    f.owner.pos=f.nativeVector(8,80,800); f.edit("enemy","move")
    f.owner.pos=f.nativeVector(9,90,900); f.edit("enemy","move")
    f.undo(); vector(f.positions("enemy")[5],8,80,800); f.noSaveUndo()
end)
register("accepted_same_key_reuse_replaces_removal_receipt",3,function(h,s)
    local f=fresh(h,s); f.edit("enemy","highest_remove")
    -- Highest surviving key is 2, so the subsequent add is exact key 3.
    f.edit("enemy","add"); f.undo()
    equal(f.positions("enemy")[3],nil); equal(f.positions("enemy")[5],nil); f.noSaveUndo()
end)
register("accepted_removed_highest_contiguous_key_reuse",3,function(h,s)
    local f=fresh(h,s); f.positions("enemy")[4]=f.nativeVector(4,40,400)
    f.edit("enemy","highest_remove"); f.edit("enemy","add")
    vector(f.positions("enemy")[5],9,90,900); f.undo(); equal(f.positions("enemy")[5],nil); f.noSaveUndo()
end)
register("unsafe_accepted_latest_edit_retires_older_history",3,function(h,s)
    local f=fresh(h,s); acceptedMove(f); f.owner.pos={x=1,y=2,z=3}
    f.edit("activator","add"); same(f.positions("activator")[6],f.owner.pos)
    f.noSaveUndo(); vector(f.positions("enemy")[5],9,90,900)
    assert(chatContains(f.owner,"undo"),"unsafe accepted capture should explain unavailable undo")
end)

-- Group 4: admission, exact private command and owner identity.
register("no_receipt_private_no_write",4,function(h,s) fresh(h,s).noSaveUndo() end)
register("wrong_owner_does_not_consume",4,function(h,s)
    local f=fresh(h,s); f.edit("enemy","add"); f.noSaveUndo(f.other); f.undo(); equal(f.positions("enemy")[6],nil)
end)
local function ownerDenied(h,s,field,value)
    local f=fresh(h,s); f.edit("enemy","add"); local old=f.owner[field]; f.owner[field]=value
    f.noSaveUndo(); f.owner[field]=old; f.noSaveUndo()
end
register("invalid_owner_private_no_write",4,function(h,s) ownerDenied(h,s,"valid",false) end)
register("nonplayer_owner_private_no_write",4,function(h,s) ownerDenied(h,s,"class","npc_citizen") end)
register("nonadmin_owner_private_no_write",4,function(h,s) ownerDenied(h,s,"admin",false) end)
register("nil_sender_private_no_write",4,function(h,s)
    local f=fresh(h,s); f.edit("enemy","add"); f.clearTrace()
    equal(f.say(nil,"!undoSpawnEdit"),""); f.trace({}); vector(f.positions("enemy")[6],9,90,900)
end)
register("dead_owner_can_undo_without_position_read",4,function(h,s)
    local f=fresh(h,s); f.edit("enemy","add"); f.owner.alive=false
    f.owner.GetPos=function() error("undo must not read player position") end
    f.undo(); equal(f.positions("enemy")[6],nil)
end)
local function usage(h,s,text)
    local f=fresh(h,s); f.edit("enemy","add"); f.clearTrace()
    equal(f.say(f.owner,text),""); f.trace({}); vector(f.positions("enemy")[6],9,90,900)
    f.undo(); equal(f.positions("enemy")[6],nil)
end
register("undo_extra_argument_private_preserves_receipt",4,function(h,s) usage(h,s,"!undoSpawnEdit 5") end)
register("undo_trailing_space_private_preserves_receipt",4,function(h,s) usage(h,s,"!undoSpawnEdit ") end)
register("undo_tab_argument_private_preserves_receipt",4,function(h,s) usage(h,s,"!undoSpawnEdit\t5") end)
register("undo_unrecognized_suffix_is_not_command",4,function(h,s)
    local f=fresh(h,s); f.edit("enemy","add"); f.clearTrace()
    equal(f.say(f.owner,"!undoSpawnEditExtra"),nil); f.trace({}); f.undo(); equal(f.positions("enemy")[6],nil)
end)
register("undo_admission_exception_is_private",4,function(h,s)
    local f=fresh(h,s); f.edit("enemy","add"); f.owner.IsAdmin=function() error("synthetic admission") end
    f.noSaveUndo()
end)
register("wrong_owner_admission_exception_preserves_owner_receipt",4,function(h,s)
    local f=fresh(h,s); f.edit("enemy","add")
    f.other.IsAdmin=function() error("synthetic other-admin admission") end
    f.noSaveUndo(f.other); f.undo(); equal(f.positions("enemy")[6],nil)
end)

-- Group 5: nonmutation operations preserve receipt and existing inspection rules.
register("rejected_missing_key_preserves_receipt",5,function(h,s)
    local f=fresh(h,s); f.edit("enemy","add"); f.say(f.owner,"!moveEnemySpawn 123")
    f.undo(); equal(f.positions("enemy")[6],nil)
end)
register("rejected_nonfinite_move_preserves_receipt",5,function(h,s)
    local f=fresh(h,s); f.edit("enemy","add"); f.list("enemy")
    f.owner.pos=f.nativeVector(0/0,1,2); f.say(f.owner,"!moveEnemySpawn 5")
    f.undo(); equal(f.positions("enemy")[6],nil); vector(f.positions("enemy")[5],5,50,500)
end)
register("empty_other_kind_removal_preserves_receipt",5,function(h,s)
    local f=fresh(h,s); f.env.SpawnPositions[1].activatorSpawnPositions={}
    f.edit("enemy","add"); f.edit("activator","highest_remove")
    f.undo(); equal(f.positions("enemy")[6],nil)
end)
register("list_near_save_status_and_help_preserve_receipt",5,function(h,s)
    local f=fresh(h,s); f.edit("enemy","add")
    f.list("enemy"); f.say(f.owner,"!nearSpawns enemy"); f.say(f.owner,"!saveSpawns")
    f.say(f.owner,"!spawnSaveStatus"); f.say(f.owner,"!activatorHelp spawns")
    f.undo(); equal(f.positions("enemy")[6],nil)
end)
register("marker_snapshot_is_historical_and_preserves_receipt",5,function(h,s)
    local f=fresh(h,s); f.edit("enemy","add"); f.list("enemy")
    f.say(f.owner,"!markSpawn enemy 6"); equal(f.effects.net,1)
    local sent=f.env.messages[1]; local values={}; for i,value in ipairs(sent.values) do values[i]=value end
    f.undo(); equal(f.positions("enemy")[6],nil); equal(f.effects.net,1)
    for i,value in ipairs(values) do equal(sent.values[i],value,"sent marker changed") end
end)
register("accepted_edit_invalidates_other_admin_page_when_save_disabled",5,function(h,s)
    local f=fresh(h,s); f.files[CANONICAL]="invalid"; f.lifecycle("Initialize")
    f.list("enemy",f.other); acceptedMove(f); f.say(f.other,"!removeEnemySpawn 5")
    vector(f.positions("enemy")[5],9,90,900)
end)
register("undo_invalidates_other_admin_page_when_save_disabled",5,function(h,s)
    local f=fresh(h,s); f.files[CANONICAL]="invalid"; f.lifecycle("Initialize")
    acceptedMove(f); f.list("enemy",f.other); f.undo(); f.say(f.other,"!removeEnemySpawn 5")
    vector(f.positions("enemy")[5],5,50,500)
end)
register("undo_preserves_other_kind_inspection",5,function(h,s)
    local f=fresh(h,s); acceptedMove(f); f.list("activator",f.other); f.undo()
    f.say(f.other,"!removeActivatorSpawn 5"); equal(f.positions("activator")[5],nil)
end)

-- Group 6: observed stale identity/value conflicts permanently retire history.
local function stale(h,s,change,restore)
    local f=fresh(h,s); acceptedMove(f); local saved=change(f)
    f.noSaveUndo(); restore(f,saved); f.noSaveUndo()
end
register("root_replacement_equal_values_permanently_stale",6,function(h,s)
    stale(h,s,function(f) local old=f.env.SpawnPositions; f.env.SpawnPositions=f.clone(old); return old end,
        function(f,old) f.env.SpawnPositions=old end)
end)
register("record_replacement_equal_values_permanently_stale",6,function(h,s)
    stale(h,s,function(f) local old=f.env.SpawnPositions[1]; f.env.SpawnPositions[1]=f.clone(old); return old end,
        function(f,old) f.env.SpawnPositions[1]=old end)
end)
register("list_replacement_equal_values_permanently_stale",6,function(h,s)
    stale(h,s,function(f) local old=f.positions("enemy"); f.env.SpawnPositions[1].enemySpawnPositions=f.clone(old); return old end,
        function(f,old) f.env.SpawnPositions[1].enemySpawnPositions=old end)
end)
register("post_vector_replacement_equal_values_permanently_stale",6,function(h,s)
    stale(h,s,function(f) local old=f.positions("enemy")[5]; f.positions("enemy")[5]=f.clone(old); return old end,
        function(f,old) f.positions("enemy")[5]=old end)
end)
register("map_change_permanently_stale",6,function(h,s)
    stale(h,s,function(f) local old=f.env.map; f.env.map="gm_flatgrass"; return old end,
        function(f,old) f.env.map=old end)
end)
register("ambiguous_map_records_permanently_stale",6,function(h,s)
    stale(h,s,function(f) f.env.SpawnPositions[2]=f.clone(f.env.SpawnPositions[1]) end,
        function(f) f.env.SpawnPositions[2]=nil end)
end)
register("post_coordinates_changed_permanently_stale",6,function(h,s)
    stale(h,s,function(f) f.positions("enemy")[5].x=91 end,
        function(f) f.positions("enemy")[5].x=9 end)
end)
register("post_coordinates_nonfinite_permanently_stale",6,function(h,s)
    stale(h,s,function(f) f.positions("enemy")[5].x=math.huge end,
        function(f) f.positions("enemy")[5].x=9 end)
end)
register("malformed_list_permanently_stale",6,function(h,s)
    stale(h,s,function(f) f.positions("enemy").bad=f.nativeVector(1,2,3) end,
        function(f) f.positions("enemy").bad=nil end)
end)
register("removed_key_external_reuse_permanently_stale",6,function(h,s)
    local f=fresh(h,s); f.edit("enemy","highest_remove")
    f.positions("enemy")[5]=f.nativeVector(5,50,500); f.noSaveUndo()
    f.positions("enemy")[5]=nil; f.noSaveUndo()
end)

-- Group 7: session/lifecycle identity, independent of SteamID-like labels.
register("owner_disconnect_retires_receipt",7,function(h,s)
    local f=fresh(h,s); f.edit("enemy","add"); f.lifecycle("PlayerDisconnected",f.owner); f.noSaveUndo()
end)
register("other_admin_disconnect_preserves_receipt",7,function(h,s)
    local f=fresh(h,s); f.edit("enemy","add"); f.lifecycle("PlayerDisconnected",f.other)
    f.undo(); equal(f.positions("enemy")[6],nil)
end)
register("same_identifier_new_player_cannot_inherit_receipt",7,function(h,s)
    local f=fresh(h,s); f.edit("enemy","add")
    equal(f.owner:SteamID(),f.other:SteamID()); f.noSaveUndo(f.other)
    f.lifecycle("PlayerDisconnected",f.owner); f.noSaveUndo(f.other)
end)
register("initialize_equal_value_reload_clears_history",7,function(h,s)
    local f=fresh(h,s); f.edit("enemy","add"); local bytes=f.files[CANONICAL]
    f.lifecycle("Initialize"); equal(f.files[CANONICAL],bytes); f.noSaveUndo()
    f.lifecycle("Initialize"); f.noSaveUndo()
end)
register("script_reload_clears_history",7,function(h,s)
    local f=fresh(h,s); f.edit("enemy","add"); f.load(); f.lifecycle("Initialize"); f.noSaveUndo()
end)
register("undo_saved_state_reloads_without_history",7,function(h,s)
    local f=fresh(h,s); acceptedMove(f); f.undo(); f.lifecycle("Initialize")
    vector(f.positions("enemy")[5],5,50,500); f.noSaveUndo()
end)

-- Group 8: detached before scalars, restoration validation, legacy admission.
register("move_before_vector_mutation_cannot_change_inverse",8,function(h,s)
    local f=fresh(h,s); local before=f.positions("enemy")[5]; acceptedMove(f)
    before.x,before.y,before.z=101,102,103; f.undo(); vector(f.positions("enemy")[5],5,50,500)
end)
register("remove_before_vector_mutation_cannot_change_inverse",8,function(h,s)
    local f=fresh(h,s); local before=f.positions("enemy")[5]; f.edit("enemy","highest_remove")
    before.x,before.y,before.z=101,102,103; f.undo(); vector(f.positions("enemy")[5],5,50,500)
end)
local function badRestoration(h,s,make)
    local f=fresh(h,s); local before=f.positions("enemy")[5]; acceptedMove(f); local post=f.positions("enemy")[5]
    f.env.Vector=function(x,y,z) return make(f,before,post,x,y,z) end
    f.noSaveUndo()
end
register("restore_rejects_known_before_alias",8,function(h,s)
    badRestoration(h,s,function(_,before) return before end)
end)
register("restore_rejects_known_post_alias_with_exact_scalars",8,function(h,s)
    local f=fresh(h,s); f.owner.pos=f.nativeVector(5,50,500); f.edit("enemy","move")
    local post=f.positions("enemy")[5]; f.env.Vector=function() return post end
    f.noSaveUndo()
end)
register("restore_rejects_nonfinite_vector",8,function(h,s)
    badRestoration(h,s,function(f,_,_,x,y,z) return f.nativeVector(math.huge,y,z) end)
end)
register("restore_rejects_inexact_vector",8,function(h,s)
    badRestoration(h,s,function(f,_,_,x,y,z) return f.nativeVector(x+1,y,z) end)
end)
register("restore_rejects_nonvector",8,function(h,s)
    badRestoration(h,s,function() return {x=5,y=50,z=500} end)
end)
register("restore_constructor_exception_is_private",8,function(h,s)
    badRestoration(h,s,function() error("synthetic constructor failure") end)
end)
register("legacy_add_nonfinite_acceptance_has_no_history",8,function(h,s)
    local f=fresh(h,s); acceptedMove(f); f.owner.pos=f.nativeVector(math.huge,2,3)
    f.edit("activator","add"); same(f.positions("activator")[6],f.owner.pos); f.noSaveUndo()
end)
register("legacy_add_nil_result_retires_old_receipt",8,function(h,s)
    local f=fresh(h,s); acceptedMove(f); f.owner.GetPos=function() return nil end
    f.edit("activator","add"); equal(f.positions("activator")[6],nil); f.noSaveUndo()
end)

-- Group 9: all injections are public API callbacks, gated by observed state.
local function duringFinalization(f,action,invalid)
    local ordinary=f.env.isvector; local fired=false; local outer=f.owner.pos
    f.env.isvector=function(value)
        if not fired and rawequal(value,outer) and rawequal(f.positions("enemy")[6],outer) then
            fired=true; action()
            if invalid then return false end
        end
        return ordinary(value)
    end
    f.edit("enemy","add"); assert(fired,"finalization callback not reached")
    f.env.isvector=ordinary
end
register("unfinished_reservation_cannot_be_undone",9,function(h,s)
    local f=fresh(h,s)
    duringFinalization(f,function()
        local before=#f.fileTrace; f.undo(); vector(f.positions("enemy")[6],9,90,900)
        equal(#f.fileTrace,before,"unfinished reservation attempted save")
    end)
    f.undo(); equal(f.positions("enemy")[6],nil)
end)
register("finalization_nested_latest_edit_owns_receipt",9,function(h,s)
    local f=fresh(h,s)
    duringFinalization(f,function() f.edit("activator","add",f.other) end)
    f.noSaveUndo(f.owner); f.undo(f.other)
    equal(f.positions("activator")[6],nil); vector(f.positions("enemy")[6],9,90,900)
end)
register("unsafe_outer_finalization_cannot_clear_newer_receipt",9,function(h,s)
    local f=fresh(h,s)
    duringFinalization(f,function() f.edit("activator","add",f.other) end,true)
    f.noSaveUndo(f.owner); f.undo(f.other)
    equal(f.positions("activator")[6],nil); vector(f.positions("enemy")[6],9,90,900)
end)
register("before_snapshot_matches_value_overwritten_after_getpos_callback",9,function(h,s)
    local f=fresh(h,s); f.list("enemy"); local ordinary=f.owner.GetPos; local fired=false
    f.owner.GetPos=function(ply)
        if not fired then fired=true; f.positions("enemy")[5]=f.nativeVector(6,60,600) end
        return ordinary(ply)
    end
    f.say(f.owner,"!moveEnemySpawn 5"); assert(fired)
    vector(f.positions("enemy")[5],9,90,900); f.undo(); vector(f.positions("enemy")[5],6,60,600)
end)
register("before_snapshot_matches_value_overwritten_after_vector_callback",9,function(h,s)
    local f=fresh(h,s); f.list("enemy"); local ordinary=f.env.Vector; local fired=false
    f.env.Vector=function(x,y,z)
        if not fired then fired=true; f.positions("enemy")[5]=f.nativeVector(7,70,700) end
        return ordinary(x,y,z)
    end
    f.say(f.owner,"!moveEnemySpawn 5"); assert(fired); f.env.Vector=ordinary
    vector(f.positions("enemy")[5],9,90,900); f.undo(); vector(f.positions("enemy")[5],7,70,700)
end)
register("uncertain_before_scalar_capture_retires_older_history",9,function(h,s)
    local f=fresh(h,s); f.edit("activator","add"); f.list("enemy")
    local before=f.positions("enemy")[5]; local meta=getmetatable(before); local index=meta.__index
    local originalVector=f.env.Vector; local armed,fired=false,false
    rawset(before,"z",nil)
    meta.__index=function(value,key)
        if rawequal(value,before) and key=="z" then
            if armed and not fired then fired=true; before.x=6 end
            return 500
        end
        if type(index)=="function" then return index(value,key) end
        return index[key]
    end
    f.env.Vector=function(x,y,z) armed=true; return originalVector(x,y,z) end
    f.say(f.owner,"!moveEnemySpawn 5")
    meta.__index=index; rawset(before,"z",500); f.env.Vector=originalVector
    assert(fired,"mutation-boundary scalar callback not reached")
    vector(f.positions("enemy")[5],9,90,900); f.noSaveUndo()
    vector(f.positions("activator")[6],9,90,900)
end)
register("format_getpos_nested_edit_remains_latest",9,function(h,s)
    local f=fresh(h,s); local ordinary=f.owner.GetPos; local fired=false
    f.owner.GetPos=function(ply)
        if not fired and rawequal(f.positions("enemy")[6],ply.pos) then
            fired=true; f.edit("activator","add",f.other)
        end
        return ordinary(ply)
    end
    f.edit("enemy","add"); assert(fired,"post-acceptance GetPos callback absent")
    f.noSaveUndo(f.owner); f.undo(f.other); equal(f.positions("activator")[6],nil)
end)
register("format_tostring_nested_edit_remains_latest",9,function(h,s)
    local f=fresh(h,s); local fired=false
    f.env.tostring=function(value)
        if not fired and rawequal(value,f.owner.pos) and rawequal(f.positions("enemy")[6],value) then
            fired=true; f.edit("activator","add",f.other)
        end
        return tostring(value)
    end
    f.edit("enemy","add"); assert(fired,"accepted add formatting callback absent")
    f.noSaveUndo(f.owner); f.undo(f.other); equal(f.positions("activator")[6],nil)
end)
register("original_edit_save_nested_edit_remains_latest",9,function(h,s)
    local f=fresh(h,s); local fired=false
    f.onEncode=function()
        if not fired then fired=true; f.edit("activator","add",f.other) end
        return false
    end
    f.edit("enemy","add"); assert(fired); f.onEncode=nil
    f.noSaveUndo(f.owner); f.undo(f.other); equal(f.positions("activator")[6],nil)
end)
register("original_edit_reply_nested_edit_remains_latest",9,function(h,s)
    local f=fresh(h,s); local ordinary=f.owner.ChatPrint; local fired=false
    f.owner.ChatPrint=function(ply,text)
        ordinary(ply,text)
        if not fired then fired=true; f.edit("activator","add",f.other) end
    end
    f.edit("enemy","add"); assert(fired)
    f.noSaveUndo(f.owner); f.undo(f.other); equal(f.positions("activator")[6],nil)
end)
register("original_edit_reply_failure_keeps_accepted_receipt",9,function(h,s)
    local f=fresh(h,s); local ordinary=f.owner.ChatPrint
    f.owner.ChatPrint=function() error("synthetic original reply") end
    pcall(function() f.edit("enemy","add") end)
    f.owner.ChatPrint=ordinary; vector(f.positions("enemy")[6],9,90,900)
    f.undo(); equal(f.positions("enemy")[6],nil)
end)
register("undo_admission_reentry_cannot_consume_newer_receipt",9,function(h,s)
    local f=fresh(h,s); f.edit("enemy","add"); local ordinary=f.env.IsValid; local fired=false
    f.env.IsValid=function(value)
        if not fired and rawequal(value,f.owner) then fired=true; f.edit("activator","add",f.other) end
        return ordinary(value)
    end
    f.undo(); assert(fired); f.env.IsValid=ordinary
    vector(f.positions("enemy")[6],9,90,900); f.undo(f.other); equal(f.positions("activator")[6],nil)
end)
register("undo_map_read_reentry_cannot_consume_newer_receipt",9,function(h,s)
    local f=fresh(h,s); f.edit("enemy","add"); local ordinary=f.env.game.GetMap; local fired=false
    f.env.game.GetMap=function()
        if not fired then fired=true; f.edit("activator","add",f.other) end
        return ordinary()
    end
    f.undo(); assert(fired); f.env.game.GetMap=ordinary
    vector(f.positions("enemy")[6],9,90,900); f.undo(f.other); equal(f.positions("activator")[6],nil)
end)
register("undo_restore_constructor_reentry_cannot_commit_old_inverse",9,function(h,s)
    local f=fresh(h,s); acceptedMove(f); local ordinary=f.env.Vector; local fired=false
    f.env.Vector=function(x,y,z)
        if not fired then fired=true; f.edit("activator","add",f.other) end
        return ordinary(x,y,z)
    end
    f.undo(); assert(fired); f.env.Vector=ordinary
    vector(f.positions("enemy")[5],9,90,900); f.undo(f.other); equal(f.positions("activator")[6],nil)
end)
register("undo_preflight_a_b_a_cannot_revive_captured_receipt",9,function(h,s)
    local f=fresh(h,s); acceptedMove(f); local ordinary=f.env.IsValid; local fired=false
    f.env.IsValid=function(value)
        if not fired and rawequal(value,f.owner) then
            fired=true; f.other.pos=f.nativeVector(8,80,800); f.edit("enemy","move",f.other)
            f.other.pos=f.nativeVector(9,90,900); f.edit("enemy","move",f.other)
        end
        return ordinary(value)
    end
    f.undo(); assert(fired); f.env.IsValid=ordinary
    vector(f.positions("enemy")[5],9,90,900); f.undo(f.other)
    vector(f.positions("enemy")[5],8,80,800); f.noSaveUndo()
end)
register("stale_outer_validation_cannot_retire_newer_nested_receipt",9,function(h,s)
    local f=fresh(h,s); acceptedMove(f); local post=f.positions("enemy")[5]
    local ordinary=f.env.isvector; local fired=false
    f.env.isvector=function(value)
        if not fired and rawequal(value,post) then
            fired=true; post.x=91; f.edit("activator","add",f.other)
        end
        return ordinary(value)
    end
    f.undo(); assert(fired); f.env.isvector=ordinary
    vector(post,91,90,900); f.undo(f.other); equal(f.positions("activator")[6],nil)
end)
register("final_target_validation_demotion_prevents_inverse_and_retires",9,function(h,s)
    local f=fresh(h,s); acceptedMove(f); local post=f.positions("enemy")[5]
    local ordinary=f.env.isvector; local observations=0
    f.env.isvector=function(value)
        if rawequal(value,post) then
            observations=observations+1
            if observations==2 then f.owner.admin=false end
        end
        return ordinary(value)
    end
    f.noSaveUndo(); assert(observations>=2,"final target-validation callback not reached")
    f.env.isvector=ordinary; f.owner.admin=true; f.noSaveUndo()
end)

register("legacy_add_preselected_key_collision_retires_receipt",9,function(h,s)
    local f=fresh(h,s); acceptedMove(f,"activator")
    local ordinary=f.owner.GetPos; local fired=false
    f.owner.GetPos=function(ply)
        if not fired then fired=true; f.edit("enemy","add",f.other) end
        return ordinary(ply)
    end
    f.edit("enemy","add"); assert(fired,"nested add did not occupy selected key")
    vector(f.positions("enemy")[6],9,90,900)
    assert(chatContains(f.owner,"This edit cannot be undone."),"colliding legacy add must report no inverse")
    f.noSaveUndo(); f.noSaveUndo(f.other)
    vector(f.positions("enemy")[6],9,90,900); vector(f.positions("activator")[5],9,90,900)
end)

register("legacy_move_preselected_key_removed_retires_receipt",9,function(h,s)
    local f=fresh(h,s); f.edit("activator","add")
    local ordinary=f.owner.GetPos; local fired=false
    f.list("enemy")
    f.owner.GetPos=function(ply)
        if not fired then fired=true; f.edit("enemy","highest_remove",f.other) end
        return ordinary(ply)
    end
    f.say(f.owner,"!moveEnemySpawn 5"); assert(fired,"nested removal did not remove selected key")
    vector(f.positions("enemy")[5],9,90,900)
    assert(chatContains(f.owner,"This edit cannot be undone."),"re-adding legacy move must report no inverse")
    f.noSaveUndo(); f.noSaveUndo(f.other)
    vector(f.positions("enemy")[5],9,90,900); vector(f.positions("activator")[6],9,90,900)
end)

-- Group 10: inverse consumption precedes save and reply callbacks/errors.
register("undo_save_reentry_cannot_apply_inverse_twice",10,function(h,s)
    local f=fresh(h,s); acceptedMove(f); local fired=false
    f.onEncode=function()
        if not fired then fired=true; f.noSaveUndo(); vector(f.positions("enemy")[5],5,50,500) end
        return false
    end
    f.undo(); assert(fired); f.onEncode=nil; vector(f.positions("enemy")[5],5,50,500); f.noSaveUndo()
end)
register("undo_reply_reentry_cannot_apply_inverse_twice",10,function(h,s)
    local f=fresh(h,s); acceptedMove(f); local ordinary=f.owner.ChatPrint; local fired=false
    f.owner.ChatPrint=function(ply,text)
        ordinary(ply,text)
        if not fired then fired=true; f.noSaveUndo(); vector(f.positions("enemy")[5],5,50,500) end
    end
    f.undo(); assert(fired); f.owner.ChatPrint=ordinary; f.noSaveUndo()
end)
register("undo_save_nested_edit_keeps_its_receipt",10,function(h,s)
    local f=fresh(h,s); acceptedMove(f); local fired=false
    f.onEncode=function()
        if not fired then fired=true; f.edit("activator","add",f.other) end
        return false
    end
    f.undo(); assert(fired); f.onEncode=nil
    vector(f.positions("enemy")[5],5,50,500); f.undo(f.other); equal(f.positions("activator")[6],nil)
end)
register("undo_reply_nested_edit_keeps_its_receipt",10,function(h,s)
    local f=fresh(h,s); acceptedMove(f); local ordinary=f.owner.ChatPrint; local fired=false
    f.owner.ChatPrint=function(ply,text)
        ordinary(ply,text)
        if not fired then fired=true; f.edit("activator","add",f.other) end
    end
    f.undo(); assert(fired); f.owner.ChatPrint=ordinary
    vector(f.positions("enemy")[5],5,50,500); f.undo(f.other); equal(f.positions("activator")[6],nil)
end)
register("undo_save_exception_keeps_inverse_consumed",10,function(h,s)
    local f=fresh(h,s); acceptedMove(f); local ordinary=f.env.ErrorNoHalt
    f.onEncode=function() return true,nil end
    f.env.ErrorNoHalt=function() error("synthetic save diagnostic") end
    local start=#f.owner.chats+1; f.undo()
    f.env.ErrorNoHalt=ordinary; f.onEncode=nil
    vector(f.positions("enemy")[5],5,50,500); f.noSaveUndo()
    assert(not chatContains(f.owner,"save verified",start),"exception falsely claimed verified save")
end)
register("undo_reply_exception_keeps_inverse_consumed",10,function(h,s)
    local f=fresh(h,s); acceptedMove(f); local ordinary=f.owner.ChatPrint
    f.owner.ChatPrint=function() error("synthetic undo reply") end
    f.undo(); f.owner.ChatPrint=ordinary
    vector(f.positions("enemy")[5],5,50,500); f.noSaveUndo()
end)
register("undo_reply_nested_edit_then_exception_preserves_new_receipt",10,function(h,s)
    local f=fresh(h,s); acceptedMove(f); local ordinary=f.owner.ChatPrint; local fired=false
    f.owner.ChatPrint=function()
        if not fired then fired=true; f.edit("activator","add",f.other) end
        error("synthetic nested reply")
    end
    f.undo(); f.owner.ChatPrint=ordinary; assert(fired)
    vector(f.positions("enemy")[5],5,50,500); f.undo(f.other); equal(f.positions("activator")[6],nil)
end)
register("undo_uses_captured_map_for_invalidation_after_commit",10,function(h,s)
    local f=fresh(h,s); acceptedMove(f); f.list("enemy",f.other)
    local ordinary=f.env.game.GetMap; local inverseSeen=false
    f.env.game.GetMap=function()
        if f.positions("enemy")[5].x==5 then inverseSeen=true; error("map lookup after committed inverse") end
        return ordinary()
    end
    f.undo(); equal(inverseSeen,false,"undo looked up map after mutation")
    f.env.game.GetMap=ordinary; vector(f.positions("enemy")[5],5,50,500)
    f.say(f.other,"!removeEnemySpawn 5"); vector(f.positions("enemy")[5],5,50,500)
end)

-- Group 11: exact real file-double calls on each persistence outcome.
local function verifiedUndoTrace(f)
    f.trace({"read:"..BACKUP,"write:"..BACKUP,"read:"..BACKUP,"write:"..CANONICAL,"read:"..CANONICAL})
end
local function failedUndo(h,s,setup,trace,restore,retryTrace)
    local f=fresh(h,s); acceptedMove(f); local postBytes=f.files[CANONICAL]
    setup(f); f.clearTrace(); local start=#f.owner.chats+1; f.undo()
    vector(f.positions("enemy")[5],5,50,500); f.trace(trace)
    assert(chatContains(f.owner,"memory",start),"failed save must distinguish accepted memory state")
    assert(not chatContains(f.owner,"save verified",start),"failed undo save claimed verification")
    f.noSaveUndo(); restore(f); f.clearTrace(); f.say(f.owner,"!saveSpawns"); f.trace(retryTrace)
    local decoded=f.clone(f.codec[f.files[CANONICAL]])
    vector(decoded[1].enemySpawnPositions[5],5,50,500)
    f.noSaveUndo(); return f,postBytes
end
register("undo_verified_save_exact_backup_and_canonical_operations",11,function(h,s)
    local f=fresh(h,s); acceptedMove(f); local postBytes=f.files[CANONICAL]
    f.clearTrace(); f.undo(); verifiedUndoTrace(f)
    equal(f.files[BACKUP],postBytes); vector(f.codec[f.files[CANONICAL]][1].enemySpawnPositions[5],5,50,500)
    f.clearTrace(); f.say(f.owner,"!saveSpawns"); f.trace({"read:"..CANONICAL}); f.noSaveUndo()
end)
register("undo_failed_load_lockout_has_zero_file_operations",11,function(h,s)
    local f=fresh(h,s); f.files[CANONICAL]="corrupt saved bytes"
    f.lifecycle("Initialize"); acceptedMove(f); f.clearTrace(); f.undo(); f.trace({})
    vector(f.positions("enemy")[5],5,50,500)
    equal(f.files[CANONICAL],"corrupt saved bytes"); f.say(f.owner,"!saveSpawns"); f.trace({}); f.noSaveUndo()
end)
register("undo_serialization_failure_then_manual_retry",11,function(h,s)
    failedUndo(h,s,function(f) f.onEncode=function() return true,nil end end,{},
        function(f) f.onEncode=nil end,
        {"read:"..BACKUP,"write:"..BACKUP,"read:"..BACKUP,"write:"..CANONICAL,"read:"..CANONICAL})
end)
register("undo_serialization_exception_then_manual_retry",11,function(h,s)
    failedUndo(h,s,function(f) f.onEncode=function() error("synthetic encoder") end end,{},
        function(f) f.onEncode=nil end,
        {"read:"..BACKUP,"write:"..BACKUP,"read:"..BACKUP,"write:"..CANONICAL,"read:"..CANONICAL})
end)
register("undo_serialized_validation_failure_then_manual_retry",11,function(h,s)
    failedUndo(h,s,function(f) f.onDecode=function() return true,{malformed=true} end end,{},
        function(f) f.onDecode=nil end,
        {"read:"..BACKUP,"write:"..BACKUP,"read:"..BACKUP,"write:"..CANONICAL,"read:"..CANONICAL})
end)
register("undo_backup_write_failure_then_manual_retry",11,function(h,s)
    failedUndo(h,s,function(f) f.onWrite=function(path) if path==BACKUP then return true,false end end end,
        {"read:"..BACKUP,"write:"..BACKUP},function(f) f.onWrite=nil end,
        {"read:"..BACKUP,"write:"..BACKUP,"read:"..BACKUP,"write:"..CANONICAL,"read:"..CANONICAL})
end)
register("undo_backup_readback_failure_then_manual_retry",11,function(h,s)
    failedUndo(h,s,function(f)
        f.onRead=function(path) if path==BACKUP then return true,"mismatch" end end
    end,{"read:"..BACKUP,"write:"..BACKUP,"read:"..BACKUP},function(f) f.onRead=nil end,
        {"read:"..BACKUP,"write:"..CANONICAL,"read:"..CANONICAL})
end)
register("undo_canonical_write_failure_then_manual_retry",11,function(h,s)
    failedUndo(h,s,function(f) f.onWrite=function(path) if path==CANONICAL then return true,false end end end,
        {"read:"..BACKUP,"write:"..BACKUP,"read:"..BACKUP,"write:"..CANONICAL},function(f) f.onWrite=nil end,
        {"read:"..BACKUP,"write:"..CANONICAL,"read:"..CANONICAL})
end)
register("undo_canonical_readback_mismatch_then_manual_retry",11,function(h,s)
    failedUndo(h,s,function(f) f.onRead=function(path) if path==CANONICAL then return true,"mismatch" end end end,
        {"read:"..BACKUP,"write:"..BACKUP,"read:"..BACKUP,"write:"..CANONICAL,"read:"..CANONICAL},
        function(f) f.onRead=nil end,{"read:"..BACKUP,"write:"..CANONICAL,"read:"..CANONICAL})
end)
register("undo_canonical_readback_exception_then_manual_retry",11,function(h,s)
    failedUndo(h,s,function(f) f.onRead=function(path) if path==CANONICAL then error("synthetic readback") end end end,
        {"read:"..BACKUP,"write:"..BACKUP,"read:"..BACKUP,"write:"..CANONICAL,"read:"..CANONICAL},
        function(f) f.onRead=nil end,{"read:"..BACKUP,"write:"..CANONICAL,"read:"..CANONICAL})
end)
register("undo_prepared_backup_loss_blocks_overwrite",11,function(h,s)
    local f=fresh(h,s); acceptedMove(f); local postBytes=f.files[CANONICAL]
    f.onWrite=function(path) if path==CANONICAL then return true,false end end
    f.undo(); equal(f.files[BACKUP],postBytes); f.onWrite=nil
    f.files[BACKUP]="externally changed prepared backup"; f.clearTrace()
    f.say(f.owner,"!saveSpawns"); f.trace({"read:"..BACKUP})
    equal(f.files[BACKUP],"externally changed prepared backup"); equal(f.files[CANONICAL],postBytes)
    vector(f.positions("enemy")[5],5,50,500); f.noSaveUndo()
end)

-- Group 12: small position/storage compatibility set, plus one old-source witness.
register("compat_sparse_append_uses_exact_highest_plus_one",12,function(h,s)
    local f=fresh(h,s); f.positions("enemy")[9]=f.nativeVector(1,2,3)
    f.edit("enemy","add"); vector(f.positions("enemy")[10],9,90,900)
    equal(f.positions("enemy")[1],nil); equal(f.positions("enemy")[3],nil)
end)
register("compat_sparse_highest_remove_does_not_renumber",12,function(h,s)
    local f=fresh(h,s); f.edit("enemy","highest_remove")
    equal(f.positions("enemy")[5],nil); vector(f.positions("enemy")[2],2,20,200); equal(count(f.positions("enemy")),1)
end)
register("compat_move_requires_exact_displayed_key_token",12,function(h,s)
    local f=fresh(h,s); f.list("enemy"); f.say(f.owner,"!moveEnemySpawn 5.0")
    vector(f.positions("enemy")[5],5,50,500); f.say(f.owner,"!moveEnemySpawn 5")
    vector(f.positions("enemy")[5],9,90,900)
end)
register("compat_inspection_coordinates_must_remain_current",12,function(h,s)
    local f=fresh(h,s); f.list("enemy"); f.positions("enemy")[2].x=22
    f.say(f.owner,"!moveEnemySpawn 5"); vector(f.positions("enemy")[5],5,50,500)
end)
register("compat_ambiguous_current_map_refuses_edit",12,function(h,s)
    local f=fresh(h,s); f.env.SpawnPositions[2]=f.clone(f.env.SpawnPositions[1])
    f.clearTrace(); f.edit("enemy","add"); equal(f.positions("enemy")[6],nil); f.trace({})
end)
register("compat_nonfinite_move_does_not_mutate_destination",12,function(h,s)
    local f=fresh(h,s); f.owner.pos=f.nativeVector(math.huge,1,2); local before=f.positions("enemy")[5]
    f.edit("enemy","move"); same(f.positions("enemy")[5],before); f.trace({})
end)
register("compat_first_save_writes_canonical_only",12,function(h,s)
    local f=fresh(h,s); f.edit("enemy","add")
    f.trace({"write:"..CANONICAL,"read:"..CANONICAL}); equal(f.files[BACKUP],nil)
end)
register("compat_initialization_without_file_uses_two_exists_probes",12,function(h,s)
    local f=fresh(h,s); f.clearTrace(); f.lifecycle("Initialize")
    f.trace({"exists:"..CANONICAL,"exists:"..LEGACY})
end)
register("compat_canonical_load_precedes_legacy",12,function(h,s)
    local f=fresh(h,s); local canonical=f.clone(f.env.SpawnPositions); canonical[1].enemySpawnPositions[5]=f.nativeVector(31,32,33)
    local legacy=f.clone(f.env.SpawnPositions); legacy[1].enemySpawnPositions[5]=f.nativeVector(41,42,43)
    f.files[CANONICAL]=f.bytes(canonical); f.files[LEGACY]=f.bytes(legacy); f.clearTrace(); f.lifecycle("Initialize")
    f.trace({"exists:"..CANONICAL,"read:"..CANONICAL}); vector(f.positions("enemy")[5],31,32,33)
end)
register("compat_legacy_load_saves_lowercase_canonical",12,function(h,s)
    local f=fresh(h,s); local bytes=f.bytes(f.env.SpawnPositions); f.files[LEGACY]=bytes
    f.clearTrace(); f.lifecycle("Initialize")
    f.trace({"exists:"..CANONICAL,"exists:"..LEGACY,"read:"..LEGACY})
    f.clearTrace(); f.say(f.owner,"!saveSpawns")
    f.trace({"read:"..CANONICAL,"read:"..BACKUP,"write:"..BACKUP,"read:"..BACKUP,"write:"..CANONICAL,"read:"..CANONICAL})
    equal(f.files[LEGACY],bytes); equal(f.files[CANONICAL],bytes)
end)
register("compat_cached_status_has_no_file_or_codec_work",12,function(h,s)
    local f=fresh(h,s); local codecBefore=f.codecCount
    f.onEncode=function() error("status encoded") end; f.onDecode=function() error("status decoded") end
    f.say(f.owner,"!spawnSaveStatus"); f.trace({}); equal(f.codecCount,codecBefore)
end)
register("compat_failed_load_remains_locked_after_edit",12,function(h,s)
    local f=fresh(h,s); f.files[CANONICAL]="invalid"; f.lifecycle("Initialize"); f.clearTrace()
    f.edit("enemy","add"); f.say(f.owner,"!saveSpawns"); f.say(f.owner,"!spawnSaveStatus")
    f.trace({}); equal(f.files[CANONICAL],"invalid"); vector(f.positions("enemy")[6],9,90,900)
    assert(chatContains(f.owner,"disabled"))
end)
register("candidate_registered_add_undo_presence_witness",12,function(h,s)
    local f=fresh(h,s); f.edit("enemy","add"); vector(f.positions("enemy")[6],9,90,900)
    f.undo(); equal(f.positions("enemy")[6],nil)
end)
register("old_source_has_no_registered_position_undo",12,function(h,s)
    local f=fresh(h,s); f.edit("enemy","add"); f.clearTrace(); local result=f.say(f.owner,"!undoSpawnEdit")
    equal(result,nil,"old source unexpectedly recognized undo")
    vector(f.positions("enemy")[6],9,90,900)
    f.trace({}); equal(f.effects.net,0)
end,"witness")

function M.run(helper,source,mode,allocations)
    local selected=mode=="witness" and witness or candidate
    local result={mode=mode,registered=#selected,executed=0,passed=0,commands=0,lifecycle=0,source_loads=0,file_ops=0,api_calls=0,cases={},allocations={}}
    assert(#selected>0,"empty selected fixture registry")
    for _,case in ipairs(selected) do
        local allocation=assert(allocations[case.name],"missing finite allocation: "..case.name)
        result.allocations[case.name]=allocation
        active=nil
        result.executed=result.executed+1
        local ok,failure=pcall(case.run,helper,source)
        if active then
            if ok then local good,reason=pcall(active.assertInvariants); ok,failure=good,reason end
            if ok then
                for key,limit in pairs(allocation) do
                    if active.counts[key]>limit then ok=false; failure="case allocation exceeded: "..key; break end
                end
            end
            for key in pairs(active.counts) do result[key]=result[key]+active.counts[key] end
        end
        if not ok then error("FAIL "..case.name..": "..tostring(failure),0) end
        result.passed=result.passed+1
        result.cases[#result.cases+1]={name=case.name,group=case.group,counts=active.counts}
    end
    return result
end
M.caps=CAP
M.candidate=candidate
M.witness=witness
return M
