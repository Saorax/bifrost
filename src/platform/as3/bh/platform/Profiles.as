package bh.platform
{
   import flash.utils.Dictionary;

   public final class Profiles
   {
      public static const DEFAULT:String = "Default";
      public static const BOT:String = "%^%^BOT#$#$#$";

      private static var restored:Dictionary = new Dictionary(true);

      private static var loadedKeyProfile:String = null;

      public function Profiles()
      {
      }

      public static function forSlot(mgr:class_310, slot:uint) : class_309
      {
         nameForSlot(mgr, slot);
         return null;
      }

      public static function nameForSlot(mgr:class_310, slot:uint) : String
      {
         controlsNameForSlot(mgr, slot);
         return null;
      }

      public static function controlsProfile(screen:Object, slot:uint, fallback:class_309) : class_309
      {
         var mgr:class_310 = screen != null && screen.owner != null ? screen.owner.var_261 as class_310 : null;
         var name:String = controlsNameForSlot(mgr, slot);
         var p:class_309 = name == null ? null : byName(mgr, name);
         return p != null ? p : fallback;
      }

      public static function controlsNameForSlot(mgr:class_310, slot:uint) : String
      {
         if(mgr == null || slot >= 8 || class_112.var_5048 == null || slot >= uint(class_112.var_5048.length))
         {
            return null;
         }
         var dev:class_223 = class_112.var_5048[slot];
         if(dev == null)
         {
            return null;
         }
         var name:String = deviceProfile(mgr, dev.mControllerID);
         if(name == DEFAULT || byName(mgr, name) == null)
         {
            return null;
         }
         return name;
      }

      public static function deviceProfile(mgr:class_310, controllerID:uint) : String
      {
         if(controllerID != 0)
         {
            restore(mgr, controllerID);
            var p:class_309 = mgr == null ? null : mgr.var_14320.method_4935(controllerID) as class_309;
            return p == null ? DEFAULT : p.var_11943;
         }
         var saved:* = ModSettings.value("keyboardProfile");
         return saved is String && byName(mgr, saved) != null ? saved : DEFAULT;
      }

      public static function assignDevice(mgr:class_310, controllerID:uint, name:String) : Boolean
      {
         if(mgr == null || name == null || name == BOT)
         {
            return false;
         }
         if(byName(mgr, name) == null && !create(mgr, name))
         {
            return false;
         }
         if(controllerID != 0)
         {
            if(!mgr.method_1819(name, controllerID))
            {
               return false;
            }
            if(controllerOf(controllerID) != null)
            {
               restored[controllerOf(controllerID)] = true;
            }
            var key:String = deviceKey(controllerID);
            if(key != null)
            {
               var map:Object = controllerMap();
               if(name == DEFAULT)
               {
                  delete map[key];
               }
               else
               {
                  map[key] = name;
               }
               ModSettings.setValue("controllerProfiles", map);
            }
         }
         else
         {
            ModSettings.setValue("keyboardProfile", name == DEFAULT ? undefined : name);
         }
         ErrorLog.write("profiles: " + (controllerID != 0 ? "controller " + controllerID : "keyboard") + " uses \"" + name + "\"");
         return true;
      }

      public static function keySuffix(suffix:String) : String
      {
         if(suffix != null && suffix != "")
         {
            return suffix;
         }
         if(loadedKeyProfile == null)
         {
            var saved:* = ModSettings.value("keyboardProfile");
            loadedKeyProfile = saved is String && saved != DEFAULT ? saved : DEFAULT;
         }
         return loadedKeyProfile == DEFAULT ? suffix : "@" + loadedKeyProfile;
      }

      public static function keyboardRestartPending() : Boolean
      {
         keySuffix("");
         var saved:* = ModSettings.value("keyboardProfile");
         return (saved is String ? saved : DEFAULT) != loadedKeyProfile;
      }

      public static function current(mgr:class_310, slot:uint) : String
      {
         var name:String = controlsNameForSlot(mgr, slot);
         return name == null ? DEFAULT : name;
      }

      public static function names(mgr:class_310) : Array
      {
         var out:Array = [DEFAULT];
         if(mgr == null)
         {
            return out;
         }
         for each(var p:class_309 in mgr.var_3341)
         {
            if(p != null && p.var_11943 != DEFAULT && p.var_11943 != BOT && !p.var_14065)
            {
               out.push(p.var_11943);
            }
         }
         return out;
      }

      public static function validName(mgr:class_310, name:String) : Boolean
      {
         return mgr != null && name != null && /^[A-Za-z0-9 _\-]{1,16}$/.test(name) && name != BOT
            && byName(mgr, name) == null;
      }

      public static function create(mgr:class_310, name:String) : Boolean
      {
         if(!validName(mgr, name) || !mgr.method_4596(name, true))
         {
            return false;
         }
         var p:class_309 = byName(mgr, name);
         if(p != null && mgr.var_3341.indexOf(p) < 0)
         {
            mgr.var_3341.push(p);
         }
         ErrorLog.write("profiles: created \"" + name + "\"");
         return true;
      }

      public static function assign(mgr:class_310, slot:uint, name:String) : Boolean
      {
         var dev:class_223 = class_112.var_5048 != null && slot < 8 && slot < uint(class_112.var_5048.length) ? class_112.var_5048[slot] : null;
         return dev != null && assignDevice(mgr, dev.mControllerID, name);
      }

      public static function remove(mgr:class_310, name:String) : Boolean
      {
         var p:class_309 = byName(mgr, name);
         if(p == null || name == DEFAULT || name == BOT)
         {
            return false;
         }
         var pad:* = mgr.var_12201.exists(name) ? mgr.var_12201.method_4935(name) : null;
         mgr.method_2375(name);
         if(pad != null && uint(pad) != 0)
         {
            mgr.method_1819(DEFAULT, uint(pad));
         }
         if(ModSettings.value("keyboardProfile") == name)
         {
            ModSettings.setValue("keyboardProfile", undefined);
         }
         var map:Object = controllerMap();
         for(var dk:String in map)
         {
            if(map[dk] == name)
            {
               delete map[dk];
            }
         }
         ModSettings.setValue("controllerProfiles", map);
         mgr.var_2498.remove(name);
         var i:int = mgr.var_3341.indexOf(p);
         if(i >= 0)
         {
            mgr.var_3341.splice(i, 1);
         }
         var data:Object = mgr.var_12819.data;
         var list:Array = data.profileList as Array;
         if(list != null && list.indexOf(name) >= 0)
         {
            list.splice(list.indexOf(name), 1);
            data.profileList = list;
         }
         var gone:Array = [];
         var key:String;
         for each(var pre:String in ["ct_", "wst_", "cst_", "sbt_", "teamcst_", "stance_", "pet_", "egt_", "lastUsed_",
            "wstfavs_", "cstfavs_", "mappingsList_"])
         {
            gone.push(pre + name);
         }
         for each(var m:String in p.var_1727)
         {
            for each(pre in ["displayname", "dpadmove", "jumponup", "mappingname", "pickuplightattack",
               "disablerightsticktaunts", "simplestickread"])
            {
               gone.push("cmap_" + pre + "_" + m + "_" + name);
            }
            var tail:String = "_" + m + "_" + name;
            for(key in data)
            {
               if(key.indexOf("cmap_input_") == 0 && key.substr(key.length - tail.length) == tail
                  && /^cmap_input_\d+$/.test(key.substr(0, key.length - tail.length)))
               {
                  gone.push(key);
               }
            }
         }
         var n:int = 0;
         for each(key in gone)
         {
            if(key in data)
            {
               delete data[key];
               n++;
            }
         }
         try
         {
            mgr.var_12819.flush();
         }
         catch(e:Error)
         {
         }
         var binds:Object = mgr.owner != null && mgr.owner.keybindsStore != null ? mgr.owner.keybindsStore.data : null;
         if(binds != null)
         {
            var bindKeys:Array = [];
            for(key in binds)
            {
               if(key.substr(key.length - name.length - 1) == "@" + name)
               {
                  bindKeys.push(key);
               }
            }
            for each(key in bindKeys)
            {
               delete binds[key];
            }
            try
            {
               mgr.owner.keybindsStore.flush();
            }
            catch(e2:Error)
            {
            }
            n += bindKeys.length;
         }
         ErrorLog.write("profiles: deleted \"" + name + "\" (" + n + " saved keys)");
         return true;
      }

      public static function cycleDevice(mgr:class_310, controllerID:uint, dir:int) : String
      {
         var list:Array = names(mgr);
         var i:int = list.indexOf(deviceProfile(mgr, controllerID));
         i = ((i < 0 ? 0 : i) + dir + list.length) % list.length;
         return assignDevice(mgr, controllerID, list[i]) ? list[i] : null;
      }

      public static function devices() : Array
      {
         var out:Array = [{"id":0, "name":"Keyboard"}];
         for each(var c:class_87 in class_112.var_9206)
         {
            if(c != null && c.mID != 0)
            {
               var label:String = null;
               try
               {
                  label = c.var_8082 != null ? c.var_8082.name : null;
               }
               catch(e:Error)
               {
               }
               out.push({"id":c.mID, "name":label || "Controller " + c.mID});
            }
         }
         return out;
      }

      private static function restore(mgr:class_310, controllerID:uint) : void
      {
         var pad:class_87 = controllerOf(controllerID);
         if(mgr == null || pad == null || restored[pad])
         {
            return;
         }
         restored[pad] = true;
         var key:String = deviceKey(controllerID);
         var name:* = controllerMap()[key];
         var p:class_309 = mgr.var_14320.method_4935(controllerID) as class_309;
         if(name is String && byName(mgr, name) != null && (p == null || p.var_11943 == DEFAULT))
         {
            mgr.method_1819(name, controllerID);
            ErrorLog.write("profiles: " + key + " (controller " + controllerID + ") uses its saved \"" + name + "\"");
         }
      }

      private static function deviceKey(controllerID:uint) : String
      {
         var mine:String = null;
         var ids:Array = [];
         var all:Array = [];
         for each(var c:class_87 in class_112.var_9206)
         {
            if(c != null && c.mID != 0)
            {
               var n:String = "Controller";
               try
               {
                  n = c.var_8082 != null && c.var_8082.name ? c.var_8082.name : n;
               }
               catch(e:Error)
               {
               }
               all.push({"id":c.mID, "name":n});
               if(c.mID == controllerID)
               {
                  mine = n;
               }
            }
         }
         if(mine == null)
         {
            return null;
         }
         for each(var o:Object in all)
         {
            if(o.name == mine)
            {
               ids.push(o.id);
            }
         }
         ids.sort(Array.NUMERIC);
         return mine + "#" + (ids.indexOf(controllerID) + 1);
      }

      private static function controllerOf(controllerID:uint) : class_87
      {
         for each(var c:class_87 in class_112.var_9206)
         {
            if(c != null && c.mID == controllerID)
            {
               return c;
            }
         }
         return null;
      }

      private static function controllerMap() : Object
      {
         var m:* = ModSettings.value("controllerProfiles");
         return m != null && typeof m == "object" ? m : {};
      }

      private static function byName(mgr:class_310, name:String) : class_309
      {
         return mgr == null || name == null ? null : mgr.var_2498.method_4935(name) as class_309;
      }
   }
}
