package bh.platform
{
   import bh.platform.net.PrivateServer;
   import flash.filesystem.File;

   public final class ReplayKeep
   {
      public static const FAVORITES:String = "Favorites";
      public static const OLDER:String = "Older";
      public static const KEEP_CHOICES:Array = [0,50,100,200,500,1000];
      public static const MOVE_AT_ONCE:int = 200;
      private static const OLD_BEST:String = "Best";

      private static var lastSaved:String = null;

      public function ReplayKeep()
      {
      }

      public static function get keepRecent() : int
      {
         return int(ModSettings.value("replayKeepRecent") || 0);
      }

      public static function set keepRecent(n:int) : void
      {
         ModSettings.setValue("replayKeepRecent",n);
      }

      public static function keepLabel(n:int) : String
      {
         return n <= 0 ? "All" : n + " newest";
      }

      public static function stepKeep(dir:int) : void
      {
         var at:int = KEEP_CHOICES.indexOf(keepRecent);
         at = ((at < 0 ? 0 : at) + (dir < 0 ? -1 : 1) + KEEP_CHOICES.length) % KEEP_CHOICES.length;
         keepRecent = int(KEEP_CHOICES[at]);
      }

      public static function folder() : File
      {
         return class_51.method_3608();
      }

      public static function prepare() : void
      {
         try
         {
            fromStorage();
            fromBest(folder().resolvePath(FAVORITES));
         }
         catch(e:Error)
         {
            PrivateServer.log("replays: Favorites not prepared: " + e.message);
         }
      }

      public static function favorites() : File
      {
         return folder().resolvePath(FAVORITES);
      }

      private static function fromStorage() : void
      {
         try
         {
            var old:File = File.applicationStorageDirectory.resolvePath("User").resolvePath("BrawlhallaReplays");
            var now:File = folder();
            if(!old.exists || !old.isDirectory || old.nativePath == now.nativePath)
            {
               return;
            }
            var moved:int = moveFolder(old,now);
            PrivateServer.log("replays: " + moved + " replays moved from " + old.nativePath + " to " + now.nativePath);
         }
         catch(e:Error)
         {
            PrivateServer.log("replays: the engine's old replay folder not moved: " + e.message);
         }
      }

      public static function moveFolder(old:File, now:File) : int
      {
         var moved:int = moveReplays(old,now);
         for each(var sub:File in old.getDirectoryListing())
         {
            if(sub.isDirectory)
            {
               moved += moveReplays(sub,now.resolvePath(sub.name == OLD_BEST ? FAVORITES : sub.name));
               if(sub.getDirectoryListing().length == 0)
               {
                  sub.deleteDirectory();
               }
            }
         }
         return moved;
      }

      private static function moveReplays(from:File, to:File) : int
      {
         var moved:int = 0;
         for each(var f:File in from.getDirectoryListing())
         {
            if(f.isDirectory || f.extension != "replay")
            {
               continue;
            }
            to.createDirectory();
            f.moveTo(freeName(to,f.name));
            moved++;
         }
         return moved;
      }

      private static function freeName(dir:File, name:String) : File
      {
         var target:File = dir.resolvePath(name);
         if(!target.exists)
         {
            return target;
         }
         var base:String = name.replace(/\.replay$/,"").replace(/ \(\d+\)$/,"");
         for(var i:int = 1; i < 100000; i++)
         {
            target = dir.resolvePath(base + " (" + i + ").replay");
            if(!target.exists)
            {
               return target;
            }
         }
         return dir.resolvePath(base + " (" + new Date().time + ").replay");
      }

      private static function fromBest(dir:File) : void
      {
         try
         {
            var old:File = folder().resolvePath(OLD_BEST);
            if(!old.exists || !old.isDirectory)
            {
               return;
            }
            if(!dir.exists)
            {
               old.moveTo(dir);
               PrivateServer.log("replays: the Best folder is now Favorites");
               return;
            }
            var moved:int = 0;
            for each(var f:File in old.getDirectoryListing())
            {
               var to:File = dir.resolvePath(f.name);
               if(!f.isDirectory && !to.exists)
               {
                  f.moveTo(to);
                  moved++;
               }
            }
            if(old.getDirectoryListing().length == 0)
            {
               old.deleteDirectory();
            }
            PrivateServer.log("replays: " + moved + " replays moved from Best to Favorites");
         }
         catch(e:Error)
         {
            PrivateServer.log("replays: Best not moved to Favorites: " + e.message);
         }
      }

      public static function inFavorites(f:File) : Boolean
      {
         return f.parent != null && f.parent.name == FAVORITES || favorites().resolvePath(f.name).exists;
      }

      public static function star(f:File, why:String) : Boolean
      {
         try
         {
            var dir:File = favorites();
            dir.createDirectory();
            var to:File = dir.resolvePath(f.name);
            if(to.exists)
            {
               return false;
            }
            f.copyTo(to);
            PrivateServer.log("replays: " + f.name + " added to Favorites (" + why + ")");
            return true;
         }
         catch(e:Error)
         {
            PrivateServer.log("replays: " + f.name + " not added to Favorites: " + e.message);
         }
         return false;
      }

      public static function unstar(f:File) : Boolean
      {
         try
         {
            var copy:File = favorites().resolvePath(f.name);
            if(!copy.exists)
            {
               return false;
            }
            copy.deleteFile();
            ReplayIndex.forget(copy);
            PrivateServer.log("replays: " + f.name + " taken out of Favorites");
            return true;
         }
         catch(e:Error)
         {
            PrivateServer.log("replays: " + f.name + " not taken out of Favorites: " + e.message);
         }
         return false;
      }

      public static function saved(recorder:Object) : void
      {
         try
         {
            var f:File = newest();
            if(f == null || f.nativePath == lastSaved || new Date().time - f.modificationDate.time > 60000)
            {
               return;
            }
            lastSaved = f.nativePath;
            ReplayStore.matchSaved(f.name);
            ReplaysWindow.matchSaved(f.name);
            PrivateServer.log("replays: saved " + f.name);
            trim();
         }
         catch(e:Error)
         {
            PrivateServer.log("replays: keeping failed: " + e.message);
         }
      }

      private static function newest() : File
      {
         var best:File = null;
         for each(var f:File in replays())
         {
            if(best == null || f.modificationDate.time > best.modificationDate.time)
            {
               best = f;
            }
         }
         return best;
      }

      private static function replays() : Array
      {
         var dir:File = folder();
         var out:Array = [];
         if(!dir.exists)
         {
            return out;
         }
         for each(var f:File in dir.getDirectoryListing())
         {
            if(!f.isDirectory && f.extension == "replay")
            {
               out.push(f);
            }
         }
         return out;
      }

      public static function trim() : int
      {
         var keep:int = keepRecent;
         if(keep <= 0)
         {
            return 0;
         }
         var all:Array = replays();
         if(all.length <= keep)
         {
            return 0;
         }
         all.sort(function(a:File, b:File):int
         {
            var d:Number = b.modificationDate.time - a.modificationDate.time;
            return d > 0 ? 1 : (d < 0 ? -1 : 0);
         });
         var dir:File = folder().resolvePath(OLDER);
         dir.createDirectory();
         var moved:int = 0;
         for(var i:int = keep; i < all.length && moved < MOVE_AT_ONCE; i++)
         {
            var f:File = all[i];
            var to:File = dir.resolvePath(f.name);
            for(var n:int = 1; to.exists; n++)
            {
               to = dir.resolvePath(f.name.replace(/\.replay$/,"") + " (old " + n + ").replay");
            }
            try
            {
               f.moveTo(to);
               moved++;
            }
            catch(e:Error)
            {
               PrivateServer.log("replays: " + f.name + " not moved to Older: " + e.message);
            }
         }
         PrivateServer.log("replays: KEEP RECENT " + keep + ": " + moved + " of " + (all.length - keep) +
            " older replays moved to Older");
         return moved;
      }
   }
}
