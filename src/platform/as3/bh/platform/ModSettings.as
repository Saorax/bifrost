package bh.platform
{
   import flash.filesystem.File;
   import flash.filesystem.FileMode;
   import flash.filesystem.FileStream;

   public final class ModSettings
   {
      public static const FILE:String = "bh-mod-settings.json";

      private static var data:Object = null;

      public function ModSettings()
      {
      }

      private static function load() : Object
      {
         if(data != null)
         {
            return data;
         }
         data = {};
         try
         {
            var file:File = Platform.dataFile(FILE);
            if(file.exists)
            {
               var stream:FileStream = new FileStream();
               stream.open(file,FileMode.READ);
               var text:String = stream.readUTFBytes(stream.bytesAvailable);
               stream.close();
               var parsed:* = JSON.parse(text);
               if(parsed != null && typeof parsed == "object" && !(parsed is Array))
               {
                  data = parsed;
               }
            }
         }
         catch(e:Error)
         {
            Platform.log("mod settings unreadable, starting empty: " + e.message);
         }
         for each(var key:String in ["disabled","mapArt"])
         {
            if(data[key] == null || typeof data[key] != "object" || data[key] is Array)
            {
               data[key] = {};
            }
         }
         return data;
      }

      private static function save() : void
      {
         try
         {
            var stream:FileStream = new FileStream();
            stream.open(Platform.dataFile(FILE),FileMode.WRITE);
            stream.writeUTFBytes(JSON.stringify(load(),null,2));
            stream.close();
         }
         catch(e:Error)
         {
            Platform.log("mod settings not saved: " + e.message);
         }
      }

      public static function isDisabled(id:String) : Boolean
      {
         return load().disabled[id] === true;
      }

      public static function setDisabled(id:String, off:Boolean) : void
      {
         if(off)
         {
            load().disabled[id] = true;
         }
         else
         {
            delete load().disabled[id];
         }
         save();
      }

      public static function mapArt(level:String) : String
      {
         var value:* = load().mapArt[level];
         return value is String ? value : null;
      }

      public static function setMapArt(level:String, value:String) : void
      {
         load().mapArt[level] = value;
         save();
      }

      public static function value(name:String) : *
      {
         return load()[name];
      }

      public static function setValue(name:String, v:*) : void
      {
         load()[name] = v;
         save();
      }

      public static function remove(name:String) : void
      {
         delete load()[name];
         save();
      }

      public static function flag(name:String, unset:Boolean = false) : Boolean
      {
         var value:* = load()[name];
         return value is Boolean ? value : unset;
      }

      public static function setFlag(name:String, on:Boolean) : void
      {
         load()[name] = on;
         save();
      }
   }
}
