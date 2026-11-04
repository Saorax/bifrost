package bh.platform
{
   import flash.filesystem.File;
   import flash.filesystem.FileMode;
   import flash.filesystem.FileStream;
   import flash.net.SharedObject;
   import flash.utils.ByteArray;

   public final class CloudSave
   {
      public static const UPLOAD:int = 11022;
      public static const HELD:int = 11023;
      public static const DELETE:int = 11024;
      public static const FORMAT:uint = 1;
      public static const SETTINGS:Array = ["legendSetups","keyboardProfile","controllerProfiles","profilePicks"];
      public static const STATE:String = "Bifrost/cloud-save.json";
      public static const PENDING:String = "Bifrost/cloud-save-pending.bin";
      public static const OFF:String = "cloudSaveOff";
      public static const LOCAL:Array = ["bhAbsolutePlayTime","bhDisabledControllers"];
      private static const CHECK_EVERY:int = 540;
      private static const MAX:int = 60000;

      public static var held:Object = null;
      public static var waitingRestart:Boolean = false;

      private static var compared:Boolean = false;
      private static var appliedAtStart:Boolean = false;
      private static var lastSent:ByteArray = null;
      private static var tick:int = 0;

      public function CloudSave()
      {
      }

      public static const ENABLED:Boolean = false;

      public static function init() : void
      {
         if(!ENABLED)
         {
            return;
         }
         Hooks.packetReceived.add(onPacket);
         Hooks.frameStarting.add(onFrame);
      }

      public static function applyPending() : void
      {
         try
         {
            var file:File = File.applicationStorageDirectory.resolvePath(PENDING);
            if(!file.exists)
            {
               return;
            }
            if(!ENABLED)
            {
               file.deleteFile();
               Platform.log("server save: off for now, the copy waiting from before dropped");
               return;
            }
            var bytes:ByteArray = readFile(file);
            file.deleteFile();
            var when:uint = bytes.readUnsignedInt();
            var rest:ByteArray = new ByteArray();
            bytes.readBytes(rest);
            rest.uncompress();
            var save:Object = rest.readObject();
            var stores:Array = [];
            for(var name:String in save.stores)
            {
               var so:SharedObject = SharedObject.getLocal(SaveCopy.PREFIX + name,"/");
               var olds:Array = [];
               for(var old:String in so.data)
               {
                  if(LOCAL.indexOf(old) < 0)
                  {
                     olds.push(old);
                  }
               }
               for each(old in olds)
               {
                  delete so.data[old];
               }
               for(var k:String in save.stores[name])
               {
                  if(LOCAL.indexOf(k) >= 0)
                  {
                     continue;
                  }
                  so.data[k] = save.stores[name][k];
               }
               so.flush();
               stores.push(name);
            }
            for(k in save.settings)
            {
               ModSettings.setValue(k,save.settings[k]);
            }
            writeState(when);
            appliedAtStart = true;
            Platform.log("server save loaded: " + stores.join(", ") + " and " + SETTINGS.join(", "));
         }
         catch(e:Error)
         {
            Platform.log("server save not loaded: " + e.message);
         }
      }

      public static function pack() : Object
      {
         var stores:Object = {};
         var names:Array = [];
         for each(var name:String in SaveCopy.STORES)
         {
            var so:SharedObject = SharedObject.getLocal(SaveCopy.PREFIX + name,"/");
            var any:Boolean = false;
            var kept:Object = {};
            for(var k:String in so.data)
            {
               if(LOCAL.indexOf(k) < 0)
               {
                  kept[k] = so.data[k];
                  any = true;
               }
            }
            if(any)
            {
               stores[name] = kept;
               names.push(name);
            }
         }
         var settings:Object = {};
         for each(k in SETTINGS)
         {
            if(ModSettings.value(k) != null)
            {
               settings[k] = ModSettings.value(k);
            }
         }
         var bytes:ByteArray = new ByteArray();
         bytes.writeObject({"format":FORMAT,"stores":stores,"settings":settings});
         return {"bytes":bytes,"what":names.concat(["settings"]).join(",")};
      }

      private static function onPacket(packet:Object) : Boolean
      {
         if(packet == null || packet.type != HELD)
         {
            return false;
         }
         try
         {
            if(!packet.method_5885())
            {
               held = {};
            }
            else
            {
               held = {"when":packet.readUint(),"size":packet.readUint(),"saved":packet.readUint(),"what":packet.readString()};
               if(packet.method_5885())
               {
                  var data:ByteArray = new ByteArray();
                  packet.method_606(data);
                  compare(data);
                  return true;
               }
            }
            if(held.when == null && !compared)
            {
               compare(null);
            }
         }
         catch(e:Error)
         {
            Platform.log("server save: could not read 11023: " + e.message);
         }
         return true;
      }

      private static function compare(data:ByteArray) : void
      {
         compared = true;
         lastSent = null;
         var local:uint = readState();
         var mine:ByteArray = pack().bytes;
         if(data != null)
         {
            var theirs:ByteArray = new ByteArray();
            theirs.writeBytes(data);
            theirs.uncompress();
            if(same(theirs,mine))
            {
               lastSent = mine;
               return;
            }
            if(appliedAtStart && uint(held.when) == local)
            {
               Platform.log("server save: loaded at start, the game's own save of it goes up");
               upload(mine,now());
               return;
            }
            if(uint(held.when) > local)
            {
               var pending:ByteArray = new ByteArray();
               pending.writeUnsignedInt(uint(held.when));
               pending.writeBytes(data);
               writeFile(File.applicationStorageDirectory.resolvePath(PENDING),pending);
               waitingRestart = true;
               Platform.log("server save is newer (" + held.when + " > " + local + "): loaded at the next start");
               Modal.show("Your save on the server","Your settings, key binds and legend setups from your other PC are " +
                  "newer than this PC's. Restart the game to load them.");
               return;
            }
         }
         upload(mine,local > 0 ? local : now());
      }

      private static function onFrame() : void
      {
         if(++tick % CHECK_EVERY != 0 || !compared || waitingRestart || ModSettings.flag(OFF))
         {
            return;
         }
         try
         {
            var mine:ByteArray = pack().bytes;
            if(lastSent == null || !same(mine,lastSent))
            {
               upload(mine,now());
            }
         }
         catch(e:Error)
         {
            ErrorLog.write("server save: " + e);
         }
      }

      private static function upload(raw:ByteArray, when:uint) : void
      {
         var core:Object = ScreenManager.owner;
         if(ModSettings.flag(OFF) || core == null || core.serverConnection == null || !core.serverConnection.isConnected())
         {
            return;
         }
         var packed:Object = pack();
         var blob:ByteArray = new ByteArray();
         blob.writeBytes(raw);
         blob.compress();
         if(blob.length > MAX)
         {
            Platform.log("server save not sent: " + blob.length + " bytes packed, more than " + MAX);
            lastSent = raw;
            return;
         }
         var p:NetPacket = new NetPacket(UPLOAD);
         p.writeUint(FORMAT);
         p.writeUint(when);
         p.writeString(packed.what);
         p.method_4571(blob);
         core.sendToServer(p);
         p.method_839();
         lastSent = raw;
         writeState(when);
         Platform.log("server save sent: " + blob.length + " bytes (" + packed.what + ")");
      }

      public static function deleteFromServer() : Boolean
      {
         var core:Object = ScreenManager.owner;
         if(core == null || core.serverConnection == null || !core.serverConnection.isConnected())
         {
            return false;
         }
         ModSettings.setFlag(OFF,true);
         var p:NetPacket = new NetPacket(DELETE);
         core.sendToServer(p);
         p.method_839();
         Platform.log("server save: delete asked; not sent again until KEEP ON SERVER");
         return true;
      }

      public static function keep() : void
      {
         ModSettings.setFlag(OFF,false);
         lastSent = null;
      }

      public static function describe() : String
      {
         if(waitingRestart)
         {
            return "Newer save from the server: restart the game to load it";
         }
         if(held == null)
         {
            return "Sign in with Discord to keep your save on the server";
         }
         if(held.when == null)
         {
            return ModSettings.flag(OFF) ? "Nothing on the server (not sending)" : "Nothing on the server yet";
         }
         var d:Date = new Date(Number(held.saved) * 1000);
         return Math.max(1,Math.round(Number(held.size) / 1024)) + " KB, saved " + d.fullYear + "-" + two(d.month + 1) +
            "-" + two(d.date) + " " + two(d.hours) + ":" + two(d.minutes) + (ModSettings.flag(OFF) ? " (not sending)" : "");
      }

      private static function two(n:int) : String
      {
         return n < 10 ? "0" + n : String(n);
      }

      private static function same(a:ByteArray, b:ByteArray) : Boolean
      {
         if(a.length != b.length)
         {
            return false;
         }
         for(var i:uint = 0; i < a.length; i++)
         {
            if(a[i] != b[i])
            {
               return false;
            }
         }
         return true;
      }

      private static function now() : uint
      {
         return uint(new Date().time / 1000);
      }

      private static function readState() : uint
      {
         try
         {
            var file:File = File.applicationStorageDirectory.resolvePath(STATE);
            if(file.exists)
            {
               var bytes:ByteArray = readFile(file);
               return uint(JSON.parse(bytes.readUTFBytes(bytes.length)).when);
            }
         }
         catch(e:Error)
         {
         }
         return 0;
      }

      private static function writeState(when:uint) : void
      {
         var bytes:ByteArray = new ByteArray();
         bytes.writeUTFBytes(JSON.stringify({"when":when,"note":"The time of this PC's latest save change the server knows."}));
         writeFile(File.applicationStorageDirectory.resolvePath(STATE),bytes);
      }

      private static function readFile(file:File) : ByteArray
      {
         var s:FileStream = new FileStream();
         s.open(file,FileMode.READ);
         var bytes:ByteArray = new ByteArray();
         s.readBytes(bytes);
         s.close();
         return bytes;
      }

      private static function writeFile(file:File, bytes:ByteArray) : void
      {
         try
         {
            file.parent.createDirectory();
            var s:FileStream = new FileStream();
            s.open(file,FileMode.WRITE);
            s.writeBytes(bytes);
            s.close();
         }
         catch(e:Error)
         {
            Platform.log("server save: " + file.name + " not written: " + e.message);
         }
      }
   }
}
