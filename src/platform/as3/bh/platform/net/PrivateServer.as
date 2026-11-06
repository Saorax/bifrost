package bh.platform.net
{
   import bh.platform.Platform;
   import bh.platform.Hooks;
   import bh.platform.EngineTls;
   import flash.filesystem.File;
   import flash.filesystem.FileMode;
   import flash.filesystem.FileStream;

   public final class PrivateServer
   {
      public static const FILE:String = "bh-server.json";

      public static const LOG:String = "bh-private.txt";

      public static var host:String = null;

      public static var port:uint = 0;

      public static var webScheme:String = "http";

      public static function webUrl(webPort:uint, path:String) : String
      {
         return webScheme + "://" + host + ":" + webPort + path;
      }

      public static var token:String = null;

      public static var p2pDelay:uint = 48;

      public static var p2pRelayOnly:Boolean = false;

      public static var p2pSmoothing:Boolean = true;

      public static var p2pSmoothingMs:Number = 100;

      public static var p2pRollback:Boolean = true;

      public static var p2pDelaySet:Boolean = false;

      public function PrivateServer()
      {
      }

      public static function readP2PSettings(cfg:Object = null) : void
      {
         try
         {
            if(cfg == null)
            {
               var f:File = Platform.dataFile(FILE);
               if(!f.exists)
               {
                  return;
               }
               var s:FileStream = new FileStream();
               s.open(f,FileMode.READ);
               var text:String = s.readUTFBytes(s.bytesAvailable);
               s.close();
               cfg = JSON.parse(text);
            }
            p2pRollback = cfg.p2p_rollback !== false;
            p2pDelaySet = cfg.p2p_delay_ms != null && !isNaN(Number(cfg.p2p_delay_ms));
            p2pDelay = p2pDelaySet ? uint(Math.max(16,Math.min(240,Math.round(Number(cfg.p2p_delay_ms) / 16) * 16))) : 48;
            p2pRelayOnly = String(cfg.p2p || "") == "relay";
            p2pSmoothing = cfg.p2p_smoothing !== false;
            p2pSmoothingMs = cfg.p2p_smoothing_ms != null && Number(cfg.p2p_smoothing_ms) > 0 ?
               Math.min(1000,Number(cfg.p2p_smoothing_ms)) : 100;
         }
         catch(e:Error)
         {
            log("could not read the P2P settings in " + FILE + ": " + e.message);
         }
      }

      public static function writeP2PSetting(key:String, value:*) : void
      {
         try
         {
            var f:File = Platform.dataFile(FILE);
            var cfg:Object = {};
            if(f.exists)
            {
               var s:FileStream = new FileStream();
               s.open(f,FileMode.READ);
               var text:String = s.readUTFBytes(s.bytesAvailable);
               s.close();
               cfg = JSON.parse(text);
            }
            if(value == null)
            {
               delete cfg[key];
            }
            else
            {
               cfg[key] = value;
            }
            var w:FileStream = new FileStream();
            w.open(f,FileMode.WRITE);
            w.writeUTFBytes(JSON.stringify(cfg,null,2));
            w.close();
            readP2PSettings(cfg);
         }
         catch(e:Error)
         {
            log("could not write " + key + " to " + FILE + ": " + e.message);
         }
      }

      public static var account:String = null;

      public static function useServer(newHost:String, newPort:int) : String
      {
         var why:String = refuse(newHost,newPort);
         if(why != null)
         {
            return why;
         }
         try
         {
            var f:File = Platform.dataFile(FILE);
            var cfg:Object = {};
            if(f.exists)
            {
               var s:FileStream = new FileStream();
               s.open(f,FileMode.READ);
               var text:String = s.readUTFBytes(s.bytesAvailable);
               s.close();
               cfg = JSON.parse(text);
            }
            if(cfg.tokens == null || typeof cfg.tokens != "object")
            {
               cfg.tokens = {};
            }
            if(cfg.host && cfg.token)
            {
               cfg.tokens[String(cfg.host) + ":" + int(cfg.port)] = {"token":cfg.token,"account":cfg.account || null};
            }
            var mine:Object = cfg.tokens[newHost + ":" + newPort];
            cfg.host = newHost;
            cfg.port = newPort;
            if(mine != null && mine.token)
            {
               cfg.token = mine.token;
               cfg.account = mine.account;
            }
            else
            {
               delete cfg.token;
               delete cfg.account;
            }
            var w:FileStream = new FileStream();
            w.open(f,FileMode.WRITE);
            w.writeUTFBytes(JSON.stringify(cfg,null,2));
            w.close();
            log("server set to " + newHost + ":" + newPort + " for the next start" + (mine != null ? " (signed in there before)" : ""));
         }
         catch(e:Error)
         {
            return e.message;
         }
         return null;
      }

      public static var main:Object = null;

      public static function init() : void
      {
         try
         {
            var f:File = Platform.dataFile(FILE);
            if(!f.exists)
            {
               log("no " + FILE + ": staying offline");
               return;
            }
            var s:FileStream = new FileStream();
            s.open(f,FileMode.READ);
            var text:String = s.readUTFBytes(s.bytesAvailable);
            s.close();
            var cfg:Object = JSON.parse(text);
            main = cfg.main != null && cfg.main.host ? {"host":String(cfg.main.host),"port":int(cfg.main.port) || 7910} : null;
            var h:String = String(cfg.host || "").replace(/^\s+|\s+$/g,"");
            var p:int = int(cfg.port);
            var why:String = refuse(h,p);
            if(why != null)
            {
               log("endpoint refused (" + why + "): staying offline");
               return;
            }
            if(host != h)
            {
               webScheme = "http";
            }
            host = h;
            port = uint(p);
            EngineTls.pinServer(host);
            token = cfg.token ? String(cfg.token) : null;
            account = cfg.account ? String(cfg.account) : null;
            readP2PSettings(cfg);
            GameTls.setting = cfg.hasOwnProperty("tls") ? cfg.tls === true : undefined;
            GameApp.var_8102 = host;
            GameApp.var_8980 = port;
            log("private server " + host + ":" + port + (token ? " (with a token)" : "") + "; the game connects there and nowhere else");
            if(started)
            {
               return;
            }
            started = true;
            Hooks.packetSending.add(function(connection:Object, packet:Object):Boolean
            {
               if(token && packet != null && packet.type == 30)
               {
                  sendToken();
               }
               if(packet != null && packet.type == 33)
               {
                  sendRoomDefaults();
               }
               if(packet != null && packet.type == 55)
               {
                  P2PMatch.sendStartDetails();
               }
               return false;
            });
            Cosmetics.register();
            ModItems.register();
            StartCover.register();
            HudPing.register();
            P2PMatch.register();
            P2PSession.register();
            SpectateFeed.register();
            Rejoin.register();
            RoomNet.register();
            LegendLevels.register();
            MatchReport.register();
            ReplayShare.register();
            ServerStats.register();
            Friends.register();
            Clans.register();
            Skirmish.register();
            ChatRestriction.register();
            ModCheck.register();
            LevelSelectBack.register();
            ModShare.register();
            Tournaments.register();
            PlayerName.init();
            DiscordLogin.init();
         }
         catch(e:Error)
         {
            log("could not read " + FILE + " (" + e.message + "): staying offline");
         }
      }

      private static var started:Boolean = false;

      public static function switchTo(newHost:String, newPort:int) : String
      {
         var why:String = useServer(newHost,newPort);
         if(why != null)
         {
            return why;
         }
         var wasHost:String = host;
         init();
         if(host != newHost || port != uint(newPort))
         {
            return "the new server couldn't be read back from " + FILE;
         }
         ServerStats.forget();
         Friends.state = null;
         try
         {
            GameApp.forceOffline = false;
            var core:GameCore = Object(GameApp.mainInstance).var_13259 as GameCore;
            if(core != null)
            {
               core.disconnectFromServer();
               core.requestReconnect(false);
               if(!(core.serverConnection != null && core.serverConnection.isConnected()))
               {
                  core.connectToServer();
               }
            }
            log("switched from " + (wasHost != null ? wasHost : "offline") + " to " + host + ":" + port + " without a restart");
         }
         catch(e:Error)
         {
            log("switching servers: " + e.message + "; restart the game to connect to " + host + ":" + port);
            return "reconnecting failed (" + e.message + "): restart the game";
         }
         return null;
      }

      public static const LINK_TOKEN:int = 11001;

      public static const ROOM_DEFAULTS:int = 11003;

      private static function sendRoomDefaults() : void
      {
         try
         {
            var g:Object = Object(GameApp.mainInstance).var_13259;
            var d:class_166 = new class_166();
            d.method_624(ScoringType.STOCK);
            var p:NetPacket = new NetPacket(ROOM_DEFAULTS);
            d.method_4231(p);
            g.sendToServer(p);
            p.method_839();
            log("sent the custom room defaults");
         }
         catch(e:Error)
         {
            log("could not send the custom room defaults: " + e.message);
         }
      }

      private static function sendToken() : void
      {
         try
         {
            var g:Object = Object(GameApp.mainInstance).var_13259;
            var p:NetPacket = new NetPacket(LINK_TOKEN);
            p.writeString(token);
            g.sendToServer(p);
            p.method_839();
            log("sent the account token");
         }
         catch(e:Error)
         {
            log("could not send the account token: " + e.message);
         }
      }

      public static function refuse(h:String, p:int) : String
      {
         if(!h)
         {
            return "no host";
         }
         if(p <= 0 || p > 65535)
         {
            return "port must be 1-65535";
         }
         if(!/^[A-Za-z0-9.\-:\[\]]+$/.test(h))
         {
            return "host has characters a host name can't have";
         }
         if(/brawlhalla|bmg|ubi(soft)?\b|ubi\./i.test(h))
         {
            return "that is an official host name";
         }
         if(/^199\.229\.253\./.test(h) || officialAddresses().indexOf(h) >= 0)
         {
            return "that is one of the game's official server addresses";
         }
         return null;
      }

      public static function officialAddresses() : Array
      {
         var out:Array = ["18.188.245.3"];
         var i:int = 0;
         try
         {
            for(i = 0; i < int(class_51.var_8023); i++)
            {
               out.push("199.229.253." + class_51.var_5701[i]);
            }
            for(i = 0; i < int(class_51.var_2796); i++)
            {
               out.push([class_51.var_6503[i],class_51.var_6787[i],class_51.var_963[i],class_51.var_8155[i]].join("."));
            }
         }
         catch(e:Error)
         {
         }
         return out;
      }

      public static function log(line:String, now:Boolean = false) : void
      {
         var text:String = new Date().toUTCString() + " " + line + "\r\n";
         if(held != null)
         {
            held.push(text);
            if(now || held.length >= HELD_MAX)
            {
               write(held.join(""));
               held.length = 0;
            }
            return;
         }
         write(text);
      }

      public static function hold(on:Boolean) : void
      {
         if(!on && held != null && held.length > 0)
         {
            write(held.join(""));
         }
         held = on ? [] : null;
      }

      private static var held:Array = null;
      private static const HELD_MAX:int = 400;

      private static function write(text:String) : void
      {
         try
         {
            var s:FileStream = new FileStream();
            s.open(Platform.dataFile(LOG),FileMode.APPEND);
            s.writeUTFBytes(text);
            s.close();
         }
         catch(e:Error)
         {
         }
      }
   }
}
