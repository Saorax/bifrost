package bh.platform
{
   import flash.filesystem.File;

   public final class MenuThemes
   {
      public static const KEY:String = "menuTheme";
      public static const SERVER_DEFAULT:String = "Server default";

      private static var server:uint = 0;
      private static var manager:ClientManager = null;
      private static var artFound:Object = {};

      public function MenuThemes()
      {
      }

      public static function pick(id:uint) : uint
      {
         server = id;
         var t:class_70 = chosen();
         return t != null ? t.var_11563 : id;
      }

      public static function started(cm:ClientManager) : void
      {
         manager = cm;
         if(chosen() != null)
         {
            apply();
         }
      }

      public static function get serverTheme() : uint
      {
         return server;
      }

      public static function choices() : Array
      {
         var out:Array = [];
         try
         {
            for each(var t:class_70 in class_70.var_11178)
            {
               if(usable(t))
               {
                  out.push(t);
               }
            }
         }
         catch(e:Error)
         {
            Platform.log("menu themes: the theme table isn't readable: " + e.message);
         }
         return out;
      }

      public static function chosen() : class_70
      {
         var name:* = ModSettings.value(KEY);
         if(!(name is String) || name == "")
         {
            return null;
         }
         try
         {
            var t:class_70 = class_70.method_5573(name);
            return usable(t) ? t : null;
         }
         catch(e:Error)
         {
         }
         return null;
      }

      public static function label() : String
      {
         var t:class_70 = chosen();
         return t != null ? nameOf(t) : SERVER_DEFAULT;
      }

      public static function about() : String
      {
         var shown:String = "the game's default";
         try
         {
            var t:class_70 = class_70.method_1525(server);
            if(t != null)
            {
               shown = nameOf(t);
            }
         }
         catch(e:Error)
         {
         }
         return "The look of the main menu: its background, logo and buttons, the login bonus frame and the menu music. " +
            "Server default uses the server's theme (now " + shown + "). Only themes whose art is in your install are listed. " +
            "This only changes what you see.";
      }

      public static function step(dir:int) : void
      {
         var list:Array = choices();
         var at:int = list.indexOf(chosen()) + 1;
         var next:int = (at + dir + list.length + 1) % (list.length + 1);
         if(next == 0)
         {
            ModSettings.remove(KEY);
         }
         else
         {
            ModSettings.setValue(KEY,class_70(list[next - 1]).var_4015);
         }
         apply();
      }

      public static function nameOf(t:class_70) : String
      {
         return String(t.var_4015).replace(/([a-z])([A-Z0-9])/g,"$1 $2").replace(/([A-Z]+)([A-Z][a-z])/g,"$1 $2");
      }

      private static function usable(t:class_70) : Boolean
      {
         return t != null && t.var_11563 != 0 && t.var_3262 != "NotLive" && hasArt(t.var_7344);
      }

      private static function hasArt(file:String) : Boolean
      {
         if(file == null || file == "")
         {
            return false;
         }
         if(artFound[file] == null)
         {
            var found:Boolean = false;
            try
            {
               found = File.applicationDirectory.resolvePath(file + ".swf").exists;
            }
            catch(e:Error)
            {
            }
            artFound[file] = found;
         }
         return artFound[file] === true;
      }

      private static function apply() : void
      {
         var cm:ClientManager = manager != null ? manager : (ClientManager.owner != null ? ClientManager.owner.var_5488 : null);
         if(cm == null)
         {
            return;
         }
         try
         {
            cm.method_1737(server);
            Platform.log("menu theme: " + label() + " (server's " + server + ")");
         }
         catch(e:Error)
         {
            Platform.log("menu theme not applied: " + e.message);
         }
      }
   }
}
