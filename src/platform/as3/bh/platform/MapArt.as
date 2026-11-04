package bh.platform
{
   import flash.filesystem.File;

   public final class MapArt
   {
      public static var packs:Array = [];

      private static var current:String = null;

      private static var chosen:Object = null;

      private static var picks:Object = {};

      private static var mass:Boolean = false;

      public function MapArt()
      {
      }

      public static function add(mod:Object, report:Array) : void
      {
         var files:Object = {};
         var count:int = 0;
         for each(var path:String in mod.mapArt.files)
         {
            var file:File = (mod.dir as File).resolvePath(path);
            if(!file.exists)
            {
               report.push("map art skipped " + mod.id + ": " + path + " is missing");
               continue;
            }
            files[path] = file;
            count++;
         }
         var maps:Object = {};
         var mapCount:int = 0;
         for(var level:String in mod.mapArt.maps)
         {
            maps[level] = String(mod.mapArt.maps[level]);
            mapCount++;
         }
         var variants:Object = {};
         for(var varied:String in mod.mapArt.variants)
         {
            variants[varied] = [];
            for each(var local:String in mod.mapArt.variants[varied] as Array)
            {
               var variant:File = (mod.dir as File).resolvePath(local);
               if(local.indexOf("..") < 0 && variant.exists)
               {
                  variants[varied].push(variant);
               }
            }
         }
         packs.push({"id":mod.id,"name":mod.name,"files":files,"maps":maps,"variants":variants,
                     "types":mod.mapArt.mapTypes != null ? mod.mapArt.mapTypes : {},
                     "thumbnails":mod.mapArt.thumbnails != null ? mod.mapArt.thumbnails : {}});
         report.push("map art " + mod.id + ": " + count + " files for " + mapCount + " maps");
      }

      public static function maps() : Array
      {
         var byLevel:Object = {};
         var list:Array = [];
         for each(var pack:Object in on())
         {
            for(var level:String in pack.maps)
            {
               if(byLevel[level] == null)
               {
                  byLevel[level] = {"level":level,"name":pack.maps[level],"packs":[],"types":[]};
                  list.push(byLevel[level]);
               }
               byLevel[level].packs.push(pack);
               for each(var kind:String in pack.types[level] as Array)
               {
                  if(byLevel[level].types.indexOf(kind) < 0)
                  {
                     byLevel[level].types.push(kind);
                  }
               }
            }
         }
         list.sortOn(["name","level"],Array.CASEINSENSITIVE);
         return list;
      }

      public static function on() : Array
      {
         var list:Array = [];
         for each(var pack:Object in packs)
         {
            if(!ModSettings.isDisabled(pack.id))
            {
               list.push(pack);
            }
         }
         return list;
      }

      private static function packsFor(level:String) : Array
      {
         var list:Array = [];
         for each(var pack:Object in on())
         {
            if(pack.maps[level] != null)
            {
               list.push(pack);
            }
         }
         return list;
      }

      public static function choice(level:String) : String
      {
         var list:Array = packsFor(level);
         var value:String = ModSettings.mapArt(level);
         if(value == "default" || value == "shuffle" || value == "mass")
         {
            return value;
         }
         for each(var pack:Object in list)
         {
            if(pack.id == value)
            {
               return value;
            }
         }
         return list.length > 0 ? list[0].id : "default";
      }

      public static function choices(level:String) : Array
      {
         var list:Array = ["default"];
         for each(var pack:Object in packsFor(level))
         {
            list.push(pack.id);
         }
         list.push("shuffle");
         list.push("mass");
         return list;
      }

      public static function choiceName(value:String) : String
      {
         if(value == "default")
         {
            return "Default";
         }
         if(value == "shuffle")
         {
            return "Shuffle";
         }
         if(value == "mass")
         {
            return "Mass random";
         }
         for each(var pack:Object in packs)
         {
            if(pack.id == value)
            {
               return pack.name;
            }
         }
         return value;
      }

      public static function gameThumbnail(level:String) : File
      {
         try
         {
            var type:LevelType = LevelType.method_2845(level);
            if(type != null && type.var_14988 != null)
            {
               var file:File = File.applicationDirectory.resolvePath(type.var_14988);
               return file.exists ? file : null;
            }
         }
         catch(e:Error)
         {
         }
         return null;
      }

      public static function choiceThumbnail(level:String, value:String) : File
      {
         var game:File = gameThumbnail(level);
         for each(var pack:Object in packs)
         {
            if(pack.id != value)
            {
               continue;
            }
            for(var path:String in pack.thumbnails)
            {
               if((pack.thumbnails[path] as Array).indexOf(level) >= 0 && pack.files[path] != null)
               {
                  return pack.files[path];
               }
            }
            if(game != null && pack.files["images/thumbnails/" + game.name] != null)
            {
               return pack.files["images/thumbnails/" + game.name];
            }
         }
         return game;
      }

      public static function pictureFor(level:String, path:String) : File
      {
         if(packs.length == 0 || level == null)
         {
            return null;
         }
         if(level == current && chosen != null)
         {
            return chosen.files[path] as File;
         }
         var value:String = choice(level);
         for each(var pack:Object in packsFor(level))
         {
            if(pack.id == value && pack.files[path] != null)
            {
               return pack.files[path] as File;
            }
         }
         return null;
      }

      public static function levelLoading(desc:Xml) : void
      {
         current = desc != null && desc.exists("LevelName") ? desc.method_4935("LevelName") : null;
         chosen = null;
         mass = false;
         picks = {};
         if(current == null || packs.length == 0)
         {
            return;
         }
         var list:Array = packsFor(current);
         var value:String = choice(current);
         mass = value == "mass";
         if(value == "shuffle")
         {
            var at:int = int(Math.random() * (list.length + 1));
            chosen = at < list.length ? list[at] : null;
         }
         else
         {
            for each(var pack:Object in list)
            {
               if(pack.id == value)
               {
                  chosen = pack;
               }
            }
         }
         if(list.length > 0)
         {
            Platform.log("map art for " + current + ": " + (mass ? "mass randomness" : (chosen != null ? chosen.id :
               "the game's")) + " (" + value + ")");
         }
      }

      public static function resolve(value:*, fileName:String, fileType:String) : *
      {
         if(packs.length == 0 || fileName == null)
         {
            return null;
         }
         if(fileName.indexOf("images/thumbnails/") == 0)
         {
            return thumbnail(fileName);
         }
         if(fileName.indexOf("mapArt/") != 0 || current == null)
         {
            return null;
         }
         if(mass)
         {
            if(picks[fileName] === undefined)
            {
               var options:Array = [null];
               for each(var pack:Object in on())
               {
                  if(pack.files[fileName] != null)
                  {
                     options.push(pack.files[fileName]);
                  }
                  for each(var other:File in pack.variants[fileName] as Array)
                  {
                     options.push(other);
                  }
               }
               picks[fileName] = options[int(Math.random() * options.length)];
            }
            return picks[fileName];
         }
         return chosen != null ? chosen.files[fileName] : null;
      }

      private static function thumbnail(fileName:String) : *
      {
         for each(var pack:Object in on())
         {
            if(pack.files[fileName] == null)
            {
               continue;
            }
            for each(var level:String in pack.thumbnails[fileName] as Array)
            {
               if(choice(level) == pack.id)
               {
                  return pack.files[fileName];
               }
            }
         }
         return null;
      }
   }
}
