package bh.platform
{
   import flash.events.MouseEvent;
   import flash.display.Sprite;
   import flash.filesystem.File;
   import flash.filesystem.FileMode;
   import flash.filesystem.FileStream;
   import flash.text.TextField;
   import flash.utils.describeType;
   import haxe.ds.StringMap;

   public class MoveEditor extends BigWindow
   {
      public static const MOD_ID:String = "my-moves";
      private static const TABS:Array = ["MOVE","HITBOX","ALL COLUMNS","LEGEND","STAT POINTS","MY CHANGES"];
      private static const RECENT_MAX:int = 24;
      private static const PICKER_H:Number = 38;
      private static const BAR_H:Number = 84;
      private static const TRAINING_MODE:uint = 32768;

      private static const GROUPS:Array = [
         ["TIMING (frames of 16 ms)",[
            ["CastTime","Cast time",0,"The move's timing: wind-up and active frames of each hit."],
            ["FixedRecoverTime","Fixed recovery",1,"Frames the legend can't act after the move, whatever happened."],
            ["RecoverTime","Recovery",1,"Frames of recovery after the move."],
            ["CooldownTime","Cooldown",1,"Frames before this move can be used again."],
            ["OnHitCooldownTime","Cooldown on hit",1,"Cooldown when the move hit."],
            ["FixedStunTime","Stun",1,"Frames of hitstun the hit gives (as Training's frame data shows it)."],
            ["MinCancelTime","Earliest cancel",1,"Frames before the move can be cancelled."],
            ["GCancelTime","Gravity cancel time",1,"Frames during which a gravity cancel is possible."],
            ["AntigravTime","No-gravity time",1,"Frames the legend floats while using it."],
            ["FixedMinChargeTime","Minimum charge",1,"Frames a charged move charges at least."]],0],
         ["HIT",[
            ["BaseDamage","Damage",1,"Damage of each hit (one value, or one per hit with \",\")."],
            ["VariableImpulse","Knockback (grows)",1,"Knockback that grows with the target's damage."],
            ["FixedImpulse","Knockback (fixed)",1,"Knockback that doesn't depend on damage."],
            ["MinimumImpulse","Minimum knockback",1,"The least knockback a hit gives."],
            ["ImpulseOffsetX","Knockback direction X",5,"Direction of the knockback, sideways part."],
            ["ImpulseOffsetY","Knockback direction Y",5,"Direction of the knockback, up/down part (negative is up)."],
            ["DIMaxAngle","Most DI",5,"How far (degrees) the target can steer the knockback."],
            ["IsMultihit","Hits several times",-1,"The move can hit the same target more than once."],
            ["MinTimeBetweenHits","Time between hits",1,"For multi-hit moves: frames between two hits."]],0],
         ["HITBOX (game units)",[
            ["AoERadiusX","Width",5,"Hitbox width per hit (\"49&25\": a capsule of 49 and 25; \",\" between hits)."],
            ["AoERadiusY","Height",5,"Hitbox height per hit."],
            ["CenterOffsetX","Offset X",5,"Where the hitbox sits in front of the legend, per hit."],
            ["CenterOffsetY","Offset Y",5,"Where the hitbox sits up/down (negative is up), per hit."],
            ["TargetMethod","Shape",0,"How the hitbox is checked (PBAoE: around the legend; others follow the art)."]],1],
         ["MOVEMENT",[
            ["CastImpulseX","Push at start X",5,"Speed given when the move starts, sideways."],
            ["CastImpulseY","Push at start Y",5,"Speed given when the move starts, up/down (negative is up)."],
            ["FireImpulseX","Push on each hit X",5,"Speed given at each active part (\"50~5\": 50, then 5 per frame)."],
            ["FireImpulseY","Push on each hit Y",5,"Speed given at each active part, up/down."],
            ["SelfImpulseOnHit","Push when it hits",0,"Speed the legend gets when the move hits."],
            ["CancelGravity","No gravity",-1,"Gravity off during the move."],
            ["AllowMove","Can steer",-1,"The legend can move while using it."],
            ["SpeedLimit","Speed limit",1,"Top speed while using it."]],1],
         ["FOLLOW-UPS (move names)",[
            ["ComboName","Next move",0,"The move that follows this one (a combo's next part)."],
            ["ComboOverrideIfHit","Next move if it hit",0,"The move that follows when this one hit."],
            ["ComboOverrideIfRelease","Next move on release",0,"The move that follows when the button is let go."],
            ["ComboOverrideIfButton","Next move on a press",0,"The move that follows when the button is pressed again."],
            ["ComboOverrideIfWall","Next move at a wall",0,"The move that follows at a wall."]],1],
         ["LOOK AND SOUND",[
            ["CastAnim","Animation",0,"The legend's animation for the move."],
            ["CastSoundEvent","Sound at start",0,"The sound played when it starts."],
            ["HitSoundEvent","Sound on hit",0,"The sound played when it hits."]],1]];
      private static const LOCKED:Object = {"PowerName":true,"PowerID":true,"OrderID":true};

      private static var window:MoveEditor;
      private static var tableName:String = "powerTypes";
      private static var pristineText:String = null;
      private static var loadedText:String = null;
      private static var header:Array = null;
      private static var headerLine:String = null;
      private static var column:Object = null;
      private static var pristineRows:Object = null;
      private static var loadedRows:Object = null;
      private static var fieldNames:Array = null;
      private static var live:Object = {};
      private static var recent:Array = [];
      private static var tracking:Boolean = false;

      public var focusBefore:ScreenBase;
      private var move:String = null;
      private var hero:String = null;
      private var pointStat:int = -1;
      private var points:int = -1;
      private var note:String = "";
      private var describe:TextField;
      private var resetArmed:String = null;
      private var rowsW:Number = 1060;

      override protected function get fullPage() : Boolean
      {
         return true;
      }

      private function get ROWS_W() : Number
      {
         return area.width;
      }

      private function get COLUMN_W() : Number
      {
         return Math.floor((area.width - 10) / 2);
      }
      private var compact:Boolean = false;
      private var describeLabel:TextField;
      private var hitView:HitboxView = null;
      private var hitPart:int = 0;
      private var hitShape:int = 0;
      private var hitFrame:int = -1;
      private var hitPlay:Boolean = false;

      public function MoveEditor(core:GameCore)
      {
         super(core);
      }

      public static function init() : void
      {
         Hooks.csvParsing.add(function(text:String, name:String, offset:int):String
         {
            if(String(name).toLowerCase() == "powertypes")
            {
               tableName = name;
               pristineText = text.substr(offset);
               pristineRows = null;
            }
            return null;
         });
      }

      public static function initLoaded() : void
      {
         Hooks.csvParsing.add(function(text:String, name:String, offset:int):String
         {
            if(String(name).toLowerCase() == "powertypes")
            {
               loadedText = text.substr(offset);
               loadedRows = null;
               live = {};
            }
            return null;
         });
         Hooks.matchStarted.add(function():void
         {
            if(!tracking && inTraining())
            {
               Hooks.frameRendering.add(track);
               tracking = true;
            }
         });
         Hooks.matchEnded.add(function(state:uint):void
         {
            if(tracking)
            {
               Hooks.frameRendering.remove(track);
               tracking = false;
            }
         });
      }

      private static function inTraining() : Boolean
      {
         try
         {
            return ScreenManager.owner != null && (uint(ScreenManager.owner.var_3595) & TRAINING_MODE) != 0 &&
               !OnlineTraining.active;
         }
         catch(e:Error)
         {
         }
         return false;
      }

      private static function track() : void
      {
         try
         {
            var players:Object = ScreenManager.owner.var_7050;
            if(players == null || players.length == 0)
            {
               return;
            }
            var main:Object = players[0].var_2000.var_9222;
            if(main == null || uint(main.var_13001) == 0 || main.var_14247 == null)
            {
               return;
            }
            var name:String = String(main.var_14247.var_504);
            if(recent.length > 0 && recent[0] == name)
            {
               return;
            }
            var at:int = recent.indexOf(name);
            if(at >= 0)
            {
               recent.splice(at,1);
            }
            recent.unshift(name);
            if(recent.length > RECENT_MAX)
            {
               recent.length = RECENT_MAX;
            }
         }
         catch(e:Error)
         {
         }
      }

      public static function open() : void
      {
         if(window == null || ScreenManager.allScreens.indexOf(window) < 0)
         {
            window = new MoveEditor(ScreenManager.owner);
            ScreenManager.registerScreen(window);
            if(ScreenManager.var_14744 != null)
            {
               window.registrationIndex = ScreenManager.var_14744.registrationIndex;
            }
         }
         if(!window.isActive)
         {
            window.focusBefore = ScreenBase.focusedScreen;
            if(recent.length > 0)
            {
               window.move = recent[0];
            }
            window.note = loadedText == null ? "The move table wasn't seen at start-up: nothing to edit." : "";
            window.Display();
            try
            {
               ScreenBase.setFocus(window);
            }
            catch(e:Error)
            {
            }
         }
      }

      public static function get shown() : MoveEditor
      {
         return window != null && window.isActive ? window : null;
      }

      public static function get recentMoves() : Array
      {
         return recent.slice();
      }

      override protected function get title() : String
      {
         return "MOVE EDITOR";
      }

      override protected function get tabNames() : Array
      {
         return TABS;
      }

      override protected function get confirmLabel() : String
      {
         return "DONE";
      }

      override protected function statusText() : String
      {
         return note;
      }

      override protected function hintText() : String
      {
         var n:Object = Prompts.KEYS;
         if(tab == 5)
         {
            return n.tabs + " TABS     " + n.select + " OPEN     " + n.option + " BACK TO THE GAME'S (TWICE)     " + n.back + " BACK";
         }
         return n.tabs + " TABS     LEFT/RIGHT CHANGE     " + n.select + " TYPE     " + n.option + " GAME'S VALUE     " +
            n.back + " BACK";
      }

      override protected function back() : void
      {
         Hide();
         try
         {
            if(focusBefore != null && focusBefore !== this && focusBefore.isActive)
            {
               ScreenBase.setFocus(focusBefore);
            }
         }
         catch(e:Error)
         {
         }
         focusBefore = null;
      }

      private static function index() : void
      {
         if(header == null && (loadedText != null || pristineText != null))
         {
            var text:String = loadedText != null ? loadedText : pristineText;
            var end:int = text.indexOf("\n");
            headerLine = stripCr(end >= 0 ? text.substr(0,end) : text);
            header = ContentMods.splitCsv(headerLine);
            column = {};
            for(var c:int = 0; c < header.length; c++)
            {
               column[header[c]] = c;
            }
         }
         if(pristineRows == null && pristineText != null)
         {
            pristineRows = rowsOf(pristineText);
         }
         if(loadedRows == null && loadedText != null)
         {
            loadedRows = rowsOf(loadedText);
         }
      }

      private static function rowsOf(text:String) : Object
      {
         var rows:Object = {};
         var lines:Array = text.split("\n");
         for(var i:int = 1; i < lines.length; i++)
         {
            var line:String = stripCr(lines[i]);
            var comma:int = line.indexOf(",");
            if(comma > 0)
            {
               rows[line.substr(0,comma)] = line;
            }
         }
         return rows;
      }

      private static function stripCr(line:String) : String
      {
         return line.charAt(line.length - 1) == "\r" ? line.substr(0,line.length - 1) : line;
      }

      private static function fieldsOf(rows:Object, name:String) : Array
      {
         index();
         if(rows == null || rows[name] == null)
         {
            return null;
         }
         var f:Array = ContentMods.splitCsv(String(rows[name]));
         while(f.length < header.length)
         {
            f.push("");
         }
         return f;
      }

      private static function gameRow(name:String) : Array
      {
         var f:Array = fieldsOf(pristineRows,name);
         return f != null ? f : fieldsOf(loadedRows,name);
      }

      private static function currentRow(name:String) : Array
      {
         var f:Array = fieldsOf(loadedRows,name);
         if(f == null)
         {
            return null;
         }
         for(var col:String in live[name])
         {
            f[column[col]] = live[name][col];
         }
         return f;
      }

      public static function exists(name:String) : Boolean
      {
         index();
         return loadedRows != null && loadedRows[name] != null && PowerType.method_6087(name) != null;
      }

      public static function apply(name:String, col:String, value:String) : String
      {
         index();
         if(column == null || column[col] == null)
         {
            return "No column " + col + ".";
         }
         if(LOCKED[col])
         {
            return col + " can't be changed here.";
         }
         var target:PowerType = PowerType.method_6087(name);
         var before:Array = currentRow(name);
         if(target == null || before == null)
         {
            return "No move " + name + ".";
         }
         var game:Array = gameRow(name);
         if(value == "" && game != null && game[column[col]] != "")
         {
            return "A mod can't empty " + col + " (the game's value would come back): set it to 0 instead.";
         }
         var after:Array = before.slice();
         after[column[col]] = value;
         var a:PowerType;
         var b:PowerType;
         try
         {
            a = parse(before,target);
            b = parse(after,target);
         }
         catch(e:Error)
         {
            return "The game refused it: " + e.message;
         }
         if(a == null || b == null)
         {
            return "The game's parser gave nothing back.";
         }
         var changed:int = copyChanges(a,b,target);
         if(live[name] == null)
         {
            live[name] = {};
         }
         live[name][col] = value;
         Platform.log("move editor: " + name + " " + col + " = " + value + " (" + changed + " fields)");
         return "";
      }

      private static function parse(fields:Array, target:PowerType) : PowerType
      {
         var name:String = target.var_504;
         var list:Vector.<PowerType> = PowerType.var_10861;
         var listLength:int = list.length;
         var combos:int = PowerType.var_12899 != null ? int(PowerType.var_12899.length) : 0;
         var id:* = target.var_8104;
         var byId:* = PowerType.var_14377[id];
         var made:PowerType = null;
         var map:Object = PowerType.var_8260;
         var table:class_99 = new class_99(headerLine + "\n" + ContentMods.joinCsv(fields) + "\n",0);
         try
         {
            if(name in StringMap.reserved)
            {
               map.setReserved(name,null);
            }
            else
            {
               map.h[name] = null;
            }
            PowerType.var_14377[id] = null;
            var rows:Object = table.method_940();
            if(rows.hasNext())
            {
               PowerType.method_52(rows.next(),false);
               if(list.length > listLength)
               {
                  made = list[list.length - 1];
               }
            }
         }
         finally
         {
            list.length = listLength;
            if(PowerType.var_12899 != null)
            {
               PowerType.var_12899.length = combos;
            }
            PowerType.var_14377[id] = byId;
            if(name in StringMap.reserved)
            {
               map.setReserved(name,target);
            }
            else
            {
               map.h[name] = target;
            }
            table.Clear();
         }
         return made;
      }

      private static function copyChanges(a:PowerType, b:PowerType, target:PowerType) : int
      {
         if(fieldNames == null)
         {
            fieldNames = [];
            for each(var v:XML in describeType(PowerType).factory.variable)
            {
               fieldNames.push(String(v.@name));
            }
         }
         var n:int = 0;
         for each(var f:String in fieldNames)
         {
            if(!same(a[f],b[f],0))
            {
               target[f] = b[f];
               n++;
            }
         }
         return n;
      }

      private static function same(x:*, y:*, depth:int) : Boolean
      {
         if(x === y)
         {
            return true;
         }
         if(x == null || y == null)
         {
            return false;
         }
         if(x is Number && y is Number)
         {
            return isNaN(x) && isNaN(y);
         }
         if(x is String || y is String || x is Boolean || y is Boolean || depth > 3)
         {
            return false;
         }
         if(x is PowerType || y is PowerType)
         {
            return false;
         }
         var xs:String = describeType(x).@name;
         if(xs != describeType(y).@name)
         {
            return false;
         }
         if(x is Array || xs.indexOf("__AS3__.vec::Vector") == 0)
         {
            if(x.length != y.length)
            {
               return false;
            }
            for(var i:int = 0; i < x.length; i++)
            {
               if(!same(x[i],y[i],depth + 1))
               {
                  return false;
               }
            }
            return true;
         }
         var d:XML = describeType(x);
         for each(var v:XML in d.variable)
         {
            if(!same(x[String(v.@name)],y[String(v.@name)],depth + 1))
            {
               return false;
            }
         }
         for(var k:String in x)
         {
            if(!same(x[k],y[k],depth + 1))
            {
               return false;
            }
         }
         return true;
      }

      public static function setId() : String
      {
         var v:* = ModSettings.value("moveSet");
         return v != null && v.id is String && validId(v.id) ? v.id : MOD_ID;
      }

      public static function setName() : String
      {
         var v:* = ModSettings.value("moveSet");
         return v != null && v.id is String && validId(v.id) && v.name is String ? v.name : "My move changes";
      }

      private static function validId(id:String) : Boolean
      {
         return /^moves-[a-z0-9-]{1,40}$/.test(id);
      }

      public static function idFor(name:String) : String
      {
         var slug:String = String(name).toLowerCase().replace(/[^a-z0-9]+/g,"-").replace(/^-+/,"").substr(0,40);
         slug = slug.replace(/-+$/,"");
         return slug.length > 0 ? "moves-" + slug : null;
      }

      public static function nameSet(name:String) : String
      {
         name = String(name).replace(/^\s+|\s+$/g,"");
         var id:String = idFor(name);
         if(id == null)
         {
            return "The name needs a letter or a digit.";
         }
         var old:String = setId();
         var oldDir:File = modFolder();
         if(id != old && folderOf(id).exists)
         {
            return "mods\\" + id + " already exists: pick another name.";
         }
         var tables:Object = savedTables();
         ModSettings.setValue("moveSet",{"id":id,"name":name});
         var line:String = save(tables);
         if(id != old && oldDir.exists)
         {
            try
            {
               oldDir.deleteDirectory(true);
            }
            catch(e:Error)
            {
               ErrorLog.write("move editor: " + oldDir.nativePath + " not removed: " + e);
            }
         }
         Platform.log("move editor: set named \"" + name + "\" (" + old + " -> " + id + ")");
         if(!folderOf(id).exists)
         {
            return line;
         }
         return "Saved as \"" + name + "\" in mods\\" + id + ". After a restart, share it from Mods > INSTALLED.";
      }

      private static function folderOf(id:String) : File
      {
         return new File(File.applicationDirectory.resolvePath(ContentMods.FOLDER).nativePath).resolvePath(id);
      }

      private static function modFolder() : File
      {
         return folderOf(setId());
      }

      private static function savedTables() : Object
      {
         try
         {
            var f:File = modFolder().resolvePath("mod.json");
            if(f.exists)
            {
               var st:FileStream = new FileStream();
               st.open(f,FileMode.READ);
               var mod:Object = JSON.parse(st.readUTFBytes(st.bytesAvailable));
               st.close();
               return mod.tables;
            }
         }
         catch(e:Error)
         {
            ErrorLog.write("move editor: mod.json unreadable: " + e);
         }
         return null;
      }

      private static function saved(tables:Object = null) : Object
      {
         var out:Object = {};
         if(tables == null)
         {
            tables = savedTables();
         }
         for each(var row:Object in tables != null ? tables[tableName] : null)
         {
            if(row != null && row.copy != null && row.set != null)
            {
               out[row.copy] = row.set;
            }
         }
         return out;
      }

      private static function changes(tables:Object = null) : Object
      {
         var all:Object = saved(tables);
         for(var name:String in live)
         {
            if(all[name] == null)
            {
               all[name] = {};
            }
            for(var col:String in live[name])
            {
               all[name][col] = live[name][col];
            }
         }
         for(name in all)
         {
            var game:Array = gameRow(name);
            var left:int = 0;
            for(col in all[name])
            {
               if(game != null && column[col] != null && game[column[col]] == all[name][col])
               {
                  delete all[name][col];
               }
               else
               {
                  left++;
               }
            }
            if(left == 0)
            {
               delete all[name];
            }
         }
         return all;
      }

      public static function save(fromTables:Object = null) : String
      {
         try
         {
            var before:Object = fromTables != null ? fromTables : savedTables();
            var all:Object = changes(before);
            var rows:Array = [];
            var names:Array = [];
            for(var name:String in all)
            {
               names.push(name);
            }
            names.sort();
            for each(name in names)
            {
               rows.push({"copy":name,"set":all[name]});
            }
            var stanceRows:Array = LegendStats.rows(LegendStats.changes(LegendStats.savedIn(before)));
            var pointRows:Array = LegendStats.pointRows(LegendStats.pointChanges(LegendStats.savedPointsIn(before)));
            var heroes:Array = [];
            for each(var sr:Object in stanceRows)
            {
               if(heroes.indexOf(sr.stance) < 0)
               {
                  heroes.push(sr.stance);
               }
            }
            var dir:File = modFolder();
            if(rows.length == 0 && stanceRows.length == 0 && pointRows.length == 0)
            {
               if(dir.exists)
               {
                  dir.deleteDirectory(true);
               }
               return "Nothing differs from the game's moves and stats: the mod is removed.";
            }
            if(!dir.exists)
            {
               dir.createDirectory();
            }
            var tables:Object = {};
            if(rows.length > 0)
            {
               tables[tableName] = rows;
            }
            if(stanceRows.length > 0)
            {
               tables[LegendStats.TABLE] = stanceRows;
            }
            if(pointRows.length > 0)
            {
               tables[LegendStats.POINTS_TABLE] = pointRows;
            }
            var what:Array = [];
            if(names.length > 0)
            {
               what.push("moves " + names.join(", "));
            }
            if(heroes.length > 0)
            {
               what.push("stats of " + heroes.join(", "));
            }
            if(pointRows.length > 0)
            {
               what.push("stat points " + pointRows.map(function(r:Object, i:int, a:Array):String { return r.copy; }).join(", "));
            }
            var mod:Object = {"id":setId(),"name":setName(),"version":"1.0","author":"Move editor",
               "description":"Changed in the game's move editor (Training > Settings > PRACTICE > MOVE EDITOR): " +
               what.join("; ") + ".","tables":tables};
            var st:FileStream = new FileStream();
            st.open(dir.resolvePath("mod.json"),FileMode.WRITE);
            st.writeUTFBytes(JSON.stringify(mod,null,2));
            st.close();
            Platform.log("move editor: saved " + rows.length + " moves, " + stanceRows.length + " stances and " + pointRows.length +
               " stat points to mods/" + setId());
            var parts:Array = [];
            if(rows.length > 0)
            {
               parts.push(rows.length + (rows.length == 1 ? " move" : " moves"));
            }
            if(stanceRows.length > 0)
            {
               parts.push(stanceRows.length + (stanceRows.length == 1 ? " stance" : " stances"));
            }
            if(pointRows.length > 0)
            {
               parts.push(pointRows.length + (pointRows.length == 1 ? " stat row" : " stat rows"));
            }
            return "Saved " + parts.join(" and ") + " in mods\\" + setId() + ". Other players need the same mod for online matches.";
         }
         catch(e:Error)
         {
            ErrorLog.write("move editor: save failed: " + e);
            return "Saving failed: " + e.message;
         }
         return "";
      }

      override protected function buildTab(i:int) : void
      {
         index();
         if(move == null || !exists(move))
         {
            move = recent.length > 0 && exists(recent[0]) ? recent[0] : (exists("BaseNeutral") ? "BaseNeutral" : null);
         }
         switch(i)
         {
            case 0:
               buildMove(false);
               break;
            case 1:
               buildHitbox();
               break;
            case 2:
               buildMove(true);
               break;
            case 3:
               buildLegend();
               break;
            case 4:
               buildPoints();
               break;
            case 5:
               buildChanges();
         }
      }

      private function rowsPanel(x:Number = NaN, width:Number = NaN) : Sprite
      {
         if(isNaN(x))
         {
            x = area.x;
            width = ROWS_W;
         }
         rowsW = width;
         compact = false;
         describeLabel = null;
         var p:Sprite = panel(x,area.y,width,area.height);
         describe = UiKit.text(p,"",14,area.height - 30,13,UiKit.GREY,UiKit.MEDIUM,width - 28);
         return scroller(p,0,8,width,area.height - 44);
      }

      private function buildMove(everything:Boolean) : void
      {
         rowsW = ROWS_W;
         compact = false;
         var top:Sprite = panel(area.x,area.y,ROWS_W,PICKER_H);
         var pick:Sprite = new Sprite();
         pick.y = 4;
         top.addChild(pick);
         movePicker(pick);
         var listHeight:Number = area.height - PICKER_H - BAR_H - 12;
         var cols:Array = [];
         for(var k:int = 0; k < 2; k++)
         {
            var col:Sprite = panel(area.x + k * (COLUMN_W + 10),area.y + PICKER_H + 6,COLUMN_W,listHeight);
            cols.push(scroller(col,0,4,COLUMN_W,listHeight - 8));
         }
         var bar:Sprite = panel(area.x,area.y + area.height - BAR_H,ROWS_W,BAR_H);
         describeLabel = UiKit.text(bar,"",14,4,14,UiKit.WHITE,UiKit.XBOLD);
         describe = UiKit.text(bar,"",14,22,12,UiKit.LIGHT,UiKit.MEDIUM,ROWS_W - 28);
         rowsW = COLUMN_W;
         compact = true;
         if(move == null)
         {
            return;
         }
         var game:Array = gameRow(move);
         var cur:Array = currentRow(move);
         if(everything)
         {
            var shown:Array = header.filter(function(h:String, ... rest):Boolean
            {
               return !LOCKED[h];
            });
            var half:int = Math.ceil(shown.length / 2);
            for(var c:int = 0; c < shown.length; c++)
            {
               if(c == 0 || c == half)
               {
                  heading(cols[c < half ? 0 : 1],c == 0 ? "EVERY COLUMN OF " + move.toUpperCase() : "EVERY COLUMN (CONTINUED)");
               }
               valueRow(cols[c < half ? 0 : 1],shown[c],shown[c],0,"",game,cur);
            }
            return;
         }
         for each(var g:Array in GROUPS)
         {
            heading(cols[g[2]],g[0]);
            for each(var r:Array in g[1])
            {
               if(column[r[0]] != null)
               {
                  valueRow(cols[g[2]],r[0],r[1],r[2],r[3],game,cur);
               }
            }
         }
         buttonRow(cols[1],"SAVE AS MOD","Writes every changed move into mods\\" + setId() + " (loaded at every start).",function():void
         {
            note = save();
            build();
         });
      }

      private function movePicker(list:Sprite) : void
      {
         var choices:Array = pickable();
         var about:String = "Left/right: the moves you used last in Training (newest first) and this move's follow-ups. " +
            Prompts.KEYS.select + ": type a move's name.";
         row(list,"MOVE",move != null ? move : "(use a move in Training first)",about,function(dir:int):void
         {
            if(choices.length == 0)
            {
               return;
            }
            var at:int = choices.indexOf(move);
            move = choices[((at < 0 ? 0 : at + dir) % choices.length + choices.length) % choices.length];
            resetArmed = null;
         },function():void
         {
            typeText("MOVE NAME",move != null ? move : "",60,function(text:String):void
            {
               if(exists(text))
               {
                  move = text;
                  note = "";
               }
               else
               {
                  note = "No move named \"" + text + "\" (names are as in the Power Viewer, e.g. BaseNeutral).";
               }
               build();
            });
         },null,true);
      }

      private function pickable() : Array
      {
         var out:Array = [];
         for each(var r:String in recent)
         {
            if(exists(r) && out.indexOf(r) < 0)
            {
               out.push(r);
            }
         }
         var cur:Array = move != null ? currentRow(move) : null;
         if(cur != null)
         {
            for each(var col:String in ["ComboName","ComboOverrideIfHit","ComboOverrideIfRelease","ComboOverrideIfButton",
               "ComboOverrideIfDir","ComboOverrideIfWall","ComboOverrideIfInterrupt","OriginPower"])
            {
               var next:String = column[col] != null ? String(cur[column[col]]) : "";
               if(next != "" && exists(next) && out.indexOf(next) < 0)
               {
                  out.push(next);
               }
            }
         }
         if(move != null && out.indexOf(move) < 0)
         {
            out.unshift(move);
         }
         return out;
      }

      private function valueRow(list:Sprite, col:String, label:String, step:Number, about:String, game:Array, cur:Array) : void
      {
         var value:String = String(cur[column[col]]);
         var original:String = game != null ? String(game[column[col]]) : value;
         var differs:Boolean = value != original;
         var shown:String = (value == "" ? "-" : value) + (differs && !compact ? "   (game: " + (original == "" ? "-" : original) + ")" : "");
         var text:String = (label != col ? col + ". " : "") + FieldHelp.about(col,about);
         var changedNote:String = !differs ? "" : (compact ? "Changed (the game's: " + (original == "" ? "-" : original) + "). " :
            "Changed. ");
         if(compact && value.length > 18)
         {
            changedNote += "Now: " + value + ". ";
         }
         var change:Function = null;
         if(step == -1 || step == 0 && /^(TRUE|FALSE)$/i.test(value))
         {
            change = function(dir:int):void
            {
               set(col,/^TRUE$/i.test(value) ? "FALSE" : "TRUE");
            };
         }
         else if(/^-?\d+(\.\d+)?$/.test(value) || value == "" && step > 0)
         {
            var by:Number = step > 0 ? step : 1;
            change = function(dir:int):void
            {
               var n:Number = (value == "" ? 0 : Number(value)) + dir * by;
               set(col,String(Math.round(n * 1000) / 1000));
            };
         }
         row(list,label,shown,changedNote + text + "  " + Prompts.KEYS.select + ": type it.",change,
            function():void
            {
               typeText(label.toUpperCase(),value,120,function(typed:String):void
               {
                  set(col,typed);
                  build();
               },true);
            },function():void
            {
               set(col,original);
               build();
            },false,differs);
      }

      private function set(col:String, value:String) : void
      {
         var why:String = apply(move,col,value);
         note = why != "" ? why : move + " " + col + " is now " + (value == "" ? "empty" : value) + ": try it, then SAVE AS MOD.";
      }

      private static const HIT_COLUMNS:Array = [
         ["CenterOffsetX","OFFSET X","x","How far in front of the legend the shape's centre is (game units)."],
         ["CenterOffsetY","OFFSET Y","y","How far below the legend's origin the shape's centre is (negative is up)."],
         ["AoERadiusX","HALF WIDTH","rx","Half the shape's width (the game's AoERadiusX)."],
         ["AoERadiusY","HALF HEIGHT","ry","Half the shape's height (the game's AoERadiusY)."]];

      public static function withShapeValue(value:String, entries:int, entry:int, shape:int, n:Number) : String
      {
         var parts:Array = value == "" ? ["0"] : value.split(",");
         if(parts.length == 1 && entries > 1)
         {
            for(var i:int = 1; i < entries; i++)
            {
               parts.push(parts[0]);
            }
         }
         if(entry < 0 || entry >= parts.length)
         {
            return null;
         }
         var shapes:Array = String(parts[entry]).split("&");
         if(shape < 0 || shape >= shapes.length || !/^\s*-?\d+(\.\d+)?\s*$/.test(shapes[shape] == "" ? "0" : shapes[shape]))
         {
            return null;
         }
         shapes[shape] = String(Math.round(n * 1000) / 1000);
         parts[entry] = shapes.join("&");
         return parts.join(",");
      }

      public static function shapeValue(value:String, entry:int, shape:int) : Number
      {
         var parts:Array = value == "" ? ["0"] : value.split(",");
         var part:String = String(parts[parts.length == 1 ? 0 : Math.min(entry,parts.length - 1)]);
         var shapes:Array = part.split("&");
         var s:String = shape < shapes.length ? String(shapes[shape]) : "";
         return /^\s*-?\d+(\.\d+)?\s*$/.test(s == "" ? "0" : s) ? Number(s == "" ? "0" : s) : NaN;
      }

      private function buildHitbox() : void
      {
         var viewW:Number = Math.round(area.width * 0.42);
         var viewPanel:Sprite = panel(area.x,area.y,viewW,area.height);
         var list:Sprite = rowsPanel(area.x + viewW + 10,ROWS_W - viewW - 10);
         movePicker(list);
         if(move == null)
         {
            return;
         }
         var p:PowerType = PowerType.method_6087(move);
         var all:Array = HitboxView.parts(p);
         var cur:Array = currentRow(move);
         var game:Array = gameRow(move);
         var castParts:Array = String(cur[column["CastTime"]]).split(",");
         var entries:int = castParts.length;
         var view:HitboxView = new HitboxView(viewW,area.height);
         view.legend = legendSpec(p);
         hitView = view;
         viewPanel.addChild(view);
         UiKit.text(viewPanel,"FACING RIGHT    OLIVE: HURTBOX    DRAG THE DOT TO MOVE, THE SQUARE TO RESIZE",12,area.height - 24,11,
            UiKit.GREY,UiKit.MEDIUM,viewW - 24);
         var method:String = column["TargetMethod"] != null ? String(cur[column["TargetMethod"]]) : "";
         if(all.length == 0)
         {
            view.draw([],-1,-1);
            heading(list,"NO HITBOX SHAPES" + (method != "" ? " (TARGETMETHOD " + method.toUpperCase() + ")" : ""));
            return;
         }
         var tl:Object = HitboxView.timeline(p);
         hitFrame = Math.max(-1,Math.min(hitFrame,int(tl.end) - 1));
         row(list,"FRAME",hitPlay ? "PLAYING" : (hitFrame < 0 ? "ALL PARTS" : (hitFrame + 1) + " of " + tl.end + "   " +
            HitboxView.phase(tl,hitFrame)),"Left/right: the move one frame at a time (the strip under the drawing: grey " +
            "startup, coloured active frames, dark recovery); the part that fires is the one the rows change. " +
            Prompts.KEYS.select + ": play it on a loop, slowed down.",function(dir:int):void
         {
            hitPlay = false;
            hitFrame = hitFrame + dir < -1 ? int(tl.end) - 1 : (hitFrame + dir >= int(tl.end) ? -1 : hitFrame + dir);
            partOnFrame(all,tl);
         },function():void
         {
            hitPlay = !hitPlay;
            partOnFrame(all,tl);
            build();
         },null,true);
         hitPart = Math.max(0,Math.min(hitPart,all.length - 1));
         var shapes:Array = all[hitPart].shapes;
         hitShape = Math.max(0,Math.min(hitShape,shapes.length - 1));
         var entry:int = int(all[hitPart].entry);
         row(list,"PART",(hitPart + 1) + " of " + all.length + "   (CastTime " + castParts[Math.min(entry,castParts.length - 1)] +
            ")","Left/right: the move's parts (one per CastTime entry with a hitbox).",function(dir:int):void
         {
            hitPart = ((hitPart + dir) % all.length + all.length) % all.length;
            hitShape = 0;
         },null,null,true);
         if(shapes.length > 1)
         {
            row(list,"SHAPE",(hitShape + 1) + " of " + shapes.length,"Left/right: this part's shapes (they hit at the same " +
               "time; \"&\" in the columns).",function(dir:int):void
            {
               hitShape = ((hitShape + dir) % shapes.length + shapes.length) % shapes.length;
            },null,null,true);
         }
         heading(list,"PART " + (hitPart + 1) + (shapes.length > 1 ? ", SHAPE " + (hitShape + 1) : ""));
         for each(var hc:Array in HIT_COLUMNS)
         {
            if(column[hc[0]] != null)
            {
               hitRow(list,hc,entries,entry,game,cur);
            }
         }
         if(method != "")
         {
            row(list,"SHAPE TYPE",method,"TargetMethod: how the game checks the hitbox (change it on ALL COLUMNS).",null,null,
               null);
         }
         buttonRow(list,"SAVE AS MOD","Writes every changed move into mods\\" + setId() + " (loaded at every start).",function():void
         {
            note = save();
            build();
         });
         view.draw(all,hitPart,hitShape,tl,hitPlay ? -1 : hitFrame);
         view.onFrame = function(f:int):void
         {
            hitFrame = f;
         };
         view.play(hitPlay);
         var drawn:Object = {"x":shapes[hitShape].x,"y":shapes[hitShape].y,"rx":shapes[hitShape].rx,"ry":shapes[hitShape].ry};
         view.onDrag = function(x:Number, y:Number, rx:Number, ry:Number):void
         {
            var moved:Object = {"x":x - drawn.x,"y":y - drawn.y,"rx":rx - drawn.rx,"ry":ry - drawn.ry};
            var said:Array = [];
            for each(var c:Array in HIT_COLUMNS)
            {
               if(moved[c[2]] != 0 && column[c[0]] != null)
               {
                  var at:Number = shapeValue(String(currentRow(move)[column[c[0]]]),entry,hitShape);
                  var why:String = isNaN(at) ? c[0] + " isn't a plain list here: type it on ALL COLUMNS" :
                     setShape(c[0],entries,entry,at + moved[c[2]]);
                  said.push(why != "" ? why : c[1] + " " + (at + moved[c[2]]));
               }
            }
            note = move + " part " + (hitPart + 1) + ": " + said.join(", ") + ". Try it, then SAVE AS MOD.";
            build();
         };
      }

      private function partOnFrame(all:Array, tl:Object) : void
      {
         var firing:Object = HitboxView.castAt(tl,hitFrame);
         for(var i:int = 0; firing != null && i < all.length; i++)
         {
            if(int(all[i].entry) == int(firing.entry) && hitPart != i)
            {
               hitPart = i;
               hitShape = 0;
            }
         }
      }

      private function hitRow(list:Sprite, hc:Array, entries:int, entry:int, game:Array, cur:Array) : void
      {
         var col:String = hc[0];
         var label:String = hc[1];
         var value:String = String(cur[column[col]]);
         var original:String = game != null ? String(game[column[col]]) : value;
         var n:Number = shapeValue(value,entry,hitShape);
         var was:Number = shapeValue(original,entry,hitShape);
         var differs:Boolean = value != original && n != was;
         var plain:Boolean = !isNaN(n);
         var done:Function = function(why:String):void
         {
            note = why != "" ? why : move + " " + col + " is now " + String(currentRow(move)[column[col]]) +
               ": try it, then SAVE AS MOD.";
         };
         row(list,label,(plain ? String(n) : value) + (differs ? "   (game: " + (isNaN(was) ? original : String(was)) + ")" : ""),
            (differs ? "Changed. " : "") + col + ". " + hc[3] + (plain ? "" : " This part uses a keyframe form: type the whole " +
            "column.") + "  " + Prompts.KEYS.select + ": type it.",plain ? function(dir:int):void
         {
            done(setShape(col,entries,entry,n + dir * 5));
         } : null,function():void
         {
            typeText(label,plain ? String(n) : value,plain ? 12 : 120,function(typed:String):void
            {
               if(plain && /^\s*-?\d+(\.\d+)?\s*$/.test(typed))
               {
                  done(setShape(col,entries,entry,Number(typed)));
               }
               else
               {
                  set(col,typed);
               }
               build();
            },true);
         },function():void
         {
            set(col,original);
            build();
         },false,differs);
      }

      private function setShape(col:String, entries:int, entry:int, n:Number) : String
      {
         var value:String = String(currentRow(move)[column[col]]);
         var next:String = withShapeValue(value,entries,entry,hitShape,n);
         if(next == null)
         {
            return col + " isn't a plain list here (\"" + value + "\"): type it on ALL COLUMNS.";
         }
         return apply(move,col,next);
      }

      private function legendSpec(p:PowerType) : Object
      {
         try
         {
            var players:* = ScreenManager.owner.var_7050;
            var legend:Object = players != null && players.length > 0 ? players[0] : null;
            if(legend == null || p == null || legend.var_108 == null)
            {
               return null;
            }
            var costume:CostumeType = legend.var_108 as CostumeType;
            return {"costume":costume,"scheme":legend.var_14421,"item":ItemType.method_8638(p.var_13984),
               "anim":p.method_3298(costume,null).var_10352,"frames":HitboxView.gameFrames(p,legend)};
         }
         catch(e:Error)
         {
            ErrorLog.write("move editor: no legend for the drawing: " + e);
         }
         return null;
      }

      private function buildLegend() : void
      {
         var list:Sprite = rowsPanel();
         var all:Array = LegendStats.legends();
         var playing:Array = LegendStats.current();
         if(hero == null || all.indexOf(hero) < 0)
         {
            hero = playing != null && all.indexOf(playing[0]) >= 0 ? playing[0] : (all.length > 0 ? all[0] : null);
         }
         if(hero == null)
         {
            UiKit.text(list,"No legend stats were loaded.",20,20,15,UiKit.GREY,UiKit.BOLD);
            return;
         }
         row(list,"LEGEND",LegendStats.displayName(hero),"Left/right: every legend. The one you play in Training comes first " +
            "when the tab opens.",function(dir:int):void
         {
            var at:int = all.indexOf(hero);
            hero = all[((at + dir) % all.length + all.length) % all.length];
            resetArmed = null;
         },null,null,true);
         for each(var pair:Array in LegendStats.stances(hero))
         {
            var index:int = pair[0];
            var total:int = 0;
            for each(var s0:Array in LegendStats.STATS)
            {
               total += LegendStats.value(hero,index,s0[0]);
            }
            var inUse:Boolean = playing != null && playing[0] == hero && playing[1] == index;
            heading(list,LegendStats.stanceName(pair[1]) + (index == 0 ? " (the legend's own)" : "") + "   total " + total +
               (inUse ? "   - YOU USE THIS ONE" : ""));
            for each(var st:Array in LegendStats.STATS)
            {
               statRow(list,index,st);
            }
         }
         buttonRow(list,"SAVE AS MOD","Writes every changed move and stat into mods\\" + setId() + " (loaded at every start).",
            function():void
         {
            note = save();
            build();
         });
      }

      private function statRow(list:Sprite, index:int, st:Array) : void
      {
         var col:String = st[0];
         var value:int = LegendStats.value(hero,index,col);
         var original:int = LegendStats.gameValue(hero,index,col);
         var differs:Boolean = value != original;
         row(list,st[1],value + (differs ? "   (game: " + original + ")" : ""),(differs ? "Changed. " : "") + st[3] +
            " 0 to " + LegendStats.MAX + ".  " + Prompts.KEYS.select + ": type it.",function(dir:int):void
         {
            setStat(index,col,Math.max(0,Math.min(LegendStats.MAX,value + dir)));
         },function():void
         {
            typeText(String(st[1]).toUpperCase(),String(value),2,function(typed:String):void
            {
               if(/^\d+$/.test(typed))
               {
                  setStat(index,col,int(typed));
               }
               else
               {
                  note = "Type a number from 0 to " + LegendStats.MAX + ".";
               }
               build();
            },true);
         },function():void
         {
            setStat(index,col,original);
            build();
         },false,differs);
      }

      private function buildPoints() : void
      {
         var list:Sprite = rowsPanel();
         var stats:Array = LegendStats.STATS;
         var playing:Array = LegendStats.current();
         if(pointStat < 0)
         {
            pointStat = 3;
         }
         if(points < 0)
         {
            points = playing != null ? LegendStats.value(playing[0],playing[1],stats[pointStat][0]) : 5;
         }
         row(list,"STAT",stats[pointStat][1],stats[pointStat][3],function(dir:int):void
         {
            pointStat = ((pointStat + dir) % stats.length + stats.length) % stats.length;
            if(playing != null)
            {
               points = LegendStats.value(playing[0],playing[1],stats[pointStat][0]);
            }
         },null,null,true);
         var yours:String = playing != null ? "  (" + LegendStats.displayName(playing[0]) + " has " +
            LegendStats.value(playing[0],playing[1],stats[pointStat][0]) + ")" : "";
         row(list,"POINTS",points + yours,"Left/right: 0 to " + LegendStats.MAX + ". The changes below apply to every legend " +
            "whose stance has this value.",function(dir:int):void
         {
            points = Math.max(0,Math.min(LegendStats.MAX,points + dir));
         },null,null,true);
         var name:String = stats[pointStat][0] + points;
         var cur:Object = LegendStats.pointRow(name);
         var cols:Array = [];
         for(var c:String in cur)
         {
            cols.push(c);
         }
         cols.sort();
         heading(list,"STATTYPES ROW " + name.toUpperCase());
         for each(c in cols)
         {
            pointRow(list,name,c,String(cur[c]));
         }
         buttonRow(list,"SAVE AS MOD","Writes every changed move and stat into mods\\" + setId() + " (loaded at every start).",
            function():void
         {
            note = save();
            build();
         });
      }

      private function pointRow(list:Sprite, name:String, col:String, value:String) : void
      {
         var original:String = LegendStats.gamePoint(name,col);
         var differs:Boolean = original != null && Number(original) != Number(value);
         var n:Number = Number(value);
         var by:Number = Math.abs(n) < 2 ? 0.01 : (Math.abs(n) < 20 ? 0.1 : 1);
         row(list,col,value + (differs ? "   (game: " + original + ")" : ""),(differs ? "Changed. " : "") +
            LegendStats.POINT_FIELDS[col] + "  " + Prompts.KEYS.select + ": type it.",function(dir:int):void
         {
            setPoint(name,col,String(Math.round((n + dir * by) * 10000) / 10000));
         },function():void
         {
            typeText(col.toUpperCase(),value,12,function(typed:String):void
            {
               setPoint(name,col,typed);
               build();
            },true);
         },function():void
         {
            if(original != null)
            {
               setPoint(name,col,original);
               build();
            }
         },false,differs);
      }

      private function setPoint(name:String, col:String, value:String) : void
      {
         var why:String = LegendStats.applyPoint(name,col,value);
         note = why != "" ? why : name + " " + col + " is now " + value + ": try it, then SAVE AS MOD.";
      }

      private function setStat(index:int, col:String, n:int) : void
      {
         var why:String = LegendStats.apply(hero,index,col,n);
         note = why != "" ? why : LegendStats.displayName(hero) + " " + col + " is now " + n + ": try it, then SAVE AS MOD.";
      }

      private function buildChanges() : void
      {
         var list:Sprite = rowsPanel();
         var all:Object = changes();
         var saving:Object = saved();
         var names:Array = [];
         for(var name:String in all)
         {
            names.push(name);
         }
         names.sort();
         var stanceSaved:Object = LegendStats.savedIn(savedTables());
         var stanceRows:Array = LegendStats.rows(LegendStats.changes(LegendStats.savedIn(savedTables())));
         var pointSaved:Object = LegendStats.savedPointsIn(savedTables());
         var pointRows:Array = LegendStats.pointRows(LegendStats.pointChanges(LegendStats.savedPointsIn(savedTables())));
         if(names.length == 0 && stanceRows.length == 0 && pointRows.length == 0)
         {
            UiKit.text(list,"Nothing differs from the game's. Change a move in the MOVE tab or a stat in LEGEND.",20,20,15,
               UiKit.GREY,UiKit.BOLD);
            return;
         }
         heading(list,"SET: " + setName().toUpperCase() + "  (mods\\" + setId() + ")");
         for each(var sr:Object in stanceRows)
         {
            var stats:Array = [];
            for(var sc:String in sr.set)
            {
               stats.push(sc + " " + sr.set[sc]);
            }
            stats.sort();
            var was:Object = stanceSaved[sr.stance] != null ? stanceSaved[sr.stance][String(sr.index)] : null;
            var stanceUnsaved:Boolean = JSON.stringify(was) != JSON.stringify(sr.set);
            var key:String = sr.stance + "/" + sr.index;
            row(list,LegendStats.displayName(sr.stance) + " stance " + sr.index,(resetArmed == key ? "PRESS AGAIN TO RESET" :
               (stanceUnsaved ? "not saved" : "saved")),stats.join(",  "),null,legendOpener(sr.stance),
               stanceResetter(sr.stance,sr.index),false,stanceUnsaved);
         }
         for each(var pr:Object in pointRows)
         {
            var pcols:Array = [];
            for(var pc:String in pr.set)
            {
               pcols.push(pc + " " + pr.set[pc]);
            }
            pcols.sort();
            var pointUnsaved:Boolean = JSON.stringify(pointSaved[pr.copy]) != JSON.stringify(pr.set);
            row(list,"Stat points " + pr.copy,(resetArmed == "points/" + pr.copy ? "PRESS AGAIN TO RESET" :
               (pointUnsaved ? "not saved" : "saved")),pcols.join(",  "),null,pointsOpener(pr.copy),pointsResetter(pr.copy),false,
               pointUnsaved);
         }
         for each(name in names)
         {
            var cols:Array = [];
            for(var col:String in all[name])
            {
               cols.push(col + " " + all[name][col]);
            }
            cols.sort();
            var unsaved:Boolean = JSON.stringify(saving[name]) != JSON.stringify(all[name]);
            row(list,name,(resetArmed == name ? "PRESS AGAIN TO RESET" : (unsaved ? "not saved" : "saved")),
               cols.join(",  "),null,opener(name),resetter(name),false,unsaved);
         }
         buttonRow(list,"SAVE AS MOD","Writes these moves into mods\\" + setId() + ".",function():void
         {
            note = save();
            build();
         });
         buttonRow(list,"NAME THIS SET","Gives these changes a name of their own (now \"" + setName() + "\", mods\\" + setId() +
            "): saved as mods\\moves-<name>, a mod you can share on the server (Mods > INSTALLED > SHARE ON SERVER).",
            function():void
         {
            typeText("SET NAME",setId() == MOD_ID ? "" : setName(),30,function(typed:String):void
            {
               note = nameSet(typed);
               build();
            });
         });
      }

      private function pointsOpener(name:String) : Function
      {
         return function():void
         {
            for(var i:int = 0; i < LegendStats.STATS.length; i++)
            {
               var stat:String = LegendStats.STATS[i][0];
               if(name.indexOf(stat) == 0 && /^\d+$/.test(name.substr(stat.length)))
               {
                  pointStat = i;
                  points = int(name.substr(stat.length));
               }
            }
            showTab(4);
         };
      }

      private function pointsResetter(name:String) : Function
      {
         return function():void
         {
            if(resetArmed != "points/" + name)
            {
               resetArmed = "points/" + name;
               build();
               return;
            }
            resetArmed = null;
            var why:String = LegendStats.resetPoint(name);
            note = why != "" ? why : name + " is back to the game's. " + save();
            build();
         };
      }

      private function legendOpener(name:String) : Function
      {
         return function():void
         {
            hero = name;
            showTab(3);
         };
      }

      private function stanceResetter(name:String, index:int) : Function
      {
         return function():void
         {
            var key:String = name + "/" + index;
            if(resetArmed != key)
            {
               resetArmed = key;
               build();
               return;
            }
            resetArmed = null;
            var why:String = LegendStats.reset(name,index);
            note = why != "" ? why : LegendStats.displayName(name) + " stance " + index + " is back to the game's. " + save();
            build();
         };
      }

      private function opener(name:String) : Function
      {
         return function():void
         {
            move = name;
            showTab(0);
         };
      }

      private function resetter(name:String) : Function
      {
         return function():void
         {
            if(resetArmed != name)
            {
               resetArmed = name;
               build();
               return;
            }
            resetArmed = null;
            note = resetMove(name);
            build();
         };
      }

      public static function resetMove(name:String) : String
      {
         var game:Array = gameRow(name);
         var cur:Array = currentRow(name);
         if(game == null || cur == null)
         {
            return "No move " + name + ".";
         }
         for(var c:int = 0; c < header.length; c++)
         {
            if(!LOCKED[header[c]] && cur[c] != game[c])
            {
               var why:String = apply(name,header[c],game[c]);
               if(why != "")
               {
                  return why;
               }
            }
         }
         return name + " is back to the game's. " + save();
      }

      private function row(parent:Sprite, label:String, value:String, about:String, change:Function, pick:Function,
                           option:Function, picker:Boolean = false, marked:Boolean = false) : void
      {
         var w:Number = rowsW - 24;
         var line:Sprite = new Sprite();
         line.x = 10;
         line.y = lastBottom(parent);
         parent.addChild(line);
         UiKit.rect(line,0,0,w,30,picker ? UiKit.PANEL : UiKit.BODY,6);
         var arrowX:Number = compact ? w * 0.5 : w * 0.34;
         UiKit.fit(UiKit.text(line,label,14,5,14,picker ? UiKit.TEAL : UiKit.WHITE,UiKit.BOLD),arrowX - 20);
         var vx:Number = compact ? (arrowX + 30 + w - 30) / 2 : w * 0.65;
         var v:TextField = UiKit.text(line,value,vx,5,14,marked ? UiKit.WHITE : UiKit.TEAL,UiKit.BOLD,0,true);
         UiKit.fit(v,compact ? w - 34 - arrowX - 40 : w * 0.55);
         v.x = vx - v.width / 2;
         if(marked && compact)
         {
            UiKit.rect(line,arrowX - 16,11,8,8,UiKit.TEAL,4);
         }
         if(change != null)
         {
            UiKit.arrow(line,arrowX,4,-1,function():void
            {
               change(-1);
               build();
            });
            UiKit.arrow(line,w - 30,4,1,function():void
            {
               change(1);
               build();
            });
         }
         var index:int = items.length;
         line.addEventListener(MouseEvent.CLICK,function(e:MouseEvent):void
         {
            focus = index;
            paintFocus();
         });
         items.push({"sprite":line,"parent":parent,"width":w,"height":30,"change":change,"use":pick,"option":option,
            "about":about,"label":label});
      }

      private function buttonRow(parent:Sprite, label:String, about:String, act:Function) : void
      {
         var holder:Sprite = new Sprite();
         holder.y = lastBottom(parent);
         parent.addChild(holder);
         button(holder,label,10,2,220,act,30,14);
         items.push({"sprite":holder,"parent":parent,"width":230,"height":34,"use":act,"about":about,"focusBox":[2,2,4,30],
            "label":label});
      }

      private function heading(parent:Sprite, s:String) : void
      {
         var t:TextField = UiKit.text(parent,s,16,lastBottom(parent) + 6,13,UiKit.GREY,UiKit.XBOLD);
         t.name = "heading";
      }

      private static function lastBottom(parent:Sprite) : Number
      {
         var bottom:Number = 0;
         for(var i:int = 0; i < parent.numChildren; i++)
         {
            var c:Object = parent.getChildAt(i);
            bottom = Math.max(bottom,c.y + (c is TextField ? 28 : 34));
         }
         return bottom;
      }

      override protected function focused(it:Object) : void
      {
         if(describe != null)
         {
            describeText(describe,it.about ? String(it.about) : "");
         }
         if(describeLabel != null)
         {
            describeLabel.text = it.label ? String(it.label).toUpperCase() : "";
         }
      }

      override protected function optionItem(it:Object) : void
      {
         if(it.option != null)
         {
            it.option();
         }
      }

   }
}
