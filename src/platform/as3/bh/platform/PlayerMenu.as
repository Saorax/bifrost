package bh.platform
{
   import bh.platform.net.Friends;
   import bh.platform.net.PrivateServer;
   import bh.platform.net.ServerStats;
   import flash.desktop.Clipboard;
   import flash.desktop.ClipboardFormats;

   public final class PlayerMenu
   {
      public function PlayerMenu()
      {
      }

      public static function entries(p:Object, extra:Array = null) : Array
      {
         var out:Array = [];
         if(p == null)
         {
            return extra != null ? extra : out;
         }
         var account:int = int(p.account);
         var pid:uint = uint(p.pid);
         var id:String = p.id != null ? String(p.id) : "";
         var name:String = p.name != null ? String(p.name) : "";
         if(account > 0 || pid != 0)
         {
            out.push(["VIEW PROFILE",function():void
            {
               if(account > 0)
               {
                  ProfileWindow.openAccount(account,name);
               }
               else
               {
                  ProfileWindow.open(pid,name);
               }
            }]);
         }
         var friend:String = PrivateServer.host != null && !isMe(account,id) ? friendship(id,name) : "self";
         var who:String = id != "" ? id : name;
         if(friend == "incoming")
         {
            out.push(["ACCEPT FRIEND REQUEST",friendAction("accept",matchedId,name)]);
         }
         else if(friend == "" && who != "")
         {
            out.push(["ADD FRIEND",friendAction("add",who,name)]);
         }
         if(pid != 0 && friend != "self")
         {
            out.push(mute(pid,name));
         }
         if(extra != null)
         {
            out = out.concat(extra);
         }
         if(name != "")
         {
            out.push(["COPY NAME",function():void
            {
               try
               {
                  Clipboard.generalClipboard.setData(ClipboardFormats.TEXT_FORMAT,name);
                  DummyDrift.show("Copied: " + name,1800);
               }
               catch(e:Error)
               {
                  DummyDrift.show("The name couldn't be copied",1800);
               }
            }]);
         }
         return out;
      }

      private static function isMe(account:int, id:String) : Boolean
      {
         var seasons:Object = ServerStats.get("seasons");
         if(account > 0 && seasons != null && int(seasons.you) == account)
         {
            return true;
         }
         return id != "" && Friends.state != null && String(Friends.state.me) == id;
      }

      private static var matchedId:String = "";

      private static function friendship(id:String, name:String) : String
      {
         var st:Object = Friends.state;
         if(st == null)
         {
            return "";
         }
         var lower:String = name.toLowerCase();
         for each(var kind:String in ["friends","outgoing","incoming"])
         {
            for each(var f:Object in st[kind] as Array || [])
            {
               if(id != "" && String(f.id) == id || lower != "" && String(f.name || "").toLowerCase() == lower)
               {
                  matchedId = String(f.id || "");
                  return kind == "friends" ? "friend" : kind;
               }
            }
         }
         return "";
      }

      private static function mute(pid:uint, name:String) : Array
      {
         var core:Object = null;
         var muted:Boolean = false;
         try
         {
            core = Object(GameApp.mainInstance).var_13259;
            muted = Boolean(core.method_5635(pid));
         }
         catch(e:Error)
         {
         }
         return [muted ? "UNMUTE" : "MUTE AND BLOCK",function():void
         {
            try
            {
               var packet:NetPacket = new NetPacket(LinkUpdater.var_6072);
               packet.writeUint(core.var_14656);
               packet.writeUint(pid);
               core.sendToServer(packet);
               packet.method_839();
               DummyDrift.show(muted ? name + " unmuted." : name + " muted: no chat, invites or matches with them.",3000);
            }
            catch(e:Error)
            {
               DummyDrift.show("Not connected to a server.",2000);
            }
            PrivateServer.log("player menu: " + (muted ? "unmute " : "mute ") + name + " (" + pid + ")");
         }];
      }

      private static function friendAction(action:String, who:String, name:String) : Function
      {
         return function():void
         {
            Friends.command(action,who,function(ok:Boolean, message:String):void
            {
               DummyDrift.show(message != "" ? message : ok ? "Sent." : "The server said no.",3000);
            });
            PrivateServer.log("player menu: " + action + " " + name);
         };
      }
   }
}
