package bh.platform
{
   import bh.platform.net.PlayerName;
   import bh.platform.net.PrivateServer;
   import flash.display.Sprite;
   import flash.events.FileListEvent;
   import flash.events.MouseEvent;
   import flash.filesystem.File;
   import flash.filesystem.FileMode;
   import flash.filesystem.FileStream;
   import flash.utils.ByteArray;
   import flash.utils.getDefinitionByName;
   import flash.utils.getTimer;

   public final class ReplayIndex
   {
      public static const FILE:String = "replay-index.json";
      private static const VERSION:int = 5;

      private static var cache:Object = null;

      private static var registered:Boolean = false;

      public static const PAGES_AHEAD:int = 2;

      private static const READ_MS:int = 6;
      private static const BUSY:String = "replay-index";
      private static var job:Object = null;
      private static var prompt:Sprite = null;
      private static var promptScreen:Object = null;
      private static var warmedRows:Object = null;
      private static var trimmedRows:Object = null;
      private static var restRows:Array = [];

      public static function init() : void
      {
         if(registered)
         {
            return;
         }
         registered = true;
         ReplayKeep.prepare();
         Hooks.replaysInput.add(function(screen:Object, input:int):Boolean
         {
            if(!screen.isActive)
            {
               return false;
            }
            if(input == 20)
            {
               rowMenu(screen);
               return true;
            }
            return ReplaysWindow.pressed(screen,input);
         });
         Hooks.replaysRowsDrawing.add(function(screen:Object):void
         {
            try
            {
               ReplaysWindow.over(screen);
            }
            catch(e:Error)
            {
               Platform.log("replays: Bifrost's page not opened: " + e.message);
            }
            try
            {
               trimRows(screen);
               showTabPrompt(screen);
               if(screen.var_3676 != null && screen.var_3676 !== warmedRows && job == null && screen.var_233 is File)
               {
                  warmedRows = screen.var_3676;
                  scanThen(screen.var_233 as File,null,true,rowFiles(screen));
               }
            }
            catch(e:Error)
            {
               PrivateServer.log("replays: prompt not shown: " + e.message);
            }
         });
      }

      public static function scanThen(folder:File, then:Function, quiet:Boolean = false, files:Array = null) : void
      {
         load();
         var dir:File = folder != null ? folder : class_51.method_3608();
         if(files == null)
         {
            files = dir.exists && dir.isDirectory ? dir.getDirectoryListing() : [];
         }
         if(job != null && job.dir.nativePath == dir.nativePath)
         {
            for each(var more:File in files)
            {
               if(more != null && !job.has[more.nativePath])
               {
                  job.has[more.nativePath] = true;
                  job.todo.push(more);
               }
            }
            if(then != null)
            {
               job.thens.push(then);
            }
            job.quiet = job.quiet && quiet;
            return;
         }
         if(job != null)
         {
            finishJob(true);
         }
         var has:Object = {};
         for each(var f:File in files)
         {
            if(f != null)
            {
               has[f.nativePath] = true;
            }
         }
         job = {"dir":dir,"todo":files.concat(),"at":0,"thens":then != null ? [then] : [],"quiet":quiet,"t0":getTimer(),
            "has":has,"names":[],"fresh":0};
         Hooks.frameStarting.add(onFrame);
      }

      public static function newestFirst(dir:File) : Array
      {
         var out:Array = [];
         if(dir == null || !dir.exists || !dir.isDirectory)
         {
            return out;
         }
         var rows:Array = [];
         for each(var f:File in dir.getDirectoryListing())
         {
            try
            {
               if(!f.isDirectory && f.extension == "replay")
               {
                  rows.push({"f":f,"t":f.modificationDate.getTime()});
               }
            }
            catch(e:Error)
            {
            }
         }
         rows.sortOn("t",Array.DESCENDING | Array.NUMERIC);
         for each(var r:Object in rows)
         {
            out.push(r.f);
         }
         prune(dir,out);
         return out;
      }

      public static function prune(dir:File, files:Array) : void
      {
         load();
         var prefix:String = subfolder(dir);
         if(prefix == null)
         {
            return;
         }
         var there:Object = {};
         for each(var f:File in files)
         {
            there[prefix + f.name] = true;
         }
         var gone:int = 0;
         for(var name:String in cache)
         {
            if(!there[name] && (prefix == "" ? name.indexOf("/") < 0 : name.indexOf(prefix) == 0))
            {
               delete cache[name];
               gone++;
            }
         }
         if(gone > 0)
         {
            PrivateServer.log("replays: " + gone + " gone from " + (prefix || "the main folder"));
            save();
         }
      }

      public static function get reading() : Boolean
      {
         return job != null;
      }

      public static function rowFiles(screen:Object) : Array
      {
         var out:Array = [];
         for each(var row:Object in screen.var_3676 as Array)
         {
            if(row != null && !row.var_13804 && row.var_8078 != null)
            {
               out.push(row.var_8078);
            }
         }
         return out;
      }

      private static function onFrame() : void
      {
         if(job == null)
         {
            Hooks.frameStarting.remove(onFrame);
            return;
         }
         var t0:int = getTimer();
         while(job.at < job.todo.length && getTimer() - t0 < READ_MS)
         {
            step(job,job.todo[job.at++] as File);
         }
         if(job.at >= job.todo.length)
         {
            finishJob(false);
         }
         else if(!job.quiet && job.fresh > 0)
         {
            Busy.start(BUSY,"READING REPLAYS " + job.at + " OF " + job.todo.length,60000);
         }
      }

      private static function step(j:Object, f:File) : void
      {
         try
         {
            if(f == null || f.isDirectory || f.extension != "replay")
            {
               return;
            }
            var time:Number = f.modificationDate.getTime();
            var key:String = keyOf(f);
            var kept:Object = cache[key];
            if(kept == null || kept.size != f.size || kept.time != time)
            {
               cache[key] = {"size":f.size,"time":time,"entry":read(f)};
               j.fresh++;
            }
            j.names.push(key);
         }
         catch(e:Error)
         {
         }
      }

      private static function finishJob(now:Boolean) : void
      {
         var j:Object = job;
         job = null;
         Hooks.frameStarting.remove(onFrame);
         Busy.done(BUSY);
         while(now && j.at < j.todo.length)
         {
            step(j,j.todo[j.at++] as File);
         }
         PrivateServer.log("replays: " + j.names.length + " checked, " + j.fresh + " read in " + (getTimer() - j.t0) + " ms" +
            (j.quiet ? " (in the background)" : ""));
         if(j.fresh > 0)
         {
            save();
         }
         if(j.thens.length == 0)
         {
            return;
         }
         var me:String = String(PlayerName.current() || "");
         var entries:Array = [];
         for each(var n:String in j.names)
         {
            var en:Object = entryOf(n,me);
            en.path = j.dir.resolvePath(String(en.file)).nativePath;
            entries.push(en);
         }
         entries.sortOn("time",Array.DESCENDING | Array.NUMERIC);
         for each(var then:Function in j.thens)
         {
            try
            {
               then(entries);
            }
            catch(e:Error)
            {
               PrivateServer.log("replays: " + e.message);
            }
         }
      }

      private static function entryOf(key:String, me:String) : Object
      {
         var kept:Object = cache[key];
         var e:Object = kept.entry;
         for each(var pl:Object in e.players)
         {
            pl.legends = names(pl.ids);
         }
         e.key = key;
         e.file = key.substr(key.lastIndexOf("/") + 1);
         e.time = kept.time;
         mine(e,me);
         return e;
      }

      public static function keyOf(f:File) : String
      {
         var sub:String = f.parent != null ? subfolder(f.parent) : null;
         return sub ? sub + f.name : f.name;
      }

      private static function subfolder(dir:File) : String
      {
         var main:File = class_51.method_3608();
         if(dir.nativePath == main.nativePath)
         {
            return "";
         }
         if(dir.parent != null && dir.parent.nativePath == main.nativePath)
         {
            return dir.name + "/";
         }
         return null;
      }

      private static function trimRows(screen:Object) : void
      {
         var rows:Array = screen.var_3676 as Array;
         if(rows == null)
         {
            return;
         }
         var want:int = (int(screen.var_7257) + 1 + PAGES_AHEAD) * int(class_622.var_14993);
         if(rows !== trimmedRows)
         {
            var files:Array = [];
            for each(var row:Object in rows)
            {
               if(row != null && !row.var_13804)
               {
                  files.push(row.var_8078);
               }
            }
            if(screen.var_233 is File)
            {
               prune(screen.var_233 as File,files);
            }
            restRows = rows.slice(want);
            trimmedRows = restRows.length > 0 ? rows.slice(0,want) : rows;
            screen.var_3676 = trimmedRows;
            return;
         }
         if(restRows.length > 0 && rows.length < want)
         {
            trimmedRows = rows.concat(restRows.splice(0,want - rows.length));
            screen.var_3676 = trimmedRows;
            screen.var_6917 = false;
         }
      }

      private static function showTabPrompt(screen:Object) : void
      {
         var panel:Object = screen.panelClip;
         if(panel == null)
         {
            return;
         }
         if(prompt == null)
         {
            prompt = new Sprite();
            prompt.addChild(promptPart(function():void
            {
               rowMenu(promptScreen);
            }));
            fillPart(screen,prompt.getChildAt(0) as Sprite,"{Alt} EXPORT / FAVORITE",UiKit.WHITE);
         }
         promptScreen = screen;
         var under:Object = panel["am_IncompatiblePrimer"];
         var into:Object = under != null ? under.parent : panel;
         if(prompt.parent !== into)
         {
            into.addChild(prompt);
         }
         if(under != null)
         {
            prompt.x = under.x;
            prompt.y = under.y + under.height + 14;
         }
      }

      private static function promptPart(action:Function) : Sprite
      {
         var part:Sprite = new Sprite();
         part.buttonMode = true;
         part.addChild(new Sprite());
         part.addEventListener(MouseEvent.CLICK,function(e:MouseEvent):void
         {
            e.stopPropagation();
            if(promptScreen != null && promptScreen.isActive)
            {
               action();
            }
         });
         return part;
      }

      private static function fillPart(screen:Object, part:Sprite, spec:String, color:uint) : void
      {
         var bar:Sprite = part.getChildAt(0) as Sprite;
         Prompts.fill(screen as ScreenBase,bar,spec,20,13,color);
         part.graphics.clear();
         part.graphics.beginFill(0,0);
         part.graphics.drawRect(-4,-4,Math.max(bar.width,60) + 8,28);
         part.graphics.endFill();
      }

      private static function rowFile(screen:Object) : File
      {
         var rows:Array = screen.var_3676 as Array;
         var at:int = int(screen.method_2779());
         var row:Object = rows != null && at >= 0 && at < rows.length ? rows[at] : null;
         return row == null || row.var_13804 || row.var_8078 == null ? null : File(row.var_8078);
      }

      public static function rowMenu(screen:Object) : String
      {
         var f:File = rowFile(screen);
         if(f == null || ReplayExport.active)
         {
            return "no replay row";
         }
         var name:String = f.name.replace(/\.replay$/,"");
         var exportIt:Object = {"label":"Export video","action":function():void
         {
            exportRow(screen);
         }};
         if(ReplayKeep.inFavorites(f))
         {
            Modal.show(name,"This replay is in Favorites (BrawlhallaReplays\\Favorites).",[exportIt]);
            return "menu: in favorites";
         }
         Modal.show(name,"Export it to a video (Documents\\Bifrost\\Videos), or add it to Favorites: a copy in " +
            "BrawlhallaReplays\\Favorites, which the KEEP RECENT limit never moves.",[exportIt,{"label":"Add to Favorites",
            "action":function():void
            {
               if(ReplayKeep.star(f,"starred"))
               {
                  Modal.show("Replays","Added to Favorites.");
               }
            }}]);
         return "menu";
      }

      public static function exportRow(screen:Object) : String
      {
         var rows:Array = screen.var_3676 as Array;
         var at:int = int(screen.method_2779());
         var row:Object = rows != null && at >= 0 && at < rows.length ? rows[at] : null;
         if(row == null || row.var_13804 || row.var_8078 == null || ReplayExport.active)
         {
            return "no replay row";
         }
         var name:String = File(row.var_8078).name.replace(/\.replay$/,"");
         ReplayExport.startWithNext(name);
         screen.method_6247(at);
         return "exporting " + name;
      }

      public static var sharing:Object = null;

      public static function play(f:File) : Boolean
      {
         var stream:FileStream = new FileStream();
         try
         {
            var bytes:ByteArray = new ByteArray();
            stream.open(f,FileMode.READ);
            stream.readBytes(bytes);
            stream.close();
            ScreenManager.var_9407.method_834(bytes,f.name);
            var bits:BitStream = new BitStream(bytes);
            Object(GameApp.mainInstance).var_13259.method_2789(f.name,bits);
            bits.method_6958();
            Platform.log("replays: playing " + keyOf(f));
            return true;
         }
         catch(e:Error)
         {
            try
            {
               stream.close();
            }
            catch(e2:Error)
            {
            }
            Platform.log("replays: could not play " + f.name + " (" + e.message + ")");
         }
         return false;
      }

      public static function entryFor(f:File) : Object
      {
         load();
         var key:String = keyOf(f);
         var time:Number = f.modificationDate.getTime();
         var kept:Object = cache[key];
         if(kept == null || kept.size != f.size || kept.time != time)
         {
            cache[key] = {"size":f.size,"time":time,"entry":read(f)};
            save();
         }
         var e:Object = entryOf(key,String(PlayerName.current() || ""));
         e.path = f.nativePath;
         return e;
      }

      public static function forget(f:File) : void
      {
         load();
         delete cache[keyOf(f)];
         save();
      }

      public static function refuseReplay(header:Object, read:Boolean) : Boolean
      {
         try
         {
            if(!read || header == null || header.var_8999 == null || header.var_8999.var_615 != null)
            {
               return false;
            }
         }
         catch(e:Error)
         {
            return false;
         }
         ReplayExport.requestStop();
         PrivateServer.log("replays: refused, its game mode isn't loaded (a mod's mode?)");
         Modal.show("Replay","This replay was played in a game mode that isn't loaded now (a mod's game mode). Switch " +
            "that mod on in Mods to watch it.");
         return true;
      }

      public static function scan(folder:File = null) : Array
      {
         load();
         var dir:File = folder != null ? folder : class_51.method_3608();
         var out:Array = [];
         var seen:Object = {};
         var changed:Boolean = false;
         var me:String = String(PlayerName.current() || "");
         if(dir.exists && dir.isDirectory)
         {
            for each(var f:File in dir.getDirectoryListing())
            {
               if(f.isDirectory || f.extension != "replay")
               {
                  continue;
               }
               var time:Number = f.modificationDate.getTime();
               var key:String = keyOf(f);
               var kept:Object = cache[key];
               if(kept == null || kept.size != f.size || kept.time != time)
               {
                  kept = {"size":f.size,"time":time,"entry":read(f)};
                  cache[key] = kept;
                  changed = true;
               }
               seen[key] = true;
               out.push(entryOf(key,me));
            }
         }
         var prefix:String = subfolder(dir);
         for(var name:String in cache)
         {
            if(prefix != null && !seen[name] && (prefix == "" ? name.indexOf("/") < 0 : name.indexOf(prefix) == 0))
            {
               delete cache[name];
               changed = true;
            }
         }
         if(changed)
         {
            save();
         }
         out.sortOn("time",Array.DESCENDING | Array.NUMERIC);
         return out;
      }

      public static function filter(entries:Array, legend:String = null, map:String = null, opponent:String = null,
                                    result:String = null) : Array
      {
         var out:Array = [];
         for each(var e:Object in entries)
         {
            if(legend && !hasLegend(e,legend.toLowerCase()))
            {
               continue;
            }
            if(map && String(e.mapName || e.map || "").toLowerCase() != map.toLowerCase() &&
               String(e.map || "").toLowerCase() != map.toLowerCase())
            {
               continue;
            }
            if(opponent && !hasOpponent(e,opponent.toLowerCase()))
            {
               continue;
            }
            if(result && String(e.result) != result.toLowerCase())
            {
               continue;
            }
            out.push(e);
         }
         return out;
      }

      public static function values(entries:Array, kind:String) : Array
      {
         var set:Object = {};
         for each(var e:Object in entries)
         {
            for each(var p:Object in e.players)
            {
               var mineOnly:Boolean = kind == "legend" && e.me >= 0;
               var isMe:Boolean = e.players.indexOf(p) == e.me;
               if(kind == "legend" && (!mineOnly || isMe))
               {
                  for each(var l:String in p.legends)
                  {
                     set[l] = true;
                  }
               }
               else if(kind == "opponent" && !isMe && p.name)
               {
                  set[p.name] = true;
               }
            }
            if(kind == "map" && (e.mapName || e.map))
            {
               set[e.mapName || e.map] = true;
            }
         }
         var out:Array = [];
         for(var k:String in set)
         {
            out.push(k);
         }
         out.sort(Array.CASEINSENSITIVE);
         return out;
      }

      public static function describe(e:Object) : String
      {
         var d:Date = new Date(e.time);
         var ps:Array = [];
         for(var i:int = 0; i < (e.players ? e.players.length : 0); i++)
         {
            var p:Object = e.players[i];
            ps.push((i == e.me ? "*" : "") + p.name + " [" + p.legends.join("/") + "]" + (p.place ? " #" + p.place : ""));
         }
         return (d.month + 1) + "-" + d.date + " " + d.hours + ":" + (d.minutes < 10 ? "0" : "") + d.minutes + " " +
            (e.ok ? "" : "(not read) ") + e.map + " | " + e.mode + " | " + ps.join(", ") + " | " + (e.result || "-") +
            " | " + Math.round(Number(e.length) / 1000) + " s";
      }

      public static function resultOf(f:File) : String
      {
         var e:Object = read(f);
         mine(e,String(PlayerName.current() || ""));
         return e.ok ? String(e.result || "") : "";
      }

      private static function read(f:File) : Object
      {
         var e:Object = {"ok":false,"why":"","map":"","mapName":"","mode":"","playlist":"","online":false,"teams":false,
            "players":[],"length":0,"kos":[]};
         try
         {
            var bytes:ByteArray = new ByteArray();
            var s:FileStream = new FileStream();
            s.open(f,FileMode.READ);
            s.readBytes(bytes);
            s.close();
            ScreenManager.var_9407.method_834(bytes,f.name);
            var h:Object = new (getDefinitionByName("class_320"))();
            e.ok = h.method_2646(f.name,new BitStream(bytes),false);
            e.map = h.var_12531 != null ? String(h.var_12531.var_5173) : "";
            e.mapName = h.var_12531 != null && h.var_12531.mDisplayName ? String(h.var_12531.mDisplayName) : "";
            e.playlist = h.var_5746 != null ? localised(String(h.var_5746)) : "";
            e.playlistId = uint(h.var_8356);
            var list:Object = e.playlistId != 0 && class_301.var_11302 != null ? class_301.var_11302[e.playlistId] : null;
            e.ranked = list != null && !!list.var_9135;
            if(e.playlist == "" && list != null && list.mDisplayNameKey)
            {
               e.playlist = localised(String(list.mDisplayNameKey));
            }
            e.online = !!h.var_223;
            e.length = uint(h.var_12978);
            var rules:Object = h.var_8999;
            e.teams = rules != null && (uint(rules.var_2458) & 1) != 0;
            if(rules != null && rules.var_615 != null)
            {
               e.mode = modeName(rules.var_615);
               e.scoring = String(rules.var_615.var_12666 || "");
            }
            if(rules != null)
            {
               e.lives = uint(rules.var_14533);
               e.duration = uint(rules.mDuration);
               e.score = uint(rules.var_6108);
               e.levelSet = uint(rules.var_5336);
            }
            var order:Array = [];
            for each(var ent:uint in h.var_4813)
            {
               order.push(ent);
               var loadout:Object = h.var_7185 != null ? h.var_7185[ent] : null;
               var legends:Array = [];
               var skins:Array = [];
               for each(var l:Object in (loadout != null ? loadout.var_12798 : null))
               {
                  if(l != null && l.var_11835)
                  {
                     legends.push(int(l.var_11835));
                     skins.push(int(l.var_14823));
                  }
               }
               e.players.push({"name":String(h.var_13290[ent] || ""),"ids":legends,"skins":skins,
                  "pid":uint(h.var_14656[ent] || 0),"team":loadout != null ? int(loadout.var_3540) : 0,
                  "place":h.var_5952 != null ? uint(h.var_5952.h[ent]) : 0,
                  "avatar":loadout != null ? uint(loadout.var_4349) : 0,
                  "colour":loadout != null ? uint(loadout.var_7774) : 0,"inputs":inputsOf(h,ent)});
            }
            var who:Object = h.var_11035;
            var when:Object = h.var_7876;
            for(var k:int = 0; who != null && when != null && k < int(who.length) && k < int(when.length); k++)
            {
               e.kos.push([order.indexOf(uint(who[k])),uint(when[k])]);
            }
            if(!e.ok)
            {
               e.why = h.var_14924 ? "version" : "unreadable";
            }
            else if(rules == null || rules.var_615 == null)
            {
               e.why = "mode";
            }
         }
         catch(err:Error)
         {
            e.error = err.message;
            e.why = "unreadable";
         }
         return e;
      }

      private static function localised(key:String) : String
      {
         try
         {
            var name:String = class_256.method_1351(key);
            if(name && name != key)
            {
               return name;
            }
         }
         catch(err:Error)
         {
         }
         return key;
      }

      private static function inputsOf(h:Object, ent:uint) : Object
      {
         var out:Object = {"jump":0,"light":0,"heavy":0,"dodge":0,"throw":0,"moves":0};
         try
         {
            var all:Object = h.var_6776 != null ? Object(h.var_6776).h : null;
            var bits:Object = all != null ? all[ent] : null;
            var prev:uint = 0;
            for(var k:int = 0; bits != null && k < int(bits.length); k++)
            {
               var b:uint = uint(bits[k]);
               var rise:uint = b & ~prev;
               prev = b;
               out.jump += (rise & 16) != 0 ? 1 : 0;
               out.heavy += (rise & 64) != 0 ? 1 : 0;
               out.light += (rise & 128) != 0 ? 1 : 0;
               out.dodge += (rise & 256) != 0 ? 1 : 0;
               out["throw"] += (rise & 512) != 0 && (rise & 128) == 0 ? 1 : 0;
               out.moves += (rise & 15) != 0 ? 1 : 0;
            }
         }
         catch(err:Error)
         {
         }
         return out;
      }

      private static function modeName(scoring:Object) : String
      {
         try
         {
            var name:String = class_256.method_1351(String(scoring.mDisplayNameKey));
            if(name)
            {
               return name;
            }
         }
         catch(err:Error)
         {
         }
         return "";
      }

      public static function myPid() : uint
      {
         try
         {
            var core:Object = ScreenManager.owner;
            return core != null ? uint(core.var_14656) : 0;
         }
         catch(err:Error)
         {
         }
         return 0;
      }

      private static function mine(e:Object, me:String) : void
      {
         e.me = -1;
         var pid:uint = myPid();
         var players:Array = e.players as Array;
         for(var i:int = 0; i < (players ? players.length : 0); i++)
         {
            if(pid != 0 && uint(players[i].pid) == pid)
            {
               e.me = i;
               break;
            }
         }
         for(i = 0; e.me < 0 && i < (players ? players.length : 0); i++)
         {
            if(me != "" && String(players[i].name).toLowerCase() == me.toLowerCase())
            {
               e.me = i;
            }
         }
         var place:uint = e.me >= 0 ? uint(players[e.me].place) : 0;
         e.result = place == 0 ? "" : (place == 1 ? "win" : "loss");
      }

      private static function names(ids:Array) : Array
      {
         var out:Array = [];
         for each(var id:int in ids)
         {
            out.push(LeaderboardWindow.legendName(id,"Legend " + id));
         }
         return out;
      }

      private static function hasLegend(e:Object, legend:String) : Boolean
      {
         for(var i:int = 0; i < e.players.length; i++)
         {
            if(e.me >= 0 && i != e.me)
            {
               continue;
            }
            for each(var l:String in e.players[i].legends)
            {
               if(l.toLowerCase() == legend)
               {
                  return true;
               }
            }
         }
         return false;
      }

      private static function hasOpponent(e:Object, part:String) : Boolean
      {
         for(var i:int = 0; i < e.players.length; i++)
         {
            if(i != e.me && String(e.players[i].name).toLowerCase().indexOf(part) >= 0)
            {
               return true;
            }
         }
         return false;
      }

      private static function load() : void
      {
         if(cache != null)
         {
            return;
         }
         cache = {};
         try
         {
            var f:File = Platform.dataFile(FILE);
            if(f.exists)
            {
               var s:FileStream = new FileStream();
               s.open(f,FileMode.READ);
               var kept:Object = JSON.parse(s.readUTFBytes(s.bytesAvailable));
               s.close();
               if(kept != null && kept.files != null && kept.version == VERSION)
               {
                  cache = kept.files;
               }
            }
         }
         catch(err:Error)
         {
            cache = {};
         }
      }

      private static function save() : void
      {
         try
         {
            var s:FileStream = new FileStream();
            s.open(Platform.dataFile(FILE),FileMode.WRITE);
            s.writeUTFBytes(JSON.stringify({"version":VERSION,"files":cache}));
            s.close();
         }
         catch(err:Error)
         {
         }
      }
   }
}
