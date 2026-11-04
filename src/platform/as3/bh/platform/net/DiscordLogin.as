package bh.platform.net
{
   import bh.platform.Platform;
   import bh.platform.Hooks;
   import bh.platform.Modal;
   import flash.events.MouseEvent;
   import flash.events.TimerEvent;
   import flash.filesystem.File;
   import flash.filesystem.FileMode;
   import flash.filesystem.FileStream;
   import flash.net.URLRequest;
   import flash.net.navigateToURL;
   import flash.utils.Timer;

   public final class DiscordLogin
   {
      public static const LOGIN_START:int = 11007;
      public static const LOGIN_LINK:int = 11008;
      public static const WEB_SCHEME:int = 11093;
      public static const LOGIN_RESULT:int = 11009;
      public static const LOGIN_NEEDED:int = 11010;
      public static const NOTICE:int = 11013;

      public static const ROW:String = "UI_Bifrost_LoginDiscord";

      public static const TITLE:String = "Discord";

      private static var pending:Boolean = false;

      private static var timer:Timer;

      public function DiscordLogin()
      {
      }

      public static function init() : void
      {
         Hooks.stringsLoaded.add(function(language:Localization):void
         {
            language.var_15061.method_65(ROW,"Login with Discord");
         });
         Hooks.optionsMenuBuilding.add(function(screen:Object, list:Object):void
         {
            list.method_7864(ROW,function(e:MouseEvent, index:uint, change:int):void
            {
               start();
            },function(e:MouseEvent, index:uint):void
            {
               screen.method_1986(e,index);
            },null,"a_MenuBtnForOptionUI");
         });
         Hooks.packetReceived.add(onPacket);
         timer = new Timer(1000);
         timer.addEventListener(TimerEvent.TIMER,function(e:TimerEvent):void
         {
            showPending();
         });
         timer.start();
      }

      public static function start() : void
      {
         try
         {
            var core:Object = GameApp.mainInstance != null ? Object(GameApp.mainInstance).var_13259 : null;
            if(core == null || core.serverConnection == null || !core.serverConnection.isConnected())
            {
               Modal.show(TITLE,"Not connected to a Bifrost server. Check the server address in Documents\\Bifrost\\bh-server.json.");
               return;
            }
            var packet:NetPacket = new NetPacket(LOGIN_START);
            core.sendToServer(packet);
            packet.method_839();
            PrivateServer.log("asked the server for a Discord sign-in link (11007)");
         }
         catch(e:Error)
         {
            PrivateServer.log("could not start the Discord sign-in: " + e.message);
         }
      }

      private static function onPacket(packet:Object) : Boolean
      {
         if(packet != null && packet.type == WEB_SCHEME)
         {
            try
            {
               PrivateServer.webScheme = packet.readString() == "https" ? "https" : "http";
               PrivateServer.log("the server's web side is " + PrivateServer.webScheme);
               if(PrivateServer.webScheme == "https")
               {
                  Tournaments.fetch();
               }
            }
            catch(e:Error)
            {
            }
            return true;
         }
         if(packet != null && packet.type == NOTICE)
         {
            try
            {
               var notice:String = packet.readString();
               Modal.show("Bifrost",notice);
               PrivateServer.log("server notice: " + notice);
            }
            catch(e:Error)
            {
            }
            return true;
         }
         if(packet == null || packet.type < LOGIN_LINK || packet.type > LOGIN_NEEDED)
         {
            return false;
         }
         try
         {
            if(packet.type == LOGIN_LINK)
            {
               var ok:Boolean = packet.method_5885();
               var text:String = packet.readString();
               if(!ok)
               {
                  Modal.show(TITLE,text);
                  PrivateServer.log("no sign-in link: " + text);
               }
               else if(!/^https:\/\/discord\.com\//.test(text))
               {
                  PrivateServer.log("refused a sign-in link that isn't Discord's: " + text);
               }
               else
               {
                  var code:String = "";
                  try
                  {
                     code = packet.readString();
                  }
                  catch(e2:Error)
                  {
                  }
                  navigateToURL(new URLRequest(text));
                  Modal.show("Log in with Discord",code ? "Your code: " + code + "\nType it on the page in your browser." :
                     "Finish logging in in your browser.",null,true);
                  PrivateServer.log("opened the Discord sign-in" + (code ? "; the page asks for code " + code : ""));
               }
            }
            else if(packet.type == LOGIN_RESULT)
            {
               var signedIn:Boolean = packet.method_5885();
               var tokenOrMessage:String = packet.readString();
               var name:String = packet.readString();
               if(signedIn)
               {
                  PrivateServer.token = tokenOrMessage;
                  saveToken(tokenOrMessage,name);
                  Modal.show("Logged in","Logged in with Discord as " + name + ". Your account is ready.");
                  PrivateServer.log("logged in with Discord as " + name + "; token saved in " + PrivateServer.FILE);
               }
               else
               {
                  Modal.show("Discord login failed",tokenOrMessage);
                  PrivateServer.log("Discord sign-in failed: " + tokenOrMessage);
               }
            }
            else if(packet.type == LOGIN_NEEDED)
            {
               pending = true;
               PrivateServer.log("the server has no account for this player yet (11010)");
            }
         }
         catch(e:Error)
         {
            PrivateServer.log("could not read Discord sign-in packet " + packet.type + ": " + e.message);
         }
         return true;
      }

      private static function showPending() : void
      {
         if(!pending)
         {
            return;
         }
         try
         {
            if(ScreenManager.var_10617 != null && ScreenManager.var_10617.isActive)
            {
               pending = false;
               Modal.show("Sign in on " + PrivateServer.host,"This server needs your Discord sign-in once.\n" +
                  "Later: Options > SERVERS > SIGN IN.",[{"label":"Log in","action":start},{"label":"Later"}],true);
            }
         }
         catch(e:Error)
         {
            pending = false;
         }
      }

      private static function saveToken(token:String, name:String) : void
      {
         try
         {
            var f:File = Platform.dataFile(PrivateServer.FILE);
            var cfg:Object = {};
            if(f.exists)
            {
               var s:FileStream = new FileStream();
               s.open(f,FileMode.READ);
               cfg = JSON.parse(s.readUTFBytes(s.bytesAvailable));
               s.close();
            }
            cfg.token = token;
            cfg.account = name;
            if(cfg.tokens == null || typeof cfg.tokens != "object")
            {
               cfg.tokens = {};
            }
            cfg.tokens[String(cfg.host) + ":" + int(cfg.port)] = {"token":token,"account":name};
            var out:FileStream = new FileStream();
            out.open(f,FileMode.WRITE);
            out.writeUTFBytes(JSON.stringify(cfg,null,2));
            out.close();
         }
         catch(e:Error)
         {
            PrivateServer.log("could not save the account token: " + e.message);
         }
      }
   }
}
