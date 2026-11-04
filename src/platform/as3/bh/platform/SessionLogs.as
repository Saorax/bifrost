package bh.platform
{
   import flash.filesystem.File;
   import flash.filesystem.FileMode;
   import flash.filesystem.FileStream;

   public final class SessionLogs
   {
      public static const MARKER:String = "bh-session.txt";

      public static const KEEP:int = 40;

      public static var current:String = null;

      public static function rotate() : void
      {
         try
         {
            var folder:File = Platform.dataFile("");
            var logs:File = Platform.dataFile("logs");
            var files:Array = [];
            var newest:Date = null;
            for each(var f:File in folder.getDirectoryListing())
            {
               if(!f.isDirectory && f.name.indexOf("bh-") == 0 && /\.txt$/i.test(f.name))
               {
                  files.push(f);
                  if(newest == null || f.modificationDate.time > newest.time)
                  {
                     newest = f.modificationDate;
                  }
               }
            }
            if(files.length > 0)
            {
               var name:String = readMarker();
               if(name == null)
               {
                  name = stamp(newest) + "_ended";
               }
               var target:File = logs.resolvePath(name);
               for(var n:int = 2; target.exists; n++)
               {
                  target = logs.resolvePath(name + "-" + n);
               }
               target.createDirectory();
               for each(var log:File in files)
               {
                  try
                  {
                     log.moveTo(target.resolvePath(log.name),false);
                  }
                  catch(moveError:Error)
                  {
                  }
               }
            }
            prune(logs);
            current = stamp(new Date());
            var stream:FileStream = new FileStream();
            stream.open(Platform.dataFile(MARKER),FileMode.WRITE);
            stream.writeUTFBytes(current);
            stream.close();
         }
         catch(e:Error)
         {
         }
      }

      private static function readMarker() : String
      {
         var file:File = Platform.dataFile(MARKER);
         if(!file.exists)
         {
            return null;
         }
         var stream:FileStream = new FileStream();
         stream.open(file,FileMode.READ);
         var text:String = stream.readUTFBytes(stream.bytesAvailable);
         stream.close();
         text = text.replace(/\s+/g,"");
         return /^[0-9_-]+$/.test(text) ? text : null;
      }

      private static function prune(logs:File) : void
      {
         if(!logs.exists)
         {
            return;
         }
         var sessions:Array = [];
         for each(var d:File in logs.getDirectoryListing())
         {
            if(d.isDirectory && /^\d{4}-\d\d-\d\d_\d\d-\d\d-\d\d/.test(d.name))
            {
               sessions.push(d);
            }
         }
         sessions.sortOn("name");
         while(sessions.length > KEEP)
         {
            try
            {
               File(sessions.shift()).deleteDirectory(true);
            }
            catch(e:Error)
            {
            }
         }
      }

      private static function stamp(d:Date) : String
      {
         return d.fullYear + "-" + two(d.month + 1) + "-" + two(d.date) + "_" + two(d.hours) + "-" + two(d.minutes) + "-" +
            two(d.seconds);
      }

      private static function two(n:int) : String
      {
         return n < 10 ? "0" + n : String(n);
      }
   }
}
