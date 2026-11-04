package bh.platform
{
   import flash.filesystem.File;
   import flash.filesystem.FileMode;
   import flash.filesystem.FileStream;

   public final class ReplayStore
   {
      public static const NOTES:String = "replay-notes.json";
      public static const STATS:String = "replay-stats";
      public static const TAGS:Array = [];

      private static var notes:Object = null;
      private static var pendingStats:Object = null;
      private static var pendingName:String = null;

      public function ReplayStore()
      {
      }

      public static function note(name:String) : String
      {
         var n:Object = notesOf(name);
         return n != null && n.note ? String(n.note) : "";
      }

      public static function tags(name:String) : Array
      {
         var n:Object = notesOf(name);
         return n != null && n.tags is Array ? (n.tags as Array).concat() : [];
      }

      public static function setNote(name:String, text:String) : void
      {
         var n:Object = notesFor(name);
         n.note = text.replace(/^\s+|\s+$/g,"");
         tidy(name);
      }

      public static function toggleTag(name:String, tag:String) : Boolean
      {
         var n:Object = notesFor(name);
         var list:Array = n.tags is Array ? n.tags : [];
         var at:int = list.indexOf(tag);
         if(at >= 0)
         {
            list.splice(at,1);
         }
         else
         {
            list.push(tag);
         }
         n.tags = list;
         tidy(name);
         return at < 0;
      }

      public static function allTags() : Array
      {
         load();
         var set:Object = {};
         var out:Array = TAGS.concat();
         for each(var t:String in TAGS)
         {
            set[t] = true;
         }
         for each(var n:Object in notes)
         {
            for each(t in (n.tags as Array))
            {
               if(!set[t])
               {
                  set[t] = true;
                  out.push(t);
               }
            }
         }
         return out;
      }

      public static function hasStats(name:String) : Boolean
      {
         try
         {
            return statsFile(name).exists;
         }
         catch(e:Error)
         {
         }
         return false;
      }

      public static function stats(name:String) : Object
      {
         try
         {
            var f:File = statsFile(name);
            if(!f.exists)
            {
               return null;
            }
            var s:FileStream = new FileStream();
            s.open(f,FileMode.READ);
            var text:String = s.readUTFBytes(s.bytesAvailable);
            s.close();
            return JSON.parse(text);
         }
         catch(e:Error)
         {
            Platform.log("replays: stats of " + name + " not read: " + e.message);
         }
         return null;
      }

      public static function saveStats(name:String, data:Object, how:String) : Boolean
      {
         if(name == null || data == null)
         {
            return false;
         }
         try
         {
            var f:File = statsFile(name);
            f.parent.createDirectory();
            data.saved = how;
            var s:FileStream = new FileStream();
            s.open(f,FileMode.WRITE);
            s.writeUTFBytes(JSON.stringify(data));
            s.close();
            Platform.log("replays: match stats of " + name + " saved (" + how + ")");
            return true;
         }
         catch(e:Error)
         {
            Platform.log("replays: match stats of " + name + " not saved: " + e.message);
         }
         return false;
      }

      public static function forget(name:String) : void
      {
         try
         {
            var f:File = statsFile(name);
            if(f.exists)
            {
               f.deleteFile();
            }
         }
         catch(e:Error)
         {
         }
         load();
         if(notes[name] != null)
         {
            delete notes[name];
            save();
         }
      }

      public static function matchStarted() : void
      {
         pendingStats = null;
         pendingName = null;
      }

      public static function matchStats(data:Object) : void
      {
         if(pendingName != null)
         {
            saveStats(pendingName,data,"played");
            pendingName = null;
            return;
         }
         pendingStats = data;
      }

      public static function matchSaved(name:String) : void
      {
         if(pendingStats != null)
         {
            saveStats(name,pendingStats,"played");
            pendingStats = null;
            return;
         }
         pendingName = name;
      }

      private static function statsFile(name:String) : File
      {
         return Platform.dataFile(STATS + "/" + name.replace(/\.replay$/,"").replace(/[\\\/:*?"<>|]/g,"_") + ".json");
      }

      private static function notesOf(name:String) : Object
      {
         load();
         return notes[name];
      }

      private static function notesFor(name:String) : Object
      {
         load();
         if(notes[name] == null)
         {
            notes[name] = {"note":"","tags":[]};
         }
         return notes[name];
      }

      private static function tidy(name:String) : void
      {
         var n:Object = notes[name];
         if(n != null && !n.note && (!(n.tags is Array) || n.tags.length == 0))
         {
            delete notes[name];
         }
         save();
      }

      private static function load() : void
      {
         if(notes != null)
         {
            return;
         }
         notes = {};
         try
         {
            var f:File = Platform.dataFile(NOTES);
            if(f.exists)
            {
               var s:FileStream = new FileStream();
               s.open(f,FileMode.READ);
               var kept:Object = JSON.parse(s.readUTFBytes(s.bytesAvailable));
               s.close();
               if(kept != null && kept.replays != null)
               {
                  notes = kept.replays;
               }
            }
         }
         catch(e:Error)
         {
            notes = {};
         }
      }

      private static function save() : void
      {
         try
         {
            var s:FileStream = new FileStream();
            s.open(Platform.dataFile(NOTES),FileMode.WRITE);
            s.writeUTFBytes(JSON.stringify({"version":1,"replays":notes}));
            s.close();
         }
         catch(e:Error)
         {
            Platform.log("replays: notes not saved: " + e.message);
         }
      }
   }
}
