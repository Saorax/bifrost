package bh.platform
{
   import flash.desktop.NativeApplication;
   import flash.events.GameInputEvent;
   import flash.filesystem.FileMode;
   import flash.filesystem.FileStream;
   import flash.ui.GameInput;
   import flash.ui.GameInputDevice;
   import flash.utils.ByteArray;
   import flash.utils.getTimer;
   import flash.utils.setTimeout;

   public final class Controllers
   {
      private static var input:GameInput;
      private static var lines:int = 0;
      private static var drain:ByteArray = new ByteArray();
      private static var wasActive:Boolean = true;

      public static function unfocused(c:Object) : Boolean
      {
         if(NativeApplication.nativeApplication.activeWindow != null)
         {
            if(!wasActive)
            {
               wasActive = true;
               Platform.log("controllers: window active, controllers read again");
            }
            return false;
         }
         if(c.var_15394 == null || int(c.var_15394.numControls) <= 0 || ModSettings.value("controllersInBackground") == true)
         {
            return false;
         }
         if(wasActive)
         {
            wasActive = false;
            Platform.log("controllers: window not active, controllers read as released");
         }
         try
         {
            c.var_15394.getCachedSamples(drain);
         }
         catch(e:Error)
         {
         }
         drain.length = 0;
         var now:Object = c.var_12051;
         var before:Object = c.var_2864;
         for each(var list:Object in [c.var_984,c.var_854])
         {
            if(list == null)
            {
               continue;
            }
            for(var i:int = 0; i < int(list.length); i++)
            {
               var key:String = list[i];
               before.set(key,now.get(key));
               now.set(key,0);
            }
         }
         return true;
      }

      public static function listening(core:Object) : void
      {
         try
         {
            write("the game read the devices: " + GameInput.numDevices + " device(s)");
            for(var i:int = 0; i < GameInput.numDevices; i++)
            {
               var device:GameInputDevice = GameInput.getDeviceAt(i);
               if(device != null)
               {
                  write("  " + describe(device));
                  held(device,"  startup");
               }
            }
         }
         catch(e:Error)
         {
            write("the game read the devices: " + e.message);
         }
      }

      public function Controllers()
      {
      }

      public static function removing(pad:Object) : void
      {
         try
         {
            if(pad != null && pad.var_594 != null)
            {
               var player:Object = pad.var_594;
               var core:Object = Object(GameApp.mainInstance).var_13259;
               var inMatch:Boolean = false;
               var players:Object = core.var_7050;
               for(var i:int = 0; players != null && i < int(players.length); i++)
               {
                  if(players[i] === player)
                  {
                     inMatch = true;
                     break;
                  }
               }
               if(player.var_6307 == null || !inMatch)
               {
                  pad.var_594 = null;
                  write("removed pad " + pad.mID + " pointed at a player no longer in a match; cleared");
               }
            }
         }
         catch(e:Error)
         {
            try
            {
               pad.var_594 = null;
            }
            catch(e2:Error)
            {
            }
         }
      }

      public static function init() : void
      {
         try
         {
            input = new GameInput();
            input.addEventListener(GameInputEvent.DEVICE_UNUSABLE,function(e:GameInputEvent):void
            {
               write("unusable (AIR: in use elsewhere or not readable): " + describe(e.device));
            });
            Hooks.controllerAdded.add(function(device:Object):void
            {
               write("added: " + describe(device as GameInputDevice));
               setTimeout(held,500,device,"added");
            });
            Hooks.controllerRemoved.add(function(device:Object):void
            {
               write("removed: " + describe(device as GameInputDevice));
            });
         }
         catch(e:Error)
         {
            Platform.log("controller log: " + e.message);
         }
      }

      private static function held(device:Object, what:String) : void
      {
         var list:* = class_112.var_9206;
         for(var i:int = 0; list != null && i < int(list.length); i++)
         {
            if(list[i].var_8082 === device)
            {
               write(what + ": the game uses it as controller " + list[i].mID + " (" + list.length + " in use)");
               return;
            }
         }
         write(what + ": the game does NOT use it (" + (list != null ? list.length : 0) + " in use)");
      }

      private static function describe(device:GameInputDevice) : String
      {
         if(device == null)
         {
            return "(no device)";
         }
         var out:String = "\"" + device.name + "\" id " + device.id + ", " + device.numControls + " controls";
         try
         {
            var type:Object = match(device.name,device.numControls);
            out += type != null ? ", table: " + type.mDisplayName + " (type " + type.var_1964 + ")" :
               ", table: NO ENTRY for " + ControllerType.method_5723(device.name);
         }
         catch(e:Error)
         {
            out += ", table not loaded";
         }
         return out;
      }

      private static function match(name:String, controls:uint) : Object
      {
         var table:* = ControllerType.var_4966;
         if(table == null)
         {
            throw new Error("no table");
         }
         var type:Object = table.method_4935(ControllerType.method_5723(name,controls));
         return type != null ? type : table.method_4935(ControllerType.method_5723(name));
      }

      private static function write(text:String) : void
      {
         if(++lines > 400)
         {
            return;
         }
         try
         {
            var stream:FileStream = new FileStream();
            stream.open(Platform.dataFile("bh-controllers.txt"),lines == 1 ? FileMode.WRITE : FileMode.APPEND);
            stream.writeUTFBytes(new Date().toString() + " [" + getTimer() + "] " + text + "\r\n");
            stream.close();
         }
         catch(e:Error)
         {
         }
      }
   }
}
