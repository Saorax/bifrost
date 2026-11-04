package bh.platform
{
   import bh.platform.net.PrivateServer;
   import flash.filesystem.File;
   import flash.filesystem.FileMode;
   import flash.filesystem.FileStream;
   import flash.system.Capabilities;
   import flash.utils.ByteArray;

   public final class BugReport
   {
      public static const SEND:int = 11094;
      public static const ANSWER:int = 11095;
      public static const FORMAT:uint = 1;
      private static const MAX:int = 58000;
      private static const PER_FILE:int = 96 * 1024;
      private static const BUSY:String = "bugreport";

      public static var status:String = null;
      public static var onAnswer:Function = null;

      private static var registered:Boolean = false;

      public function BugReport()
      {
         super();
      }

      public static function send(note:String) : String
      {
         var core:Object = ScreenManager.owner;
         if(core == null || core.serverConnection == null || !core.serverConnection.isConnected())
         {
            return "not connected to a server";
         }
         if(!registered)
         {
            registered = true;
            Hooks.packetReceived.add(onPacket);
         }
         var report:Object = pack(note);
         if(report == null)
         {
            return "the logs couldn't be read";
         }
         var p:NetPacket = new NetPacket(SEND);
         p.writeUint(FORMAT);
         p.writeString(note);
         p.writeString(report.files);
         p.writeUint(report.size);
         p.method_4571(report.bytes);
         core.sendToServer(p);
         p.method_839();
         status = "Sending the bug report...";
         Busy.start(BUSY,"SENDING THE BUG REPORT",15000);
         Platform.log("bug report sent: " + report.bytes.length + " bytes packed, " + report.size + " of text (" +
            report.files + ")");
         return null;
      }

      public static function pack(note:String) : Object
      {
         try
         {
            var files:Array = logFiles();
            for(var cut:int = PER_FILE; cut >= 1024; cut >>= 1)
            {
               var text:String = header(note) + body(files,cut);
               var bytes:ByteArray = new ByteArray();
               bytes.writeUTFBytes(text);
               var size:uint = bytes.length;
               bytes.compress();
               if(bytes.length <= MAX)
               {
                  var names:Array = [];
                  for each(var f:Object in files)
                  {
                     names.push(f.name);
                  }
                  return {"bytes":bytes,"size":size,"files":names.join(",")};
               }
            }
         }
         catch(e:Error)
         {
            Platform.log("bug report: " + e.message);
         }
         return null;
      }

      private static function logFiles() : Array
      {
         var out:Array = [];
         var folder:File = Platform.dataFile("");
         addLogs(out,folder,"");
         var logs:File = Platform.dataFile("logs");
         if(logs.exists)
         {
            var sessions:Array = [];
            for each(var d:File in logs.getDirectoryListing())
            {
               if(d.isDirectory && /^\d{4}-\d\d-\d\d_\d\d-\d\d-\d\d/.test(d.name) && d.name != SessionLogs.current)
               {
                  sessions.push(d);
               }
            }
            sessions.sortOn("name");
            if(sessions.length > 0)
            {
               addLogs(out,File(sessions[sessions.length - 1]),"last/");
            }
         }
         return out;
      }

      private static function addLogs(out:Array, folder:File, prefix:String) : void
      {
         var found:Array = [];
         for each(var f:File in folder.getDirectoryListing())
         {
            if(!f.isDirectory && f.name.indexOf("bh-") == 0 && /\.txt$/i.test(f.name))
            {
               found.push(f);
            }
         }
         found.sortOn("name");
         for each(var g:File in found)
         {
            out.push({"name":prefix + g.name,"file":g});
         }
      }

      private static function header(note:String) : String
      {
         var screen:String = "";
         var runtime:String = "";
         try
         {
            screen = Capabilities.screenResolutionX + "x" + Capabilities.screenResolutionY;
            runtime = Capabilities.version + " " + Capabilities.playerType;
         }
         catch(e:Error)
         {
         }
         return "Bifrost bug report, " + new Date().toString() + "\nNote: " + (note || "(none)") + "\nOS: " + os() +
            "\nRuntime: " + runtime + "\nScreen: " + screen + "\nSession: " + SessionLogs.current + "\nServer: " +
            PrivateServer.host + ":" + PrivateServer.port + "\n";
      }

      private static function os() : String
      {
         try
         {
            return Capabilities.os;
         }
         catch(e:Error)
         {
         }
         return "?";
      }

      private static function body(files:Array, cut:int) : String
      {
         var out:String = "";
         var token:String = PrivateServer.token;
         for each(var f:Object in files)
         {
            var text:String = tail(File(f.file),cut);
            if(token != null && token.length >= 8)
            {
               text = text.split(token).join("<token>");
            }
            out += "\n===== " + f.name + " =====\n" + text;
         }
         return out;
      }

      private static function tail(file:File, cut:int) : String
      {
         var stream:FileStream = new FileStream();
         try
         {
            stream.open(file,FileMode.READ);
            var size:Number = stream.bytesAvailable;
            if(size > cut)
            {
               stream.position = size - cut;
            }
            var text:String = stream.readUTFBytes(stream.bytesAvailable);
            return (size > cut ? "[... the first " + int(size - cut) + " bytes left out]\n" : "") + text;
         }
         catch(e:Error)
         {
            return "[unreadable: " + e.message + "]\n";
         }
         finally
         {
            stream.close();
         }
         return "";
      }

      private static function onPacket(packet:Object) : Boolean
      {
         if(packet == null || packet.type != ANSWER)
         {
            return false;
         }
         Busy.done(BUSY);
         try
         {
            var id:uint = packet.readUint();
            var message:String = packet.readString();
            status = message || (id > 0 ? "Bug report #" + id + " received." : "Not sent.");
         }
         catch(e:Error)
         {
            status = "The server's answer couldn't be read.";
         }
         Platform.log("bug report: " + status);
         if(onAnswer != null)
         {
            onAnswer(status);
         }
         return true;
      }
   }
}
