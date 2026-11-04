package bh.platform
{
   import flash.events.UncaughtErrorEvent;
   import flash.filesystem.File;
   import flash.filesystem.FileMode;
   import flash.filesystem.FileStream;

   public final class ErrorLog
   {
      public static const FILE:String = "bh-errors.txt";

      private static const MAX:int = 20;

      private static var count:int = 0;

      public function ErrorLog()
      {
      }

      public static function init() : void
      {
         try
         {
            var file:File = Platform.dataFile(FILE);
            if(file.exists)
            {
               file.deleteFile();
            }
         }
         catch(e:Error)
         {
         }
         Hooks.dataCheckFailed.add(function(message:String):void
         {
            if(++count <= MAX)
            {
               write("data check failed: " + message + "\r\n" + new Error("called from").getStackTrace());
            }
         });
         Hooks.gameError.add(function(error:Error):void
         {
            if(++count <= MAX)
            {
               write("error caught by the game's loop #" + count + ":\r\n" + (error.getStackTrace() || (error.name + ": " + error.message)));
            }
         });
         Hooks.gameCreated.add(function(main:Object):void
         {
            main.root.loaderInfo.uncaughtErrorEvents.addEventListener(UncaughtErrorEvent.UNCAUGHT_ERROR,onError,false,1000);
            write("error log attached");
         });
      }

      private static function onError(event:UncaughtErrorEvent) : void
      {
         if(++count > MAX)
         {
            return;
         }
         var error:* = event.error;
         var text:String;
         if(error is Error)
         {
            text = Error(error).getStackTrace() || (Error(error).name + ": " + Error(error).message);
         }
         else
         {
            text = "thrown value (not an Error): " + String(error);
         }
         write("uncaught error #" + count + ":\r\n" + text);
      }

      public static function write(line:String) : void
      {
         try
         {
            var stream:FileStream = new FileStream();
            stream.open(Platform.dataFile(FILE),FileMode.APPEND);
            stream.writeUTFBytes(new Date().toUTCString() + " " + line + "\r\n");
            stream.close();
         }
         catch(e:Error)
         {
         }
      }
   }
}
