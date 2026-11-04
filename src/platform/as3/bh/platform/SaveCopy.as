package bh.platform
{
   import flash.filesystem.File;
   import flash.filesystem.FileMode;
   import flash.filesystem.FileStream;
   import flash.net.SharedObject;
   import flash.utils.ByteArray;

   public final class SaveCopy
   {
      public static const STORES:Array = ["sbSavedGameData","sbSavedGameDataP","sbSavedGameDataC","bhProfileData",
         "bhProfileDataP","bhProfileDataC","bhKeybinds","sbSavedData"];

      public static const PREFIX:String = "bifrost_";

      public static const MARKER:String = "Bifrost/live-copy.json";

      public function SaveCopy()
      {
      }

      public static function run() : void
      {
         try
         {
            var marker:File = File.applicationStorageDirectory.resolvePath(MARKER);
            if(marker.exists)
            {
               return;
            }
            var copied:Array = [];
            for each(var name:String in STORES)
            {
               var n:int = copy(name);
               if(n > 0)
               {
                  copied.push(name + " (" + n + " values)");
               }
            }
            marker.parent.createDirectory();
            var s:FileStream = new FileStream();
            s.open(marker,FileMode.WRITE);
            s.writeUTFBytes(JSON.stringify({"copied":copied,"at":new Date().toUTCString(),
               "note":"The live game's saves were copied into the rebuilt game's once. Delete this file to copy them again."},null,2));
            s.close();
            Platform.log("copied the live game's saves: " + (copied.length ? copied.join(", ") : "none found"));
         }
         catch(e:Error)
         {
            Platform.log("could not copy the live game's saves: " + e.message);
         }
      }

      public static function requestImport() : Boolean
      {
         try
         {
            var marker:File = File.applicationStorageDirectory.resolvePath(MARKER);
            if(marker.exists)
            {
               marker.deleteFile();
            }
            Platform.log("the live game's saves will be copied again at the next start (Options > MORE)");
            return true;
         }
         catch(e:Error)
         {
            Platform.log("could not set up the save import: " + e.message);
         }
         return false;
      }

      public static function importPending() : Boolean
      {
         try
         {
            return !File.applicationStorageDirectory.resolvePath(MARKER).exists;
         }
         catch(e:Error)
         {
         }
         return false;
      }

      private static function copy(name:String) : int
      {
         var live:SharedObject = SharedObject.getLocal(name,"/");
         var keys:Array = [];
         for(var k:String in live.data)
         {
            keys.push(k);
         }
         if(keys.length == 0)
         {
            return 0;
         }
         var mine:SharedObject = SharedObject.getLocal(PREFIX + name,"/");
         var n:int = 0;
         for each(k in keys)
         {
            var bytes:ByteArray = new ByteArray();
            bytes.writeObject(live.data[k]);
            bytes.position = 0;
            mine.data[k] = bytes.readObject();
            n++;
         }
         mine.flush();
         return n;
      }
   }
}
