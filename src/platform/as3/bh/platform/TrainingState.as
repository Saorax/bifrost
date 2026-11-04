package bh.platform
{
   import flash.display.Sprite;
   import flash.display.Stage;
   import flash.utils.describeType;
   import flash.utils.getQualifiedClassName;
   import flash.utils.getTimer;
   import bh.platform.net.P2PSession;
   import bh.platform.net.RemoteInput;
   import bh.platform.net.SimRandom;
   import bh.platform.net.TrainingSync;
   import haxe.ds.IntMap;

   public final class TrainingState
   {
      public static const SAVE_KEY:uint = 112;
      public static const LOAD_KEY:uint = 113;
      public static const SLOTS:int = 5;
      private static const TRAINING_MODE:uint = 32768;
      private static const PAUSED:uint = 32;
      private static const SPAN:uint = 80;
      private static const STEP_MS:uint = 16;
      private static const SAVE_WAIT:uint = 400;
      private static const KEEP_AFTER:uint = 50000;

      public static const SAVE_ROW:int = 250;
      public static const LOAD_ROW:int = 251;

      private static var stage:Stage;
      private static var wantSave:Boolean = false;
      private static var saveFrom:uint = 0;
      private static var saveInto:int = 0;
      private static var wantLoad:Boolean = false;
      private static var loadFrom:int = 0;
      private static var slotAt:int = -1;
      private static var slots:Array = [];
      private static var lastLoaded:Object = null;
      private static var note:Sprite = null;
      private static var noteUntil:int = 0;
      public static var loads:uint = 0;
      public static var loadedAt:uint = 0;
      public static var lastHash:String = "";
      public static var lastNote:String = "";
      public static var notes:uint = 0;
      private static var hashPending:Boolean = false;

      public function TrainingState()
      {
      }

      public static function init() : void
      {
         Hooks.gameCreated.add(function(main:Object):void
         {
            stage = main.stage;
         });
         Hooks.keyDown.add(onKey);
         Hooks.simulationRollback.add(onSimulation);
         Hooks.frameStarting.add(fadeNote);
         Hooks.frameRendering.add(checkHash);
         Hooks.matchStarted.add(forget);
         Hooks.matchEnded.add(function(state:uint):void
         {
            forget();
         });
      }

      public static function get slot() : int
      {
         if(slotAt < 0)
         {
            slotAt = Math.max(0,Math.min(SLOTS - 1,int(ModSettings.value("stateSlot"))));
         }
         return slotAt;
      }

      public static function set slot(i:int) : void
      {
         slotAt = (i % SLOTS + SLOTS) % SLOTS;
         ModSettings.setValue("stateSlot",slotAt);
         show("State slot " + (slotAt + 1) + ":  " + describeSlot(slotAt));
      }

      public static function describeSlot(i:int) : String
      {
         var s:Object = i >= 0 && i < slots.length ? slots[i] : null;
         return s == null ? "empty" : "saved at " + clock(uint(s.key));
      }

      public static function clock(ms:uint) : String
      {
         var sec:int = int(ms / 1000);
         var rest:int = sec % 60;
         return int(sec / 60) + ":" + (rest < 10 ? "0" : "") + rest;
      }

      public static function save() : void
      {
         if(queueOnline(SAVE_ROW))
         {
            return;
         }
         wantSave = true;
         saveFrom = 0;
         saveInto = slot;
         wantLoad = false;
      }

      public static function load() : void
      {
         if(queueOnline(LOAD_ROW))
         {
            return;
         }
         wantLoad = true;
         loadFrom = slot;
      }

      private static function queueOnline(row:int) : Boolean
      {
         if(!OnlineTraining.active)
         {
            return false;
         }
         var core:Object = game();
         if(core != null && TrainingSync.usable && Platform.matchRunning)
         {
            TrainingSync.queueLocal(core,row,slot);
            show((row == SAVE_ROW ? "Saving state in slot " : "Loading state slot ") + (slot + 1) + "...");
         }
         else
         {
            OnlineTraining.refuses("Training saved states");
         }
         return true;
      }

      public static function get savedAt() : uint
      {
         var s:Object = slots[slot];
         return s != null ? uint(s.key) : 0;
      }

      private static function forget() : void
      {
         wantSave = wantLoad = false;
         slots = [];
         lastLoaded = null;
         loadedAt = 0;
      }

      private static function game() : Object
      {
         try
         {
            return ScreenManager.owner;
         }
         catch(e:Error)
         {
         }
         return null;
      }

      private static function inTraining(core:Object) : Boolean
      {
         return core != null && (uint(core.var_3595) & TRAINING_MODE) != 0;
      }

      private static function onKey(event:Object) : Boolean
      {
         if(event == null || event.ctrlKey || event.altKey || event.shiftKey)
         {
            return false;
         }
         var code:uint = uint(event.keyCode);
         if(code != SAVE_KEY && code != LOAD_KEY || !Platform.matchRunning || !inTraining(game()))
         {
            return false;
         }
         if(code == SAVE_KEY)
         {
            save();
         }
         else
         {
            load();
         }
         return true;
      }

      private static function onSimulation(core:Object) : Boolean
      {
         if(!wantSave && !wantLoad)
         {
            if(inTraining(core))
            {
               parkOld(core);
            }
            return false;
         }
         if(!inTraining(core))
         {
            if((uint(core.var_3595) & PAUSED) == 0)
            {
               wantSave = wantLoad = false;
            }
            return false;
         }
         try
         {
            if(wantSave)
            {
               trySave(core);
            }
            if(wantLoad && !wantSave)
            {
               wantLoad = false;
               doLoad(core,loadFrom);
            }
         }
         catch(e:Error)
         {
            wantSave = wantLoad = false;
            Platform.log("training state: " + e.message);
         }
         return false;
      }

      private static function trySave(core:Object) : void
      {
         var now:uint = uint(core.var_13849);
         var players:Object = core.var_7050;
         if(saveFrom == 0 || saveFrom > now)
         {
            saveFrom = now;
         }
         var missing:Boolean = false;
         for(var i:int = 0; i < int(players.length); i++)
         {
            if(players[i].var_7944 == null)
            {
               players[i].var_7944 = new class_361();
               players[i].var_9577 = new IntMap();
               missing = true;
            }
         }
         var key:uint = alignedAtOrBefore(saveFrom);
         if(missing || !complete(core,key))
         {
            key = alignedAtOrBefore(now);
            if(key < saveFrom || !complete(core,key))
            {
               if(now > saveFrom + SAVE_WAIT)
               {
                  Platform.log("training state: no checkpoint for every player after " + saveFrom + " ms");
                  wantSave = false;
                  saveFrom = 0;
                  show("Could not save");
               }
               return;
            }
         }
         var items:Object = core.var_14281.var_14445;
         var s:Object = {"key":key,"match":core.var_13110.method_3072(int(key)),"players":[],
            "items":items != null ? items.h[key] : null,"inMap":true,"brains":[]};
         for(i = 0; i < int(players.length); i++)
         {
            s.players.push(players[i].var_7944.method_3072(int(key)));
            var b:Object = players[i].var_8233;
            s.brains.push(b != null && b.var_13063 != null ? {"brain":b,"state":Type.getClass(b.var_13063),"values":scalars(b,players),
               "pad":scalars(b.var_12188,null),"plan":scalars(b.var_5119,null),"threat":scalars(b.var_14739,null)} : null);
         }
         s.random = randomState();
         slots[saveInto] = s;
         wantSave = false;
         show("State saved in slot " + (saveInto + 1) + "  (F2 to load)");
         Platform.log("training state saved in slot " + (saveInto + 1) + " at " + key + " ms (pressed at " + saveFrom + ", " +
            players.length + " players)");
         saveFrom = 0;
      }

      private static function alignedAtOrBefore(t:uint) : uint
      {
         if(t < 16)
         {
            return 0;
         }
         var k:uint = t - (t - 16) % SPAN;
         return k;
      }

      private static function complete(core:Object, key:uint) : Boolean
      {
         if(key < 16 || core.var_13110 == null || core.var_13110.method_3072(int(key)) == null)
         {
            return false;
         }
         var players:Object = core.var_7050;
         for(var i:int = 0; i < int(players.length); i++)
         {
            if(players[i].var_7944 == null || players[i].var_7944.method_3072(int(key)) == null)
            {
               return false;
            }
         }
         return true;
      }

      private static function inMaps(core:Object, s:Object) : Boolean
      {
         var key:int = int(s.key);
         if(core.var_13110.method_3072(key) !== s.match)
         {
            return false;
         }
         var players:Object = core.var_7050;
         for(var i:int = 0; i < int(players.length) && i < s.players.length; i++)
         {
            if(players[i].var_7944 == null || players[i].var_7944.method_3072(key) !== s.players[i])
            {
               return false;
            }
         }
         return true;
      }

      private static function usable(core:Object, s:Object) : Boolean
      {
         if(int(core.var_7050.length) != s.players.length)
         {
            return false;
         }
         return !s.inMap || inMaps(core,s);
      }

      private static function park(core:Object, s:Object) : void
      {
         if(!s.inMap)
         {
            return;
         }
         s.inMap = false;
         var key:int = int(s.key);
         if(core.var_13110.method_3072(key) === s.match)
         {
            core.var_13110.class_481(key,null);
         }
         var players:Object = core.var_7050;
         for(var i:int = 0; i < int(players.length) && i < s.players.length; i++)
         {
            if(players[i].var_7944 != null && players[i].var_7944.method_3072(key) === s.players[i])
            {
               players[i].var_7944.class_481(key,null);
            }
         }
         var items:Object = core.var_14281.var_14445;
         if(items != null && s.items != null && items.h[key] === s.items)
         {
            items.remove(key);
         }
      }

      private static function unpark(core:Object, s:Object) : void
      {
         var key:int = int(s.key);
         core.var_13110.class_481(key,s.match);
         var players:Object = core.var_7050;
         for(var i:int = 0; i < int(players.length) && i < s.players.length; i++)
         {
            if(players[i].var_7944 != null)
            {
               players[i].var_7944.class_481(key,s.players[i]);
            }
         }
         var items:Object = core.var_14281.var_14445;
         if(items != null && s.items != null)
         {
            items.h[key] = s.items;
         }
         for each(var o:Object in slots)
         {
            if(o != null && o.match === s.match)
            {
               o.inMap = true;
            }
         }
      }

      private static function parkOld(core:Object) : void
      {
         var now:uint = uint(core.var_13849);
         for each(var s:Object in slots)
         {
            if(s != null && s.inMap && now >= uint(s.key) + KEEP_AFTER)
            {
               if(!inMaps(core,s))
               {
                  continue;
               }
               park(core,s);
               Platform.log("training state at " + s.key + " ms parked (match time " + now + ")");
            }
         }
      }

      private static function takeSlot(core:Object, i:int) : Object
      {
         var s:Object = slots[i];
         if(s == null)
         {
            show("Slot " + (i + 1) + " is empty  (F1 to save)");
            return null;
         }
         if(!usable(core,s))
         {
            Platform.log("training state slot " + (i + 1) + " at " + s.key + " ms expired (match time now " + core.var_13849 + ")");
            slots[i] = null;
            show("Saved state expired  (slot " + (i + 1) + ")");
            return null;
         }
         for each(var o:Object in slots)
         {
            if(o != null)
            {
               park(core,o);
            }
         }
         unpark(core,s);
         return s;
      }

      private static function doLoad(core:Object, i:int) : void
      {
         var s:Object = slots[i];
         var was:uint = uint(core.var_13849);
         if(s != null && s === lastLoaded && was >= uint(s.key) && was < uint(s.key) + 2 * STEP_MS && usable(core,s))
         {
            show("State loaded  (slot " + (i + 1) + ")");
            return;
         }
         s = takeSlot(core,i);
         if(s == null)
         {
            return;
         }
         var key:uint = uint(s.key);
         cutInputs(core,key);
         rollBack(core,key);
         core.var_12659 = key;
         loaded(core,s,i);
         Platform.log("training state loaded: slot " + (i + 1) + ", " + key + " ms (from " + was + ")");
      }

      public static function saveOnline(core:Object, at:uint, into:int) : void
      {
         wantLoad = false;
         wantSave = true;
         saveFrom = at - 16;
         saveInto = (into % SLOTS + SLOTS) % SLOTS;
         trySave(core);
         if(wantSave)
         {
            wantSave = false;
            saveFrom = 0;
            Platform.log("training state: no online save at " + (at - 80) + " ms");
            show("Could not save");
         }
      }

      public static function loadOnline(core:Object, at:uint, target:uint, from:int) : Number
      {
         wantSave = wantLoad = false;
         var i:int = (from % SLOTS + SLOTS) % SLOTS;
         var s:Object = takeSlot(core,i);
         if(s == null)
         {
            return -1;
         }
         var key:uint = uint(s.key);
         var back:Number = Number(at) - Number(key);
         shiftInputs(core,key,at);
         rollBack(core,key);
         P2PSession.timeShifted(back);
         loaded(core,s,i);
         Platform.log("training state loaded online: slot " + (i + 1) + ", " + key + " ms (at " + at + ", the clock " +
            back + " ms back)");
         return Math.max(key,Number(target) - back);
      }

      private static function rollBack(core:Object, saved:uint) : void
      {
         var longCursor:uint = uint(core.var_1185);
         core.var_10941 = 0;
         core.var_1185 = 0;
         core.method_4383(saved,true);
         core.var_10941 = saved > 60016 ? alignedAtOrBefore(saved - 60000) : 0;
         core.var_1185 = longCursor < saved ? longCursor : 0;
         if(uint(core.var_7830) + 16 != saved)
         {
            Platform.log("training state: rollback went to " + core.var_7830 + " for " + saved);
         }
      }

      private static function loaded(core:Object, s:Object, i:int) : void
      {
         var key:uint = uint(s.key);
         lastLoaded = s;
         loadedAt = key;
         TrainingDummy.loaded(key);
         DummyRecovery.loaded();
         restoreBrains(core,s);
         wakeBrains(core,key);
         restoreRandom(s.random as Vector.<uint>);
         loads++;
         hashPending = true;
         show("State loaded  (slot " + (i + 1) + ")");
      }

      private static function wakeBrains(core:Object, t:uint) : void
      {
         var players:Object = core.var_7050;
         for(var i:int = 0; i < int(players.length); i++)
         {
            var b:Object = players[i] != null ? players[i].var_8233 : null;
            if(b == null)
            {
               continue;
            }
            if(uint(b.var_5696) > t)
            {
               b.var_5696 = t;
            }
            if(uint(b.var_1859) > t)
            {
               b.var_1859 = 0;
            }
         }
      }

      private static function randomState() : Vector.<uint>
      {
         var r:Object = class_50.var_5617;
         if(SimRandom.active || r == null)
         {
            return null;
         }
         var v:Vector.<uint> = new Vector.<uint>(17,true);
         v[0] = uint(r.var_12730);
         for(var i:int = 0; i < 16; i++)
         {
            v[i + 1] = uint(r.var_12512[i]);
         }
         return v;
      }

      private static function restoreRandom(v:Vector.<uint>) : void
      {
         var r:Object = class_50.var_5617;
         if(v == null || SimRandom.active || r == null)
         {
            return;
         }
         r.var_12730 = v[0];
         for(var i:int = 0; i < 16; i++)
         {
            r.var_12512[i] = v[i + 1];
         }
      }

      private static function scalars(o:Object, players:Object) : Object
      {
         var out:Object = {};
         if(o == null)
         {
            return out;
         }
         for each(var v:XML in describeType(o).variable)
         {
            var name:String = String(v.@name);
            var value:* = o[name];
            if(typeof value == "number" || typeof value == "boolean" || value != null && players != null && isPlayer(players,value))
            {
               out[name] = value;
            }
         }
         return out;
      }

      private static function isPlayer(players:Object, value:*) : Boolean
      {
         for(var i:int = 0; i < int(players.length); i++)
         {
            if(players[i] === value)
            {
               return true;
            }
         }
         return false;
      }

      private static function putBack(o:Object, values:Object) : void
      {
         if(o == null || values == null)
         {
            return;
         }
         for(var name:String in values)
         {
            o[name] = values[name];
         }
      }

      private static function restoreBrains(core:Object, s:Object) : void
      {
         var players:Object = core.var_7050;
         var brains:Array = s.brains as Array;
         for(var i:int = 0; brains != null && i < int(players.length) && i < brains.length; i++)
         {
            var saved:Object = brains[i];
            var b:Object = players[i] != null ? players[i].var_8233 : null;
            if(saved == null || b == null || b !== saved.brain || b.var_13063 == null)
            {
               continue;
            }
            var was:String = getQualifiedClassName(b.var_13063);
            b.var_13063.method_7875();
            b.var_13063.method_470();
            b.var_13063 = Type.createInstance(saved.state,[players[i]]);
            b.var_13063.method_1270();
            var level:uint = uint(b.var_9930);
            var kinds:* = b.var_13033;
            putBack(b,saved.values);
            b.var_9930 = level;
            b.var_13033 = kinds;
            putBack(b.var_12188,saved.pad);
            putBack(b.var_5119,saved.plan);
            putBack(b.var_14739,saved.threat);
            Platform.log("training state: brain " + i + " back to " + getQualifiedClassName(b.var_13063) + " (was " + was + ")");
         }
      }

      private static function cutInputs(core:Object, time:uint) : void
      {
         var players:Object = core.var_7050;
         for(var i:int = 0; i < int(players.length); i++)
         {
            var state:Object = players[i].var_10012;
            if(state == null || state.var_11813 == null)
            {
               continue;
            }
            var history:Array = state.var_11813;
            while(history.length > 1 && uint(history[history.length - 1].var_5941) >= time)
            {
               history.pop();
            }
            if(int(state.var_14092) >= history.length)
            {
               state.var_14092 = history.length - 1;
            }
            var held:uint = uint(state.var_13831);
            if(uint(history[history.length - 1].var_1212) != held)
            {
               history.push(new class_224(time,held));
            }
         }
      }

      private static function shiftInputs(core:Object, from:uint, to:uint) : void
      {
         var players:Object = core.var_7050;
         for(var i:int = 0; i < int(players.length); i++)
         {
            var state:Object = players[i].var_10012;
            if(state == null || state.var_11813 == null)
            {
               continue;
            }
            var history:Array = state.var_11813;
            var bits:uint = RemoteInput.bitsAt(state,to);
            var kept:Array = [];
            var later:Array = [];
            for each(var e:Object in history)
            {
               var t:uint = uint(e.var_5941);
               if(t < from && t <= to)
               {
                  kept.push(e);
               }
               else if(t > to)
               {
                  later.push(new class_224(uint(Number(t) + Number(from) - Number(to)),uint(e.var_1212)));
               }
            }
            kept.push(new class_224(from,bits));
            var at:int = kept.length - 1;
            history.length = 0;
            for each(e in kept.concat(later))
            {
               history.push(e);
            }
            state.var_14092 = at;
         }
      }

      private static function checkHash() : void
      {
         if(!hashPending)
         {
            return;
         }
         hashPending = false;
         try
         {
            var core:Object = game();
            var parts:Array = [];
            var match:Object = new class_363(core as GameCore);
            parts.push(fnv(match.var_5133));
            diffMatch(match.var_5133);
            match.method_470();
            var players:Object = core.var_7050;
            for(var i:int = 0; i < int(players.length); i++)
            {
               var one:Object = new class_362(players[i]);
               parts.push(fnv(one.var_5133));
               one.method_470();
            }
            lastHash = parts.join(" ");
            Platform.log("training state after load " + loads + " (" + loadedAt + " ms): " + lastHash);
         }
         catch(e:Error)
         {
            Platform.log("training state hash: " + e.message);
         }
      }

      private static var firstBytes:Array = null;
      private static var firstFor:Object = null;

      private static function diffMatch(bytes:Object) : void
      {
         var now:Array = [];
         for(var i:int = 0; i < int(bytes.length); i++)
         {
            now.push(uint(bytes[i]));
         }
         if(firstBytes == null || firstFor !== lastLoaded)
         {
            firstBytes = now;
            firstFor = lastLoaded;
            return;
         }
         var out:Array = [];
         for(i = 0; i < Math.max(now.length,firstBytes.length) && out.length < 24; i++)
         {
            if(now[i] !== firstBytes[i])
            {
               out.push(i + ":" + firstBytes[i] + "/" + now[i]);
            }
         }
         if(out.length > 0)
         {
            Platform.log("training state: match bytes differ from the first load: " + out.join(" "));
         }
      }

      private static function fnv(bytes:Object) : String
      {
         var h:uint = 2166136261;
         var n:int = int(bytes.length);
         for(var i:int = 0; i < n; i++)
         {
            h = uint((h ^ uint(bytes[i])) * 16777619);
         }
         return h.toString(16) + "/" + n;
      }

      public static function show(text:String) : void
      {
         lastNote = text;
         notes++;
         if(stage == null)
         {
            return;
         }
         if(note != null && note.parent != null)
         {
            note.parent.removeChild(note);
         }
         note = new Sprite();
         note.mouseEnabled = note.mouseChildren = false;
         var w:Number = stage.stageWidth;
         var t:Object = UiKit.text(note,text,w / 2,stage.stageHeight * 0.16,Math.max(18,Math.round(w / 70)),UiKit.WHITE,UiKit.BOLD,0,true);
         note.graphics.beginFill(0,0.55);
         note.graphics.drawRect(t.x - 14,t.y - 6,t.width + 28,t.height + 12);
         note.graphics.endFill();
         stage.addChild(note);
         noteUntil = getTimer() + 1500;
      }

      private static function fadeNote() : void
      {
         if(note != null && getTimer() > noteUntil)
         {
            if(note.parent != null)
            {
               note.parent.removeChild(note);
            }
            note = null;
         }
      }
   }
}
