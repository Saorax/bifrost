package bh.platform
{
   import bh.platform.net.P2PSession;
   import bh.platform.net.TrainingSync;
   import haxe.ds.StringMap;

   public final class OnlineTraining
   {
      public static const TRAINING:uint = 1;

      public static const MARK:uint = 0x100;

      private static const TRAINING_MODE:uint = 32768;

      private static function get DISPLAY_ROWS() : Array
      {
         if(displayRows == null)
         {
            displayRows = rows(["Player_ShowHitboxes","Player_ShowHurtBoxes","Player_ShowSpawnPoints"]).concat([TrainingMenu.FIRST,TrainingMenu.FIRST + 1]);
         }
         return displayRows;
      }

      private static var displayRows:Array = null;
      private static var syncedRows:Array = null;
      private static var lookRows:Array = null;
      private static var controlRow:int = -2;

      private static function rows(names:Array) : Array
      {
         var out:Array = [];
         for each(var name:String in names)
         {
            var i:int = int(class_549.__constructs__.indexOf(name));
            if(i >= 0)
            {
               out.push(i);
            }
         }
         return out;
      }

      private static function get SYNCED_ROWS() : Array
      {
         if(syncedRows == null)
         {
            syncedRows = rows(["Player_SpawnWeapon","Player_SpawnGadget","Player_ShowDamage","Player_ShowImpulse",
               "Player_ShowStun","Player_ItemsToggle","Bot_SpawnWeapon","Bot_SpawnGadget","Bot_Difficulty","Bot_Constraint",
               "Bot_ReactionDodge","Bot_ReactionJump","Bot_ReactionAttack","Bot_SetDamage","Bot_HealthResetToggle",
               "Bot_PositionResetToggle","Bot_ResetMode"]);
         }
         return syncedRows;
      }

      private static function get LOOK_ROWS() : Array
      {
         if(lookRows == null)
         {
            lookRows = rows(["Player_Hero","Player_Costume","Player_Color","Bot_Hero","Bot_Costume"]);
         }
         return lookRows;
      }

      public static function get CONTROL_ROW() : int
      {
         if(controlRow == -2)
         {
            controlRow = int(class_549.__constructs__.indexOf("Bot_ControlBot"));
         }
         return controlRow;
      }

      private static var controlledBy:uint = 0;

      private static var applyingLook:Boolean = false;

      private static const LOOK_FIELDS:Array = [["var_4103","var_1096"],["var_6764","var_2964"],["var_8985","var_14908"],
         ["var_7724","var_14680"],["var_15109","var_3652"]];

      private static const HERO_FIELDS:Array = [0,3];

      private static function heroId(index:int) : int
      {
         var heroes:Object = HeroType.var_10653;
         return index >= 0 && index < int(heroes.length) ? int(heroes[index].var_12172) : -1;
      }

      private static function heroIndex(id:int) : int
      {
         var heroes:Object = HeroType.var_10653;
         for(var i:int = 0; i < int(heroes.length); i++)
         {
            if(int(heroes[i].var_12172) == id)
            {
               return i;
            }
         }
         return -1;
      }

      private static function lookValue(look:Array, i:int) : int
      {
         var value:int = int(look[i + 1]) == 0xFFFF ? -1 : int(look[i + 1]);
         return value >= 0 && HERO_FIELDS.indexOf(i) >= 0 ? heroIndex(value) : value;
      }


      private static var applying:Boolean = false;

      private static const SCREEN_DEFAULTS:Object = {"var_14862":false,"var_8504":false,"var_12692":false,
         "var_11699":false,"var_7987":false,"var_2783":false,"var_2786":true,"var_6486":false,"var_5340":false,
         "var_3659":0,"var_8460":0,"var_6017":0,"var_2999":0,"var_10621":0,"var_12528":0,"var_1053":0,"var_1645":0,
         "var_12759":0,"var_10408":0,"var_2919":0,"var_1566":0};

      public static var active:Boolean = false;

      private static var savedSettings:Object = null;

      private static var savedScreen:Object = null;

      private static var refusedShown:Boolean = false;

      public function OnlineTraining()
      {
      }

      public static function init() : void
      {
         Hooks.matchEnded.add(function(to:uint):void
         {
            finish();
         });
         Hooks.trainingRowChange.add(refusesRow);
         Hooks.keyDown.add(onKey);
      }

      private static function onKey(event:Object) : Boolean
      {
         if(!active || event == null || event.ctrlKey || event.altKey || event.shiftKey || !TrainingSync.usable)
         {
            return false;
         }
         var code:uint = uint(event.keyCode);
         if(code != 118 && code != 117 && code != 116)
         {
            return false;
         }
         try
         {
            TrainingSync.pauseKey(Object(GameApp.mainInstance).var_13259,code == 118 ? "F7" : (code == 117 ? "F6" : "F5"),0);
         }
         catch(e:Error)
         {
            ErrorLog.write("online training: " + e + " " + e.getStackTrace());
         }
         return true;
      }

      public static function get requested() : Boolean
      {
         return ModSettings.flag("roomTraining",false);
      }

      public static function set requested(on:Boolean) : void
      {
         ModSettings.setFlag("roomTraining",on);
      }

      public static function startFlags() : uint
      {
         return MARK | (requested ? TRAINING : 0);
      }

      public static function readFlags(packet:Object) : uint
      {
         try
         {
            var bytes:Object = packet.var_5085.var_15327;
            var bitsLeft:int = int(bytes.length) * 8 - int(packet.var_5085.var_11198);
            if(bitsLeft < 8)
            {
               return 0;
            }
            var v:uint = packet.readUint();
            return (v & MARK) != 0 ? v & 0xFF : 0;
         }
         catch(e:Error)
         {
         }
         return 0;
      }

      public static function launch(core:Object) : void
      {
         finish();
         var screen:Object = ScreenManager.var_14532;
         var settings:Object = core.var_8999;
         savedSettings = new class_166();
         savedSettings.method_3381(settings);
         var row:Object = trainingRow(settings);
         var roomMode:String = settings.var_615 != null ? String(settings.var_615.var_9187) : "?";
         settings.method_4452(row);
         savedScreen = {};
         for(var field:String in SCREEN_DEFAULTS)
         {
            savedScreen[field] = screen[field];
            screen[field] = SCREEN_DEFAULTS[field];
         }
         active = true;
         refusedShown = false;
         controlledBy = 0;
         Platform.log("online training: " + row.var_11207 + " for a room in " + roomMode);
         core.method_3264();
         core.var_3595 = TRAINING_MODE;
         core.method_4157(true,true,"training");
         screen.method_4772();
      }

      private static function trainingRow(settings:Object) : Object
      {
         var rows:Object = class_163.var_8065;
         var mode:Object = settings.var_615;
         if(mode != null && mode !== ScoringType.method_1536(class_163.var_2518.var_615))
         {
            for(var i:int = 0; i < int(rows.length); i++)
            {
               if(String(rows[i].var_11207).indexOf(TrainingModes.PREFIX) == 0 && ScoringType.method_1536(rows[i].var_615) === mode)
               {
                  return rows[i];
               }
            }
         }
         return class_163.var_2518;
      }

      private static function finish() : void
      {
         if(!active)
         {
            return;
         }
         active = false;
         try
         {
            var core:Object = Object(GameApp.mainInstance).var_13259;
            if(savedSettings != null)
            {
               core.var_8999.method_3381(savedSettings);
            }
            var screen:Object = ScreenManager.var_14532;
            for(var field:String in savedScreen)
            {
               screen[field] = savedScreen[field];
            }
            Platform.log("online training ended: the room's settings and the Training screen's are back");
         }
         catch(e:Error)
         {
            ErrorLog.write("online training: " + e + " " + e.getStackTrace());
         }
         savedSettings = null;
         savedScreen = null;
      }

      public static function refuses(what:String) : Boolean
      {
         if(!active)
         {
            return false;
         }
         if(!refusedShown)
         {
            refusedShown = true;
            Platform.log("online training: the Training tools that change the match are off (every PC must play the same " +
               "match; first asked: " + what + ")");
         }
         return true;
      }

      public static function refusesRow(screen:Object, row:Object, direction:int) : Boolean
      {
         if(!active)
         {
            return false;
         }
         try
         {
            var index:int = int(row.var_5108.index);
            if(applying || DISPLAY_ROWS.indexOf(index) >= 0)
            {
               return false;
            }
            if((LOOK_ROWS.indexOf(index) >= 0 || index == CONTROL_ROW) && TrainingSync.usable)
            {
               return false;
            }
            if(SYNCED_ROWS.indexOf(index) >= 0 && TrainingSync.usable)
            {
               TrainingSync.queueLocal(screen.owner,index,direction);
               return true;
            }
            return refuses("Training setting " + row.var_5108.index);
         }
         catch(e:Error)
         {
         }
         return true;
      }

      public static function applyRow(core:Object, index:int, direction:int, senderId:uint) : void
      {
         if(index == CONTROL_ROW)
         {
            applyControl(core,direction,senderId);
            return;
         }
         var screen:Object = ScreenManager.var_14532;
         var value:Object = class_549[String(class_549.__constructs__[index])];
         if(value == null)
         {
            return;
         }
         var row:Object = screen.var_3041 != null ? screen.var_3041.method_4935(value) : null;
         if(row == null)
         {
            row = new class_674();
            row.var_5108 = value;
         }
         var local:Object = core.var_9499;
         var players:Object = core.var_7050;
         for(var i:int = 0; i < int(players.length); i++)
         {
            if(players[i] != null && uint(players[i].var_14656) == senderId && players[i].var_8233 == null)
            {
               core.var_9499 = players[i];
            }
         }
         applying = true;
         try
         {
            screen.method_2907(row,direction);
            screen.method_1502();
         }
         finally
         {
            applying = false;
            core.var_9499 = local;
         }
      }

      public static function menuOpened(screen:Object) : void
      {
         if(!active || screen.owner.var_9499 != null)
         {
            return;
         }
         try
         {
            var core:Object = screen.owner;
            var players:Object = core.var_7050;
            for(var i:int = 0; i < int(players.length); i++)
            {
               var p:Object = players[i];
               if(p != null && p.var_8233 == null && uint(p.var_14656) == uint(core.var_14656) && p.var_13881 != null)
               {
                  screen.var_1096 = int(HeroType.var_10653.indexOf(p.var_13881));
                  screen.var_2964 = int(p.var_13881.var_10772.indexOf(p.var_108));
                  if(p.var_108 != null && p.var_108.var_9162 && p.var_10767 != null)
                  {
                     screen.var_2964 = int(p.var_13881.var_10772.indexOf(p.var_10767[0]));
                  }
                  screen.var_14908 = class_76.var_12696.indexOf(p.var_14421);
                  screen.var_4103 = screen.var_1096;
                  screen.var_6764 = screen.var_2964;
                  screen.var_8985 = screen.var_14908;
                  screen.method_1502();
                  return;
               }
            }
         }
         catch(e:*)
         {
            ErrorLog.write("online training menu: " + e);
         }
      }

      public static function closing(screen:Object) : void
      {
         if(!active || applyingLook)
         {
            return;
         }
         try
         {
            var flags:uint = 0;
            var look:Array = [0];
            for(var i:int = 0; i < LOOK_FIELDS.length; i++)
            {
               var f:Array = LOOK_FIELDS[i];
               if(int(screen[f[0]]) != int(screen[f[1]]))
               {
                  flags |= 1 << i;
               }
               look.push((HERO_FIELDS.indexOf(i) >= 0 ? heroId(int(screen[f[1]])) : int(screen[f[1]])) & 0xFFFF);
               screen[f[0]] = screen[f[1]];
            }
            if(flags != 0 && TrainingSync.usable)
            {
               look[0] = flags;
               TrainingSync.queueLocal(screen.owner,TrainingSync.LOOK,0,look);
            }
            else if(flags != 0)
            {
               refuses("Training look " + flags);
            }
            if(int(screen.var_2919) != int(screen.var_1566))
            {
               if(TrainingSync.usable)
               {
                  TrainingSync.queueLocal(screen.owner,CONTROL_ROW,int(screen.var_2919));
               }
               else
               {
                  refuses("Training bot control " + screen.var_2919);
                  screen.var_2919 = screen.var_1566;
               }
               screen.var_1566 = screen.var_2919;
            }
         }
         catch(e:Error)
         {
            ErrorLog.write("online training closing: " + e + " " + e.getStackTrace());
         }
      }

      public static function applyLook(core:Object, look:Array, senderId:uint) : void
      {
         var screen:Object = ScreenManager.var_14532;
         var flags:uint = uint(look[0]);
         var saved:Object = {};
         var i:int;
         for(i = 0; i < LOOK_FIELDS.length; i++)
         {
            saved[LOOK_FIELDS[i][0]] = screen[LOOK_FIELDS[i][0]];
            saved[LOOK_FIELDS[i][1]] = screen[LOOK_FIELDS[i][1]];
         }
         var savedMode:Object = screen.var_2386;
         var savedControl:int = int(screen.var_1566);
         var local:Object = core.var_9499;
         var loadouts:Object = core.var_261.var_2498;
         var sender:Object = null;
         var players:Object = core.var_7050;
         for(i = 0; i < int(players.length); i++)
         {
            if(players[i] != null && uint(players[i].var_14656) == senderId && players[i].var_8233 == null)
            {
               sender = players[i];
            }
         }
         applyingLook = true;
         var failed:* = null;
         try
         {
            core.var_261.var_2498 = new StringMap();
            screen.var_2386 = screen.var_13997;
            screen.var_1566 = screen.var_2919;
            for(var part:int = 0; part < 2; part++)
            {
               var from:int = part == 0 ? 0 : 3;
               var to:int = part == 0 ? 3 : 5;
               var any:Boolean = false;
               for(i = 0; i < LOOK_FIELDS.length; i++)
               {
                  var value:int = lookValue(look,i);
                  var changed:Boolean = i >= from && i < to && (flags & (1 << i)) != 0;
                  screen[LOOK_FIELDS[i][1]] = value;
                  screen[LOOK_FIELDS[i][0]] = changed ? -2 : value;
                  any = any || changed;
               }
               if(any && (part == 1 || sender != null))
               {
                  core.var_9499 = part == 0 ? sender : local;
                  screen.method_8652();
               }
            }
         }
         catch(e:*)
         {
            failed = e;
         }
         applyingLook = false;
         core.var_9499 = local;
         core.var_261.var_2498 = loadouts;
         screen.var_2386 = savedMode;
         screen.var_1566 = savedControl;
         var mine:Boolean = local != null && uint(local.var_14656) == senderId;
         for(i = 0; i < LOOK_FIELDS.length; i++)
         {
            var af:String = LOOK_FIELDS[i][0];
            var mf:String = LOOK_FIELDS[i][1];
            screen[af] = saved[af];
            screen[mf] = saved[mf];
            if((flags & (1 << i)) != 0 && (i >= 3 || mine) && int(saved[af]) == int(saved[mf]))
            {
               screen[af] = screen[mf] = lookValue(look,i);
            }
         }
         if(failed != null)
         {
            throw failed;
         }
      }

      public static function applyControl(core:Object, mode:int, senderId:uint) : void
      {
         var screen:Object = ScreenManager.var_14532;
         var sender:Object = null;
         var previous:Object = null;
         var players:Object = core.var_7050;
         for(var i:int = 0; i < int(players.length); i++)
         {
            var p:Object = players[i];
            if(p != null && p.var_8233 == null && uint(p.var_14656) == senderId)
            {
               sender = p;
            }
            if(p != null && p.var_8233 == null && controlledBy != 0 && uint(p.var_14656) == controlledBy)
            {
               previous = p;
            }
         }
         if(sender == null || mode < 0 || mode > 3)
         {
            return;
         }
         var mine:Boolean = int(screen.var_2919) != int(screen.var_1566);
         var menuValue:int = int(screen.var_2919);
         if(previous != null)
         {
            previous.var_14147 = false;
         }
         var local:Object = core.var_9499;
         core.var_9499 = sender;
         screen.var_2919 = mode;
         var failed:* = null;
         try
         {
            screen.method_5507();
         }
         catch(e:*)
         {
            failed = e;
         }
         core.var_9499 = local;
         controlledBy = mode == 0 ? 0 : senderId;
         P2PSession.botController = controlledBy;
         screen.var_1566 = mode;
         screen.var_2919 = mine ? menuValue : mode;
         try
         {
            screen.method_1502();
         }
         catch(e2:*)
         {
         }
         Platform.log("online training: bot control " + mode + " from ID " + senderId);
         if(failed != null)
         {
            throw failed;
         }
      }

      public static function refusesKey(core:Object, key:String, held:uint = 0) : Boolean
      {
         if(active && (key == "F7" || key == "F6" || key == "F5") && TrainingSync.usable)
         {
            TrainingSync.pauseKey(core,key,held);
            return true;
         }
         return refuses("Training key " + key);
      }

      public static function menuPaused(screen:Object) : void
      {
         if(!active)
         {
            return;
         }
         screen.owner.method_4932();
      }
   }
}
