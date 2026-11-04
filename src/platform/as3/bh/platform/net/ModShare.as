package bh.platform.net
{
   import bh.platform.Notices;
   import bh.platform.Busy;
   import bh.platform.ContentMods;
   import bh.platform.ErrorLog;
   import bh.platform.Hooks;
   import bh.platform.ModSettings;
   import bh.platform.Modal;
   import bh.platform.Platform;
   import flash.events.Event;
   import flash.events.HTTPStatusEvent;
   import flash.events.IOErrorEvent;
   import flash.events.ProgressEvent;
   import flash.events.SecurityErrorEvent;
   import flash.filesystem.File;
   import flash.filesystem.FileMode;
   import flash.filesystem.FileStream;
   import flash.net.URLLoader;
   import flash.net.URLLoaderDataFormat;
   import flash.net.URLRequest;
   import flash.net.URLRequestMethod;
   import flash.utils.ByteArray;
   import flash.utils.getTimer;
   import flash.utils.setTimeout;

   public final class ModShare
   {
      public static const UPLOAD:int = 11015;
      public static const OFFER:int = 11016;
      public static const LIBRARY_ASK:int = 11070;
      public static const LIBRARY:int = 11071;
      public static const SHARE:int = 11072;
      public static const KEY_ASK:int = 11084;
      public static const KEY:int = 11085;
      public static const MINE_ASK:int = 11086;
      public static const MINE:int = 11087;
      public static const SET:int = 11088;
      private static const BUSY_LIBRARY:String = "mods:library";
      private static const BUSY_MINE:String = "mods:mine";
      private static const BUSY_KEY:String = "mods:key";

      public static var mine:Object = null;
      public static var mineChanged:Function = null;
      private static var mineWeb:uint = 0;
      private static var mineTicket:String = "";
      private static var mineAsked:int = -1;
      public static var keyResult:Object = null;
      public static var keyChanged:Function = null;
      private static var keyWeb:uint = 0;
      private static var keyTicket:String = "";

      public static var library:Array = null;
      public static var libraryError:String = null;
      public static var libraryChanged:Function = null;
      private static var libraryWeb:uint = 0;
      private static var libraryTicket:String = "";
      private static var libraryAsked:int = -1;
      private static var libraryAt:int = -1;
      private static var sharing:Object = {};
      public static var shareDone:Function = null;

      private static var installedNow:Object = {};

      private static const PATH:RegExp = /^[A-Za-z0-9 _.-]+(\/[A-Za-z0-9 _.-]+)*$/;
      private static const MAX_FILES:int = 4096;
      private static const RETRIES:int = 40;

      private static var quiet:Object = {};

      public function ModShare()
      {
      }

      public static function register() : void
      {
         Hooks.mainMenuButtonsBuilt.add(function(menu:Object):void
         {
            if(!updatesChecked && hasSubscriptions())
            {
               updatesChecked = true;
               checkForUpdates(24);
            }
         });
         Hooks.packetReceived.add(function(packet:Object):Boolean
         {
            if(packet != null && packet.type == LIBRARY)
            {
               libraryArrived(packet);
               return true;
            }
            if(packet != null && (packet.type == MINE || packet.type == KEY))
            {
               jsonArrived(packet);
               return true;
            }
            if(packet == null || (packet.type != UPLOAD && packet.type != OFFER))
            {
               return false;
            }
            try
            {
               var web:uint = packet.readUint();
               var ticket:String = packet.readString();
               var host:String = packet.type == OFFER ? packet.readString() : null;
               var n:uint = packet.readUint();
               var entries:Array = [];
               for(var i:int = 0; i < int(Math.min(n,60)); i++)
               {
                  entries.push(packet.readString());
               }
               if(packet.type == UPLOAD)
               {
                  upload(web,ticket,entries);
               }
               else
               {
                  offer(web,ticket,host,entries);
               }
            }
            catch(e:Error)
            {
               PrivateServer.log("mod sharing: bad packet " + packet.type + " (" + e.message + ")");
            }
            return true;
         });
      }

      public static function browse(quiet:Boolean = false) : Boolean
      {
         try
         {
            var core:Object = Object(GameApp.mainInstance).var_13259;
            var packet:NetPacket = new NetPacket(LIBRARY_ASK);
            var sent:Boolean = core.sendToServer(packet);
            packet.method_839();
            if(sent)
            {
               libraryAsked = getTimer();
               if(!quiet)
               {
                  Busy.start(BUSY_LIBRARY,"LOADING COMMUNITY MODS",15000);
               }
            }
            return sent;
         }
         catch(e:Error)
         {
            PrivateServer.log("mod library: could not ask (" + e.message + ")");
         }
         return false;
      }

      public static function browsing() : Boolean
      {
         return libraryAsked >= 0 && getTimer() - libraryAsked < 15000;
      }

      public static function previewUrl(entry:String) : String
      {
         return libraryWeb > 0 && libraryTicket ? url(libraryWeb,"/mods/preview",libraryTicket,entry) : null;
      }

      public static function shareState(mod:Object) : String
      {
         if(mine == null || mine.error != null || mod == null)
         {
            return null;
         }
         var entry:String = ModCheck.entryOf(mod);
         if(sharing[entry])
         {
            return "sending";
         }
         var copy:Object = mineOf(entry);
         return copy != null ? String(copy.visibility) : "share";
      }

      public static function mineOf(entry:String) : Object
      {
         for each(var m:Object in mine != null && mine.mods is Array ? mine.mods : [])
         {
            if(m.entry == entry)
            {
               return m;
            }
         }
         return null;
      }

      public static function installed(entry:String) : Object
      {
         for each(var m:Object in ContentMods.mods.concat(ContentMods.all))
         {
            if(ModCheck.entryOf(m) == entry && m.dir != null)
            {
               return m;
            }
         }
         return null;
      }

      private static function send(type:int, write:Function) : Boolean
      {
         try
         {
            var core:Object = Object(GameApp.mainInstance).var_13259;
            var packet:NetPacket = new NetPacket(type);
            if(write != null)
            {
               write(packet);
            }
            var sent:Boolean = core.sendToServer(packet);
            packet.method_839();
            return sent;
         }
         catch(e:Error)
         {
            PrivateServer.log("mod library: could not send " + type + " (" + e.message + ")");
         }
         return false;
      }

      public static function share(mod:Object, asPublic:Boolean = false) : Boolean
      {
         var entry:String = ModCheck.entryOf(mod);
         var sent:Boolean = send(SHARE,function(packet:NetPacket):void
         {
            packet.writeUint(1);
            packet.writeString(entry);
            packet.writeUint(asPublic ? 1 : 0);
         });
         if(sent)
         {
            sharing[entry] = true;
            PrivateServer.log("mod sharing: asked to send " + entry + (asPublic ? " for review" : " (private)"));
            setTimeout(function():void
            {
               if(sharing[entry] === true)
               {
                  delete sharing[entry];
                  shared(entry,"the server didn't ask for it");
               }
            },15000);
         }
         return sent;
      }

      public static function like(modId:String, on:Boolean) : Boolean
      {
         var sent:Boolean = send(SET,function(packet:NetPacket):void
         {
            packet.writeString(modId);
            packet.writeString(on ? "like" : "unlike");
            packet.writeString("");
         });
         if(sent)
         {
            libraryAsked = getTimer();
            Busy.start(BUSY_LIBRARY,"ASKING THE SERVER",15000);
         }
         return sent;
      }

      private static const SUBSCRIBED_FILE:String = "mods-subscribed.json";

      private static var subscribed:Object = null;

      private static var updating:Object = {};

      private static var updatesChecked:Boolean = false;

      public static var updated:Array = [];

      private static function subscriptions() : Object
      {
         if(subscribed != null)
         {
            return subscribed;
         }
         subscribed = {};
         try
         {
            var f:File = Platform.dataFile(SUBSCRIBED_FILE);
            if(f.exists)
            {
               var stream:FileStream = new FileStream();
               stream.open(f,FileMode.READ);
               var got:Object = JSON.parse(stream.readUTFBytes(stream.bytesAvailable));
               stream.close();
               for(var id:String in got)
               {
                  if(got[id] != null && got[id].entry is String)
                  {
                     subscribed[id] = {"entry":String(got[id].entry),"uploader":String(got[id].uploader || "")};
                  }
               }
            }
         }
         catch(e:Error)
         {
            PrivateServer.log("mod updates: " + SUBSCRIBED_FILE + " unreadable (" + e.message + ")");
         }
         return subscribed;
      }

      private static function saveSubscriptions() : void
      {
         try
         {
            var stream:FileStream = new FileStream();
            stream.open(Platform.dataFile(SUBSCRIBED_FILE),FileMode.WRITE);
            stream.writeUTFBytes(JSON.stringify(subscriptions()));
            stream.close();
         }
         catch(e:Error)
         {
            PrivateServer.log("mod updates: could not write " + SUBSCRIBED_FILE + " (" + e.message + ")");
         }
      }

      private static function checkForUpdates(tries:int) : void
      {
         setTimeout(function():void
         {
            if(library != null && libraryError == null)
            {
               return;
            }
            if(!browsing())
            {
               browse(true);
            }
            if(tries > 1)
            {
               checkForUpdates(tries - 1);
            }
         },5000);
      }

      private static function hasSubscriptions() : Boolean
      {
         for(var id:String in subscriptions())
         {
            return true;
         }
         return false;
      }

      public static function isSubscribed(id:String) : Boolean
      {
         return subscriptions()[id] != null;
      }

      private static function subscribe(entry:String) : void
      {
         var uploader:String = "";
         for each(var m:Object in library)
         {
            if(m.entry == entry)
            {
               uploader = String(m.uploader || "");
            }
         }
         subscriptions()[entry.split("@")[0]] = {"entry":entry,"uploader":uploader};
         saveSubscriptions();
      }

      private static function unsubscribe(id:String) : void
      {
         if(subscriptions()[id] != null)
         {
            delete subscriptions()[id];
            saveSubscriptions();
         }
      }

      private static function updateSubscribed() : void
      {
         for each(var m:Object in library)
         {
            var id:String = String(m.id);
            var sub:Object = subscriptions()[id];
            var had:String = sub != null ? String(sub.entry) : null;
            var entry:String = String(m.entry);
            if(had == null || had == entry || updating[id] || ModSettings.isDisabled(id) || removedNow[id] === true)
            {
               continue;
            }
            if(!sub.uploader || String(m.uploader || "") != sub.uploader)
            {
               continue;
            }
            var mine:Object = null;
            for each(var inst:Object in ContentMods.all)
            {
               if(inst.id == id && inst.dir is File && (inst.dir as File).exists)
               {
                  mine = inst;
               }
            }
            if(mine == null || ModCheck.entryOf(mine) != had)
            {
               continue;
            }
            updating[id] = true;
            PrivateServer.log("mod updates: " + id + " " + had.split("#")[0] + " > " + entry.split("#")[0]);
            getFromLibrary(entry,updateDone(m,mine));
         }
      }

      private static function updateDone(m:Object, old:Object) : Function
      {
         return function(why:String):void
         {
            delete updating[String(m.id)];
            if(why == null)
            {
               updated.push(m.name + " " + old.version + " > " + m.version);
               PrivateServer.log("mod updates: " + m.id + " updated to " + m.version + " (loads at the next start)");
               Notices.add("mods-updated",updated.length == 1 ? "MOD UPDATED" : updated.length + " MODS UPDATED",
                  updated.join(", ") + " (loads at the next start)","Coins");
            }
            else
            {
               PrivateServer.log("mod updates: " + m.id + " not updated (" + why + ")");
            }
            if(libraryChanged != null)
            {
               try
               {
                  libraryChanged();
               }
               catch(e:Error)
               {
               }
            }
         };
      }

      public static var libraryMessage:String = null;

      private static var removedNow:Object = {};

      public static function remove(mod:Object) : String
      {
         var dir:File = mod != null ? mod.dir as File : null;
         if(dir == null || !dir.exists)
         {
            return "its folder isn't there";
         }
         try
         {
            var aside:File = asideOf(dir,"mods-removed");
            new File(dir.nativePath).moveTo(aside);
            PrivateServer.log("mods: removed " + mod.id + " " + mod.version + " (moved to " + aside.nativePath + ")");
         }
         catch(e:Error)
         {
            return "could not move its folder (" + e.message + ")";
         }
         removedNow[mod.id] = true;
         unsubscribe(mod.id);
         for(var entry:String in installedNow)
         {
            if(entry.split("@")[0] == mod.id)
            {
               delete installedNow[entry];
            }
         }
         return null;
      }

      private static function asideOf(dir:File, kind:String) : File
      {
         var parent:File = new File(dir.parent.parent.resolvePath(kind).nativePath);
         if(!parent.exists)
         {
            parent.createDirectory();
         }
         return parent.resolvePath(dir.name + "-" + new Date().time);
      }

      public static function isRemoved(mod:Object) : Boolean
      {
         return mod != null && removedNow[mod.id] === true && !(mod.dir is File && (mod.dir as File).exists);
      }

      public static function askMine() : Boolean
      {
         var sent:Boolean = send(MINE_ASK,null);
         if(sent)
         {
            mineAsked = getTimer();
            Busy.start(BUSY_MINE,"LOADING YOUR MODS ON THE SERVER",15000);
         }
         return sent;
      }

      public static function askingMine() : Boolean
      {
         return mineAsked >= 0 && getTimer() - mineAsked < 15000;
      }

      public static function act(pid:String, action:String, note:String = "") : Boolean
      {
         var sent:Boolean = send(SET,function(packet:NetPacket):void
         {
            packet.writeString(pid);
            packet.writeString(action);
            packet.writeString(note || "");
         });
         if(sent)
         {
            mineAsked = getTimer();
            Busy.start(BUSY_MINE,"ASKING THE SERVER",15000);
         }
         return sent;
      }

      public static function askKey(key:String) : Boolean
      {
         keyResult = null;
         var sent:Boolean = send(KEY_ASK,function(packet:NetPacket):void
         {
            packet.writeString(key);
         });
         if(sent)
         {
            Busy.start(BUSY_KEY,"LOOKING UP THE KEY",15000);
         }
         return sent;
      }

      private static function jsonArrived(packet:Object) : void
      {
         var isMine:Boolean = packet.type == MINE;
         var got:Object;
         var web:uint = 0;
         var ticket:String = "";
         try
         {
            web = packet.readUint();
            ticket = packet.readString();
            got = JSON.parse(packet.readString());
         }
         catch(e:Error)
         {
            got = {"error":"The server's answer couldn't be read."};
         }
         if(!isMine)
         {
            Busy.done(BUSY_KEY);
            keyWeb = web;
            keyTicket = ticket;
            keyResult = got;
            PrivateServer.log("mod key: " + (got.error != null ? got.error : got.mod.entry));
            call(keyChanged);
            return;
         }
         mineAsked = -1;
         Busy.done(BUSY_MINE);
         mineWeb = web;
         mineTicket = ticket;
         mine = got;
         PrivateServer.log("mod library: " + (got.error != null ? got.error : (got.mods is Array ? got.mods.length : 0) +
            " mods of ours on the server") + (got.message ? " (" + got.message + ")" : ""));
         var message:String = got.error != null ? String(got.error) : String(got.message || "");
         for(var entry:String in sharing)
         {
            if(sharing[entry] === true && message)
            {
               shared(entry,message.indexOf("Not sent") == 0 || got.error != null ? message.replace(/^Not sent: /,"").replace(/\.$/,"") : null);
            }
         }
         call(mineChanged);
         call(libraryChanged);
      }

      private static function call(f:Function) : void
      {
         if(f != null)
         {
            try
            {
               f();
            }
            catch(e:Error)
            {
               ErrorLog.write("mod library: a window's callback failed: " + e);
            }
         }
      }

      public static function getByKey(entry:String, done:Function) : void
      {
         getWith(keyWeb,keyTicket,entry,done);
      }

      public static function getMine(entry:String, done:Function) : void
      {
         getWith(mineWeb,mineTicket,entry,done);
      }

      private static function getWith(web:uint, ticket:String, entry:String, done:Function) : void
      {
         var state:String = stateOf(entry);
         if(state == "loaded" || state == "on")
         {
            done(null);
            return;
         }
         if(state == "off")
         {
            ModSettings.setDisabled(entry.split("@")[0],false);
            done(null);
            return;
         }
         if(web == 0 || !ticket)
         {
            done("the server gave no download ticket");
            return;
         }
         fetch(web,ticket,entry,RETRIES - 1,function(why:String):void
         {
            DownloadWindow.close();
            done(why);
         });
      }

      private static function shared(entry:String, why:String) : void
      {
         delete sharing[entry];
         if(why == null)
         {
            askMine();
         }
         if(shareDone != null)
         {
            try
            {
               shareDone(entry,why);
            }
            catch(e:Error)
            {
            }
         }
      }

      public static function libraryOlder(ms:int) : Boolean
      {
         return libraryAt < 0 || getTimer() - libraryAt > ms;
      }

      private static function libraryArrived(packet:Object) : void
      {
         libraryAsked = -1;
         Busy.done(BUSY_LIBRARY);
         libraryAt = getTimer();
         try
         {
            libraryWeb = packet.readUint();
            libraryTicket = packet.readString();
            var got:Object = JSON.parse(packet.readString());
            libraryError = got.error != null ? String(got.error) : null;
            libraryMessage = got.message ? String(got.message) : null;
            library = got.mods is Array ? got.mods : [];
         }
         catch(e:Error)
         {
            library = [];
            libraryError = "The server's answer couldn't be read.";
         }
         PrivateServer.log("mod library: " + (libraryError != null ? libraryError : library.length + " mods listed"));
         if(libraryError == null)
         {
            updateSubscribed();
         }
         if(libraryChanged != null)
         {
            try
            {
               libraryChanged();
            }
            catch(e2:Error)
            {
            }
         }
      }

      public static function stateOf(entry:String) : String
      {
         var id:String = entry.split("@")[0];
         if(removedNow[id] === true && !installedNow[entry])
         {
            return "new";
         }
         for each(var m:Object in ContentMods.mods)
         {
            if(ModCheck.entryOf(m) == entry)
            {
               return "loaded";
            }
         }
         if(installedNow[entry])
         {
            return ModSettings.isDisabled(id) ? "off" : "on";
         }
         var other:Boolean = false;
         for each(m in ContentMods.all)
         {
            if(m.id == id)
            {
               if(ModCheck.entryOf(m) == entry)
               {
                  return ModSettings.isDisabled(id) ? "off" : "on";
               }
               other = true;
            }
         }
         return other ? "other" : "new";
      }

      public static function getFromLibrary(entry:String, done:Function) : void
      {
         var state:String = stateOf(entry);
         if(state == "loaded" || state == "on")
         {
            done(null);
            return;
         }
         if(state == "off")
         {
            ModSettings.setDisabled(entry.split("@")[0],false);
            done(null);
            return;
         }
         if(libraryWeb == 0 || !libraryTicket)
         {
            done("the server gave no download ticket");
            return;
         }
         fetch(libraryWeb,libraryTicket,entry,RETRIES - 1,function(why:String):void
         {
            DownloadWindow.close();
            if(why == null)
            {
               subscribe(entry);
            }
            done(why);
         });
      }

      private static function url(web:uint, path:String, ticket:String, entry:String) : String
      {
         return PrivateServer.webUrl(web,path) + "?ticket=" + encodeURIComponent(ticket) + "&entry=" +
            encodeURIComponent(entry);
      }

      private static function upload(web:uint, ticket:String, entries:Array) : void
      {
         var asked:Array = [];
         var own:Array = [];
         for each(var entry:String in entries)
         {
            (sharing[entry] ? own : asked).push(entry);
         }
         if(own.length > 0)
         {
            sendAll(web,ticket,own);
         }
         if(asked.length == 0)
         {
            return;
         }
         if(!ModSettings.flag("shareMods",true))
         {
            PrivateServer.log("mod sharing: the server asked for " + asked.join(", ") + "; not sent (shareMods is off)");
            return;
         }
         var key:String = "up|" + asked.join(",");
         if(getTimer() < Number(quiet[key] || 0))
         {
            return;
         }
         quiet[key] = getTimer() + 120000;
         Modal.show("Send your mods for this room?","The others in the room don't have " + names(asked).join(", ") +
            ". Send " + (asked.length == 1 ? "it" : "them") + " to the server so they can download " +
            (asked.length == 1 ? "it" : "them") + "?\nIt stays private on the server: only this room's players and " +
            "people you give its key to can get it (Mods window > MODS ON THE SERVER). Send only mods you may pass on.",[{
            "label":"Send",
            "action":function():void
            {
               sendAll(web,ticket,asked);
            }
         },{
            "label":"Not now",
            "action":function():void
            {
               PrivateServer.log("mod sharing: not sent (the host said not now): " + asked.join(", "));
            }
         }],true);
      }

      private static function sendAll(web:uint, ticket:String, entries:Array) : void
      {
         for each(var entry:String in entries)
         {
            if(sharing[entry])
            {
               sharing[entry] = "sending";
            }
            var mod:Object = installed(entry);
            if(mod == null)
            {
               PrivateServer.log("mod sharing: asked for " + entry + ", not installed here");
               if(sharing[entry])
               {
                  shared(entry,"it isn't installed here");
               }
               continue;
            }
            try
            {
               var bytes:ByteArray = pack(mod.dir as File);
            }
            catch(e:Error)
            {
               PrivateServer.log("mod sharing: could not pack " + entry + ": " + e.message);
               if(sharing[entry])
               {
                  shared(entry,"it couldn't be packed (" + e.message + ")");
               }
               continue;
            }
            post(url(web,"/mods/upload",ticket,entry),bytes,entry);
         }
      }

      private static function post(address:String, bytes:ByteArray, entry:String) : void
      {
         var req:URLRequest = new URLRequest(address);
         req.method = URLRequestMethod.POST;
         req.contentType = "application/octet-stream";
         req.data = bytes;
         var loader:URLLoader = new URLLoader();
         var status:int = 0;
         var busy:String = "mods:send:" + entry;
         Busy.start(busy,"SENDING " + String(entry.split("@")[0]).toUpperCase() + " TO THE SERVER",120000);
         loader.addEventListener(HTTPStatusEvent.HTTP_STATUS,function(e:HTTPStatusEvent):void
         {
            status = e.status;
         });
         loader.addEventListener(Event.COMPLETE,function(e:Event):void
         {
            Busy.done(busy);
            PrivateServer.log("mod sharing: sent " + entry + " (" + bytes.length + " bytes)");
            if(sharing[entry])
            {
               shared(entry,null);
            }
         });
         var failed:Function = function(e:Event):void
         {
            Busy.done(busy);
            PrivateServer.log("mod sharing: sending " + entry + " failed (" + e.type + (status > 0 ? ", " + status : "") + ")");
            if(sharing[entry])
            {
               var why:String = "";
               try
               {
                  why = String(JSON.parse(String(loader.data)).error || "");
               }
               catch(e2:Error)
               {
               }
               shared(entry,why ? "the server refused it: " + why : (status > 0 ? "the server said " + status : "no answer from the server"));
            }
         };
         loader.addEventListener(IOErrorEvent.IO_ERROR,failed);
         loader.addEventListener(SecurityErrorEvent.SECURITY_ERROR,failed);
         loader.load(req);
      }

      public static function pack(dir:File) : ByteArray
      {
         var files:Array = [];
         collect(dir,"",files);
         if(files.length > MAX_FILES)
         {
            throw new Error(files.length + " files");
         }
         var body:ByteArray = new ByteArray();
         body.writeUTFBytes("BHMP");
         body.writeShort(1);
         body.writeUnsignedInt(files.length);
         for each(var f:Object in files)
         {
            var data:ByteArray = new ByteArray();
            var stream:FileStream = new FileStream();
            stream.open(f.file,FileMode.READ);
            stream.readBytes(data);
            stream.close();
            body.writeUTF(f.path);
            body.writeUnsignedInt(data.length);
            body.writeBytes(data);
         }
         body.compress();
         return body;
      }

      private static function collect(dir:File, prefix:String, out:Array) : void
      {
         for each(var f:File in dir.getDirectoryListing())
         {
            if(f.name.charAt(0) == ".")
            {
               continue;
            }
            var path:String = prefix + f.name;
            if(f.isDirectory)
            {
               collect(f,path + "/",out);
            }
            else if(PATH.test(path))
            {
               out.push({"file":f,"path":path});
            }
            else
            {
               PrivateServer.log("mod sharing: left out " + path + " (name not allowed)");
            }
         }
      }

      public static function plan(wanted:Array) : Object
      {
         var loaded:Object = {};
         for each(var m:Object in ContentMods.mods)
         {
            loaded[m.id] = ModCheck.entryOf(m);
         }
         var installed:Object = {};
         for each(m in ContentMods.all)
         {
            installed[m.id] = ModCheck.entryOf(m);
         }
         var wantedIds:Object = {};
         var on:Array = [];
         var get:Array = [];
         for each(var entry:String in wanted)
         {
            var id:String = entry.split("@")[0];
            wantedIds[id] = true;
            if(loaded[id] == entry)
            {
               continue;
            }
            if(installed[id] == entry)
            {
               on.push(id);
            }
            else
            {
               get.push(entry);
            }
         }
         var off:Array = [];
         for(id in loaded)
         {
            if(!wantedIds[id])
            {
               off.push(id);
            }
         }
         off.sort();
         return {"off":off,"on":on,"get":get};
      }

      private static function offer(web:uint, ticket:String, host:String, wanted:Array) : void
      {
         var p:Object = plan(wanted);
         var off:Array = p.off;
         var on:Array = p.on;
         var get:Array = p.get;
         PrivateServer.log("mod sharing: " + host + "'s mods offered; switch off [" + off.join(", ") + "], on [" +
            on.join(", ") + "], download [" + get.join(", ") + "]");
         if(off.length + on.length + get.length == 0)
         {
            return;
         }
         var key:String = off.join(",") + "|" + on.join(",") + "|" + get.join(",");
         if(getTimer() < Number(quiet[key] || 0))
         {
            PrivateServer.log("mod sharing: already asked about these");
            return;
         }
         quiet[key] = getTimer() + 90000;
         var lines:Array = [];
         if(off.length > 0)
         {
            lines.push("Switch off: " + off.join(", ") + ".");
         }
         if(on.length > 0)
         {
            lines.push("Switch on: " + on.join(", ") + ".");
         }
         if(get.length > 0)
         {
            lines.push("Download from the server: " + names(get).join(", ") + " (sent by " + host + "; the server lets " +
               "through only mods whose game files hold no code, but only take mods from people you trust).");
         }
         lines.push("The game then needs a restart.");
         Modal.show("Use " + host + "'s mods?",lines.join("\n"),[{
            "label":"Use them",
            "action":function():void
            {
               quiet[key] = Number.MAX_VALUE;
               apply(web,ticket,off,on,get);
            }
         },{
            "label":"Not now",
            "action":function():void
            {
               quiet[key] = getTimer() + 300000;
            }
         }],true);
      }

      public static function offerReplay(web:uint, ticket:String, available:Array, recorded:Array, differ:String,
         watch:Function = null) : Boolean
      {
         var p:Object = plan(recorded);
         var held:Object = {};
         for each(var entry:String in available)
         {
            held[entry] = true;
         }
         var get:Array = [];
         var missing:Array = [];
         for each(entry in p.get)
         {
            (held[entry] && web > 0 && ticket ? get : missing).push(entry);
         }
         PrivateServer.log("replay mods: switch off [" + p.off.join(", ") + "], on [" + p.on.join(", ") + "], download [" +
            get.join(", ") + "], not on the server [" + missing.join(", ") + "]");
         if(p.off.length + p.on.length + get.length == 0)
         {
            return false;
         }
         var lines:Array = ["It's in the Replays list. It was recorded with other content mods than yours, and replays " +
            "play back with the mods you have on, so it may play out differently.",""];
         if(p.off.length > 0)
         {
            lines.push("Switch off: " + p.off.join(", ") + ".");
         }
         if(p.on.length > 0)
         {
            lines.push("Switch on: " + p.on.join(", ") + ".");
         }
         if(get.length > 0)
         {
            lines.push("Download from the server: " + names(get).join(", ") + " (only take mods from people you trust).");
         }
         if(missing.length > 0)
         {
            lines.push("Not on the server: " + names(missing).join(", ") + ".");
         }
         lines.push("The game then needs a restart; switch your mods back in the Mods window afterwards.");
         Modal.show("Use the replay's mods?",lines.join("\n"),[{
            "label":"Use them",
            "action":function():void
            {
               apply(web,ticket,p.off,p.on,get,"Restart the game to load the mods, then play the replay.");
            }
         },{
            "label":(watch != null ? "Watch anyway" : "Not now"),
            "action":function():void
            {
               if(watch != null)
               {
                  watch();
               }
            }
         }],true);
         return true;
      }

      private static function names(entries:Array) : Array
      {
         var out:Array = [];
         for each(var entry:String in entries)
         {
            out.push(entry.split("#")[0]);
         }
         return out;
      }

      private static function apply(web:uint, ticket:String, off:Array, on:Array, get:Array, done:String = null) : void
      {
         for each(var id:String in off)
         {
            ModSettings.setDisabled(id,true);
         }
         for each(id in on)
         {
            ModSettings.setDisabled(id,false);
         }
         var failed:Array = [];
         var next:Function = function(i:int):void
         {
            if(i >= get.length)
            {
               DownloadWindow.close();
               var text:String = done || "Restart the game to load the mods, then lock in again.";
               if(failed.length > 0)
               {
                  text = "Not installed: " + failed.join("; ") + ".\n" + text;
               }
               Modal.show(failed.length > 0 ? "Some mods failed" : "Mods ready",text,null,failed.length > 0);
               return;
            }
            fetch(web,ticket,get[i],0,function(why:String):void
            {
               if(why != null)
               {
                  failed.push(String(get[i]).split("#")[0] + " (" + why + ")");
               }
               next(i + 1);
            },i + 1,get.length);
         };
         next(0);
      }

      private static function fetch(web:uint, ticket:String, entry:String, attempt:int, done:Function, index:int = 1,
                                    count:int = 1) : void
      {
         var loader:URLLoader = new URLLoader();
         loader.dataFormat = URLLoaderDataFormat.BINARY;
         var name:String = entry.split("#")[0];
         DownloadWindow.progress(name,index,count,0,0);
         loader.addEventListener(ProgressEvent.PROGRESS,function(e:ProgressEvent):void
         {
            DownloadWindow.progress(name,index,count,e.bytesLoaded,e.bytesTotal);
         });
         var status:int = 0;
         loader.addEventListener(HTTPStatusEvent.HTTP_STATUS,function(e:HTTPStatusEvent):void
         {
            status = e.status;
         });
         loader.addEventListener(Event.COMPLETE,function(e:Event):void
         {
            var why:String = install(entry,loader.data as ByteArray);
            PrivateServer.log("mod sharing: " + entry + (why == null ? " installed" : " not installed: " + why));
            done(why);
         });
         var failed:Function = function(e:Event):void
         {
            if(status == 404 && attempt < RETRIES)
            {
               setTimeout(fetch,3000,web,ticket,entry,attempt + 1,done,index,count);
               return;
            }
            done(status == 404 ? "the host didn't send it" : (status > 0 ? "server said " + status : "no answer from the server"));
         };
         loader.addEventListener(IOErrorEvent.IO_ERROR,failed);
         loader.addEventListener(SecurityErrorEvent.SECURITY_ERROR,failed);
         loader.load(new URLRequest(url(web,"/mods/get",ticket,entry)));
      }

      public static function install(entry:String, pkg:ByteArray) : String
      {
         var files:Array;
         try
         {
            files = unpack(pkg);
         }
         catch(e:Error)
         {
            return e.message;
         }
         var manifest:ByteArray = null;
         for each(var f:Object in files)
         {
            if(f.path == "mod.json")
            {
               manifest = f.data;
            }
         }
         if(manifest == null)
         {
            return "no mod.json";
         }
         manifest.position = 0;
         var text:String = manifest.readUTFBytes(manifest.length);
         if(text.charCodeAt(0) == 0xFEFF)
         {
            text = text.substr(1);
         }
         var mod:Object = ContentMods.parse("download",text);
         if(mod == null || ModCheck.entryOf(mod) != entry)
         {
            return "its contents aren't the ones offered";
         }
         var root:File = new File(File.applicationDirectory.resolvePath(ContentMods.FOLDER).nativePath);
         try
         {
            for each(var old:Object in ContentMods.all)
            {
               if(old.id == mod.id && old.dir != null && (old.dir as File).exists)
               {
                  var aside:File = asideOf(old.dir as File,"mods-replaced");
                  new File((old.dir as File).nativePath).moveTo(aside);
                  PrivateServer.log("mod sharing: moved the installed " + old.id + " " + old.version + " to " + aside.nativePath);
               }
            }
            var dir:File = root.resolvePath(mod.id);
            for(var n:int = 2; dir.exists; n++)
            {
               dir = root.resolvePath(mod.id + "-" + n);
            }
            for each(f in files)
            {
               var stream:FileStream = new FileStream();
               stream.open(dir.resolvePath(f.path),FileMode.WRITE);
               stream.writeBytes(f.data);
               stream.close();
            }
         }
         catch(e:Error)
         {
            try
            {
               if(dir != null && dir.exists)
               {
                  dir.deleteDirectory(true);
               }
            }
            catch(e2:Error)
            {
            }
            return "could not write it (" + e.message + ")";
         }
         ModSettings.setDisabled(mod.id,false);
         installedNow[entry] = true;
         delete removedNow[mod.id];
         return null;
      }

      public static function unpack(pkg:ByteArray) : Array
      {
         var body:ByteArray = new ByteArray();
         pkg.position = 0;
         pkg.readBytes(body);
         try
         {
            body.uncompress();
         }
         catch(e:Error)
         {
            throw new Error("not a package");
         }
         body.position = 0;
         if(body.length < 10 || body.readUTFBytes(4) != "BHMP" || body.readUnsignedShort() != 1)
         {
            throw new Error("not a package");
         }
         var n:uint = body.readUnsignedInt();
         if(n > MAX_FILES)
         {
            throw new Error(n + " files");
         }
         var out:Array = [];
         var seen:Object = {};
         for(var i:int = 0; i < int(n); i++)
         {
            if(body.bytesAvailable < 6)
            {
               throw new Error("cut short");
            }
            var path:String = body.readUTF();
            var size:uint = body.readUnsignedInt();
            if(size > body.bytesAvailable)
            {
               throw new Error("cut short");
            }
            if(!PATH.test(path) || dotPart(path) || seen[path.toLowerCase()])
            {
               throw new Error("bad path " + path);
            }
            seen[path.toLowerCase()] = true;
            var data:ByteArray = new ByteArray();
            if(size > 0)
            {
               body.readBytes(data,0,size);
            }
            out.push({"path":path,"data":data});
         }
         if(body.bytesAvailable != 0)
         {
            throw new Error("bytes after the last file");
         }
         return out;
      }

      private static function dotPart(path:String) : Boolean
      {
         for each(var part:String in path.split("/"))
         {
            if(part.charAt(0) == ".")
            {
               return true;
            }
         }
         return false;
      }
   }
}
