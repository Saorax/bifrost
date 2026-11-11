package bh.platform.net
{
   import bh.platform.Hooks;
   import bh.platform.Modal;
   import bh.platform.OnlineTraining;
   import bh.platform.Platform;
   import flash.events.DatagramSocketDataEvent;
   import flash.net.DatagramSocket;
   import flash.net.NetworkInfo;
   import flash.events.TimerEvent;
   import flash.utils.ByteArray;
   import flash.utils.Endian;
   import flash.utils.Timer;
   import flash.utils.getTimer;
   import haxe.ds.IntMap;

   public final class P2PSession
   {
      public static const P2P_HELLO:int = 11011;
      public static const P2P_PEERS:int = 11012;
      public static const TURN_OFFER:int = 11027;
      public static const TURN_ADDRESS:int = 11028;
      public static const TURN_PEERS:int = 11029;

      public static const MAGIC:uint = 0xBF02;
      public static const PING:uint = 1;
      public static const PONG:uint = 2;
      public static const INPUT:uint = 3;
      public static const BYE:uint = 4;
      public static const MODS:uint = 5;
      public static const HELLO_BACK:uint = 6;
      public static const RELAY:uint = 0x10;
      public static const REGISTER:uint = 0x11;

      public static const GIVE_UP:int = 8000;
      public static const MAX_DELAY:uint = 160;
      private static const LOST_TITLE:String = "Connection lost";

      public static const MAX_PREDICT:uint = 240;
      public static const MAX_AUTO_DELAY:uint = 48;
      public static const HIGH_PING_DELAY:uint = 96;
      public static const MAX_CHANGES:int = 64;
      public static const KEEP_FOR_GONE:int = 10000;

      public static var active:Boolean = false;

      private static var shift:Number = 0;

      public static function base(core:Object) : Number
      {
         return Number(uint(core.var_5300)) - shift;
      }

      public static function timeShifted(by:Number) : void
      {
         shift += by;
         Desync.shifted(by);
         selfPending = null;
         Smoothing.jumped();
         PrivateServer.log("P2P room " + room + ": the match clock went back " + by + " ms (a Training load; " + shift +
            " ms in all)");
      }

      public static function get rollbackOn() : Boolean
      {
         return active && rollback;
      }

      public static function get resimulatedSteps() : uint
      {
         return resimulated;
      }

      public static function get ping() : int
      {
         if(!active)
         {
            return -1;
         }
         var worst:int = -1;
         for each(var peer:Object in peers)
         {
            if(peer.gone)
            {
               continue;
            }
            var latest:* = usesDirect(peer) ? peer.lastRtt : peer.lastRelayRtt;
            worst = Math.max(worst,latest != null ? int(latest) : pathRtt(peer));
         }
         return worst;
      }

      public static function get inputDelay() : uint
      {
         return active ? delay : 0;
      }

      public static function get myId() : uint
      {
         return localId;
      }

      public static function get rollbackCount() : uint
      {
         return rollbacks;
      }

      public static function get deepestRollback() : uint
      {
         return deepest;
      }

      public static function get peerLost() : Boolean
      {
         for each(var peer:Object in peers)
         {
            if(peer.gone)
            {
               return true;
            }
         }
         return false;
      }

      public static function get modsState() : String
      {
         return modsDiffer != null ? "DIFFER" : modsHeard > 0 ? "SAME" : "";
      }

      public static function get waitCount() : uint
      {
         return stalls;
      }

      public static function get pathName() : String
      {
         if(pipe != null)
         {
            return String(pipe.name);
         }
         for each(var peer:Object in peers)
         {
            if(!peer.gone && !usesDirect(peer))
            {
               return peer.viaTurn ? "cloudflare" : "relay";
            }
         }
         return "direct";
      }

      private static var registered:Boolean = false;
      public static var pipe:Object = null;
      private static var turn:TurnClient = null;
      private static var turnTimer:Timer = null;
      private static var turnRoom:uint = 0;
      private static var socket:DatagramSocket;
      private static var room:uint;
      private static var localId:uint;
      private static var delay:uint;
      private static var relayOnly:Boolean;
      private static var relayPort:uint = 0;
      private static var tokenHi:uint = 0;
      private static var tokenLo:uint = 0;
      private static var peers:Object = {};
      private static var peerCount:int = 0;

      private static var changes:Array = [];
      private static var confirmed:int = -1;

      private static var passT:int = -1;
      private static var ownT:int = -1;
      private static var skipLogged:Boolean = false;
      private static var lastBits:uint = 0;
      private static var lastSend:int = 0;
      private static var lastRegister:int = 0;
      private static var lastPing:int = 0;
      private static var tuneStarted:int = 0;
      private static var warming:Boolean = false;
      private static var warmRoom:uint = 0;
      private static var warmStart:int = 0;
      public static const WARM_MS:int = 60000;
      private static var stallStart:int = -1;
      private static var recentWaits:Array = [];
      private static var lastFrameAt:int = 0;
      private static var localHitchAt:int = -100000;
      private static var lastRaise:int = -100000;
      private static var rollback:Boolean = false;
      private static var rollbacks:uint = 0;
      private static var resimulated:uint = 0;
      private static var deepest:uint = 0;
      public static var mergeRollbacks:Boolean = true;
      private static var heldLate:uint = uint.MAX_VALUE;
      private static var rolledAt:Number = -1;
      private static var merged:uint = 0;
      private static var samePredicted:uint = 0;
      private static var inputBody:ByteArray = new ByteArray();
      private static var relayBody:ByteArray = new ByteArray();
      private static var sendList:Array = [];
      private static var sendSent:Array = [];
      private static var syncedMs:Number = 0;
      private static var timeStarted:Boolean = false;
      private static var pingTimer:Timer;

      private static var lastPos:Object = {};
      private static var usualStep:Object = {};
      private static var pendingCheck:Object = null;
      private static var diagnosed:int = 0;
      public static const DIAGNOSE:int = 40;
      private static var delayFromPing:Boolean = false;
      private static var startDelay:uint = 0;

      private static var stalls:uint = 0;
      private static var stalledMs:uint = 0;
      private static var waitLog:Array = [];
      private static var stallAt:int = 0;
      private static var stallLocal:Boolean = false;
      private static var modsSent:int = 0;
      private static var lastModsSent:int = 0;
      private static var modsHeard:uint = 0;
      private static var modsDiffer:String = null;
      private static var sentCount:uint = 0;

      private static var runsBots:Boolean = false;
      public static var botRunnerHighest:Boolean = false;
      public static var botController:uint = 0;
      private static var botsKnown:Boolean = false;
      private static var botsTakenAt:int = -1;
      private static var botChanges:Object = {};
      private static var botLast:Object = {};
      private static var botSampled:Object = {};
      private static var botStates:Object = {};

      public static var selfCheck:Boolean = false;
      private static var historyLine:String = "";
      private static var historyFrames:int = 0;
      public static const SELF_CHECK_EVERY:int = 90;
      private static var selfFrames:int = 0;
      private static var selfPending:Array = null;
      private static var selfForced:uint = 0;
      private static var selfCompared:uint = 0;
      private static var selfDiffered:uint = 0;
      private static var selfByPlayer:Object = {};
      private static var selfLogged:int = 0;
      private static var receivedCount:uint = 0;

      private static var handBackT:int = -1;
      private static var handBackSent:int = 0;
      private static var rejoinedSelf:Boolean = false;
      private static var ownSampledBack:Boolean = false;
      private static var backJump:Number = -1;

      public function P2PSession()
      {
      }

      public static function register() : void
      {
         if(registered)
         {
            return;
         }
         registered = true;
         Hooks.simulationFrame.add(onFrame);
         Hooks.simulationRollback.add(function(core:Object):Boolean
         {
            return active && rollback;
         });
         Hooks.botMatchTime.add(function(core:Object):Boolean
         {
            return active && rollback;
         });
         Hooks.replayEndMatchTime.add(function(core:Object):Boolean
         {
            return active && rollback;
         });
         Hooks.inputSampling.add(onSampling);
         Hooks.inputSampled.add(onSampled);
         Hooks.packetReceived.add(onPacket);
         Hooks.pauseMenuPausing.add(function(core:Object):Boolean
         {
            return active;
         });
         Hooks.matchEnded.add(function(to:uint):void
         {
            end(to == MatchReport.END_STATE ? "the match ended" : "the match was left",to != MatchReport.END_STATE);
         });
      }

      public static function prepare(roomNumber:uint, myId:uint, core:Object) : void
      {
         if(active)
         {
            return;
         }
         stopWarm();
         P2PChoice.warmStarts();
         PrivateServer.readP2PSettings();
         room = roomNumber;
         localId = myId;
         relayOnly = PrivateServer.p2pRelayOnly;
         rollback = PrivateServer.p2pRollback;
         delay = rollback && !PrivateServer.p2pDelaySet ? 32 : PrivateServer.p2pDelay;
         peers = {};
         peerCount = 0;
         NetTune.reset();
         tuneStarted = warmStart = getTimer();
         if(!openSocket())
         {
            return;
         }
         warming = true;
         warmRoom = roomNumber;
         pingTimer = new Timer(100);
         pingTimer.addEventListener(TimerEvent.TIMER,onPingTick);
         pingTimer.start();
         var addresses:Array = sendHello(core);
         PrivateServer.log("P2P room " + room + ": match found, pinging the other players before the start (UDP " +
            socket.localPort + ", addresses " + addresses.join(" ") + (relayOnly ? ", relay only" : "") + ")");
      }

      private static function stopWarm(keep:Boolean = false) : void
      {
         if(!warming)
         {
            return;
         }
         warming = false;
         if(pingTimer != null)
         {
            pingTimer.stop();
            pingTimer = null;
         }
         if(!keep)
         {
            peers = {};
            peerCount = 0;
         }
      }

      private static function openSocket() : Boolean
      {
         if(pipe != null)
         {
            return true;
         }
         try
         {
            if(socket == null)
            {
               socket = new DatagramSocket();
               socket.addEventListener(DatagramSocketDataEvent.DATA,onDatagram);
               socket.bind(0,"0.0.0.0");
               socket.receive();
            }
         }
         catch(e:Error)
         {
            PrivateServer.log("P2P: could not open a UDP socket (" + e.message + "); remote players will stand still");
            socket = null;
            return false;
         }
         return true;
      }

      private static function sendHello(core:Object) : Array
      {
         if(pipe != null)
         {
            return [];
         }
         var addresses:Array = localAddresses();
         var hello:NetPacket = new NetPacket(P2P_HELLO);
         hello.writeUint(socket.localPort);
         hello.writeUint(addresses.length);
         for each(var a:String in addresses)
         {
            hello.writeString(a);
         }
         core.sendToServer(hello);
         hello.method_839();
         return addresses;
      }

      public static function begin(roomNumber:uint, myId:uint, core:Object) : void
      {
         P2PChoice.matchStarts(roomNumber);
         end("a new match");
         var warmed:Boolean = warming && warmRoom == roomNumber && myId == localId;
         var warmPeers:Object = peers;
         var warmCount:int = peerCount;
         var warmedFor:int = getTimer() - warmStart;
         stopWarm(warmed);
         room = roomNumber;
         localId = myId;
         PrivateServer.readP2PSettings();
         RoomNet.apply(roomNumber);
         rollback = PrivateServer.p2pRollback;
         Smoothing.start(rollback && PrivateServer.p2pSmoothing,PrivateServer.p2pSmoothingMs);
         try
         {
            core.var_10934 = false;
            core.var_12659 = 0;
            core.var_13849 = 0;
         }
         catch(e:Error)
         {
         }
         delay = rollback && !PrivateServer.p2pDelaySet ? 32 : PrivateServer.p2pDelay;
         rollbacks = resimulated = deepest = merged = samePredicted = 0;
         heldLate = uint.MAX_VALUE;
         rolledAt = -1;
         syncedMs = 0;
         timeStarted = false;
         delayFromPing = false;
         lastPos = {};
         usualStep = {};
         pendingCheck = null;
         diagnosed = 0;
         relayOnly = PrivateServer.p2pRelayOnly;
         NetTune.reset();
         tuneStarted = warmed ? warmStart : getTimer();
         peers = warmed ? warmPeers : {};
         peerCount = warmed ? warmCount : 0;
         changes = [];
         confirmed = -1;
         passT = -1;
         ownT = -1;
         skipLogged = false;
         Desync.reset();
         TrainingSync.reset();
         shift = 0;
         selfFrames = 0;
         runsBots = false;
         botController = 0;
         botsKnown = false;
         botsTakenAt = -1;
         botChanges = {};
         botLast = {};
         botSampled = {};
         botStates = {};
         historyLine = "";
         historyFrames = 0;
         handBackT = -1;
         handBackSent = 0;
         ownSampledBack = false;
         backJump = -1;
         rejoinedSelf = Rejoin.active;
         selfPending = null;
         selfForced = selfCompared = selfDiffered = 0;
         selfByPlayer = {};
         selfLogged = 0;
         lastBits = 0;
         stallStart = -1;
         recentWaits = [];
         lastFrameAt = 0;
         localHitchAt = lastRaise = -100000;
         startDelay = delay;
         stalls = stalledMs = sentCount = receivedCount = 0;
         waitLog = [];
         ModCheck.refresh();
         modsSent = lastModsSent = modsHeard = 0;
         modsDiffer = null;
         if(!openSocket())
         {
            return;
         }
         var members:Object = core.var_6244.var_1751;
         var inRoom:Object = {};
         for(var i:int = 0; i < int(members.length); i++)
         {
            var id:uint = uint(members[i].var_14656);
            if(id != 0 && id != localId)
            {
               inRoom[id] = true;
               if(peers[id] == null)
               {
                  peers[id] = newPeer(id);
                  peerCount++;
               }
               try
               {
                  peers[id].name = String(members[i].var_6307.var_14792 || peers[id].name);
               }
               catch(e:Error)
               {
               }
            }
         }
         if(warmed)
         {
            for(var pid:String in peers)
            {
               if(!inRoom[pid])
               {
                  delete peers[pid];
                  peerCount--;
               }
            }
            var measured:Array = [];
            var answered:Boolean = false;
            for each(var wp:Object in peers)
            {
               wp.heard = getTimer();
               answered = answered || wp.samples.length + wp.relaySamples.length > 0;
               measured.push(wp.name + " " + int(wp.samples.length) + " direct / " + int(wp.relaySamples.length) +
                  " relay" + (wp.turnIp != null ? " / " + int(wp.turnSamples.length) + " Cloudflare" : "") + " round trips");
            }
            PrivateServer.log("P2P room " + room + ": pinged for " + warmedFor + " ms before the start (" +
               measured.join(", ") + ")");
            if(!answered)
            {
               tuneStarted = getTimer();
            }
         }
         active = true;
         pingTimer = new Timer(100);
         pingTimer.addEventListener(TimerEvent.TIMER,onPingTick);
         pingTimer.start();
         var addresses:Array = sendHello(core);
         PrivateServer.log("P2P room " + room + ": " + peerCount + " remote player(s), input delay " + delay + " ms" + (PrivateServer.p2pDelaySet ? " (p2p_delay_ms in bh-server.json)" : "") + ", UDP " +
            (pipe != null ? pipe.name : socket.localPort) + ", addresses " + addresses.join(" ") + (relayOnly ? ", relay only" : ""));
         PrivateServer.hold(true);
      }

      private static function newPeer(id:uint) : Object
      {
         return {"id":id,"port":0,"addresses":[],"direct":null,"directPort":0,"rtt":-1,"heard":getTimer(),
            "confirmed":0,"ack":-1,"applied":-1,"pending":[],"state":null,"gone":false,"name":"player " + id,
            "botPending":{},"botApplied":{},"samples":[],"relaySamples":[],"preferRelay":false,"pathChosen":false,
            "turnIp":null,"turnPort":0,"turnSamples":[],"turnChosen":false,"viaTurn":false};
      }

      private static function usesDirect(peer:Object) : Boolean
      {
         return pipe != null || peer.direct != null && !relayOnly && !peer.preferRelay;
      }

      private static const SAMPLES:int = 16;

      private static function addSample(list:Array, rtt:int) : void
      {
         list.push(rtt);
         if(list.length > SAMPLES)
         {
            list.shift();
         }
      }

      private static function planRtt(list:Array) : int
      {
         if(list == null || list.length < 3)
         {
            return -1;
         }
         var sorted:Array = list.concat().sort(Array.NUMERIC);
         return int(sorted[Math.min(sorted.length - 1,int(Math.ceil(sorted.length * 0.9)) - 1)]);
      }

      private static function median(list:Array) : int
      {
         var sorted:Array = list.concat().sort(Array.NUMERIC);
         return int(sorted[int(sorted.length / 2)]);
      }

      private static function choosePath(peer:Object) : void
      {
         if(peer.pathChosen || peer.direct == null || relayOnly || peer.samples.length < 5 || peer.relaySamples.length < 5)
         {
            return;
         }
         peer.pathChosen = true;
         var d:int = median(peer.samples);
         var r:int = median(peer.relaySamples);
         peer.preferRelay = r + 10 < d;
         PrivateServer.log("P2P room " + room + ": " + peer.name + " " + (peer.preferRelay ? "through the relay" : "direct") +
            " (round trip " + d + " ms direct, " + r + " ms through the relay)");
      }

      private static function chooseRelay(peer:Object) : void
      {
         if(peer.turnChosen || peer.turnIp == null || peer.turnSamples.length < 5 ||
            peer.relaySamples.length < 5 && peer.turnSamples.length < 10)
         {
            return;
         }
         peer.turnChosen = true;
         var t:int = median(peer.turnSamples);
         var r:int = peer.relaySamples.length > 0 ? median(peer.relaySamples) : -1;
         peer.viaTurn = r < 0 || t + 10 < r || PrivateServer.p2pTurnAlways;
         if(peer.viaTurn)
         {
            peer.relaySamples = peer.turnSamples.concat();
            peer.relayRtt = peer.turnRtt;
            peer.lastRelayRtt = peer.lastTurnRtt;
            peer.sentRelay = peer.sentTurn;
            peer.answeredRelay = peer.answeredTurn;
         }
         PrivateServer.log("P2P room " + room + ": " + peer.name + "'s relay: " + (peer.viaTurn ? "Cloudflare" : "the server's") +
            " (round trip " + t + " ms through Cloudflare, " + (r >= 0 ? r + " ms" : "no answer") + " through the server's relay)");
      }

      private static function dropTurn(peer:Object) : void
      {
         if(peer.viaTurn)
         {
            peer.relaySamples = [];
            peer.relayRtt = null;
            peer.lastRelayRtt = null;
            peer.sentRelay = peer.answeredRelay = 0;
         }
         peer.turnIp = null;
         peer.turnPort = 0;
         peer.turnSamples = [];
         peer.turnRtt = null;
         peer.turnChosen = false;
         peer.viaTurn = false;
      }

      private static function sendTurn(peer:Object, body:ByteArray) : Boolean
      {
         return turn != null && peer.turnIp != null && turn.send(peer.turnIp,peer.turnPort,body);
      }

      private static function onTurnOffer(packet:Object) : void
      {
         var offerRoom:uint = packet.readUint();
         var host:String = packet.readString();
         var ports:Array = [];
         var n:uint = packet.readUint();
         for(var i:uint = 0; i < n; i++)
         {
            var port:int = int(packet.readUint());
            if(ports.length < 8)
            {
               ports.push(port);
            }
         }
         var username:String = packet.readString();
         var credential:String = packet.readString();
         var expires:uint = packet.readUint();
         if(!PrivateServer.p2pTurn || pipe != null || socket == null)
         {
            PrivateServer.log("P2P room " + offerRoom + ": Cloudflare relay offered, not used (" + (!PrivateServer.p2pTurn ?
               "p2p_turn false in bh-server.json" : "no UDP socket") + ")");
            return;
         }
         var now:int = getTimer();
         if(offerRoom != turnRoom && turn != null)
         {
            turn.retirePeers();
         }
         turnRoom = offerRoom;
         if(turn != null && turn.sameLogin(host,ports,username,credential) && (turn.ready || turn.state == "allocating"))
         {
            if(turn.ready)
            {
               sendTurnAddress(offerRoom,turn.relayedIp,turn.relayedPort);
            }
            return;
         }
         if(turn != null)
         {
            turn.close(now);
         }
         var client:TurnClient = new TurnClient(function(bytes:ByteArray, ip:String, to:int):void
         {
            if(socket != null)
            {
               socket.send(bytes,0,0,ip,to);
            }
         },host,ports,username,credential,expires);
         turn = client;
         client.log = function(line:String):void
         {
            PrivateServer.log("P2P " + line);
         };
         client.onReady = function(c:TurnClient):void
         {
            if(turn === client)
            {
               sendTurnAddress(turnRoom,c.relayedIp,c.relayedPort);
            }
         };
         client.onFailed = function(why:String):void
         {
            if(turn === client)
            {
               sendTurnAddress(turnRoom,"",0);
               for each(var p:Object in peers)
               {
                  p.viaTurn = false;
               }
            }
         };
         client.onData = function(ip:String, from:int, data:ByteArray):void
         {
            if(turn === client)
            {
               received(data,null,0,true);
            }
         };
         client.start(now);
         if(turnTimer == null)
         {
            turnTimer = new Timer(100);
            turnTimer.addEventListener(TimerEvent.TIMER,function(e:TimerEvent):void
            {
               if(turn != null)
               {
                  turn.tick(getTimer());
               }
            });
            turnTimer.start();
         }
      }

      private static function sendTurnAddress(r:uint, ip:String, port:int) : void
      {
         try
         {
            var p:NetPacket = new NetPacket(TURN_ADDRESS);
            p.writeUint(r);
            p.writeString(ip || "");
            p.writeUint(port);
            Object(GameApp.mainInstance).var_13259.sendToServer(p);
            p.method_839();
         }
         catch(e:Error)
         {
            PrivateServer.log("P2P: could not send the Cloudflare relay address: " + e.message);
         }
      }

      private static function onTurnPeers(packet:Object) : void
      {
         var peersRoom:uint = packet.readUint();
         var n:uint = packet.readUint();
         var listed:Object = {};
         var now:int = getTimer();
         var got:Array = [];
         for(var i:uint = 0; i < n; i++)
         {
            var id:uint = packet.readUint();
            var ip:String = packet.readString();
            var port:int = int(packet.readUint());
            if(peersRoom != room || id == localId || turn == null)
            {
               continue;
            }
            listed[id] = true;
            var peer:Object = peers[id];
            if(peer == null)
            {
               peer = peers[id] = newPeer(id);
               peerCount++;
            }
            if(peer.turnIp != ip || int(peer.turnPort) != port)
            {
               if(peer.turnIp != null)
               {
                  turn.retirePeer(peer.turnIp,peer.turnPort);
               }
               dropTurn(peer);
               peer.turnIp = ip;
               peer.turnPort = port;
            }
            turn.addPeer(ip,port,now);
            got.push(peer.name);
         }
         if(peersRoom != room || turn == null)
         {
            return;
         }
         for(var pid:String in peers)
         {
            var gone:Object = peers[pid];
            if(!listed[pid] && gone.turnIp != null)
            {
               turn.retirePeer(gone.turnIp,gone.turnPort);
               dropTurn(gone);
               PrivateServer.log("P2P room " + room + ": " + gone.name + " has no Cloudflare relay address now");
            }
         }
         if(got.length > 0)
         {
            PrivateServer.log("P2P room " + room + ": Cloudflare relay addresses of " + got.join(", "));
         }
      }

      private static function end(why:String, abrupt:Boolean = true) : void
      {
         if(!active)
         {
            return;
         }
         active = false;
         NetTune.hide();
         PrivateServer.hold(false);
         SimRandom.stop();
         Rejoin.end(why);
         Rejoin.handedBackAt = -1;

         var t0:int = getTimer();
         var steps:Array = [];
         Modal.close(LOST_TITLE);
         SpectateFeed.hostEnd(abrupt);
         steps.push("spectate " + (getTimer() - t0));
         if(pingTimer != null)
         {
            pingTimer.stop();
            pingTimer = null;
         }
         for each(var peer:Object in peers)
         {
            sendTo(peer,datagram(BYE));
         }
         steps.push("byes " + (getTimer() - t0));
         var paths:Array = [];
         for each(peer in peers)
         {
            paths.push(peer.name + ": " + (usesDirect(peer) ? "direct " + peer.direct + ":" + peer.directPort :
               (peer.viaTurn ? "Cloudflare relay" : "relay") +
               (peer.relayRtt != null ? ", " + peer.relayRtt + " ms best round trip through it" : "")) +
               (!peer.viaTurn && peer.turnRtt != null ? ", " + peer.turnRtt + " ms best through Cloudflare" : "") +
               (peer.rtt >= 0 ? ", " + peer.rtt + " ms best round trip" : ""));
         }
         PrivateServer.log("P2P room " + room + " ended (" + why + "): " + (rollback ? "rollback, " + rollbacks + " rollbacks (" + merged + " late inputs merged into a later one, " + samePredicted + " late but as predicted, " +
            resimulated + " steps simulated again, input histories " + historyLine + ", " + Desync.summary() + ", " + Desync.cost() + ", " + (TrainingSync.applied + TrainingSync.lateCount + TrainingSync.pausedFrames > 0 ? TrainingSync.summary() + ", " : "") + selfCheckSummary() + ", " + SimRandom.summary() + ", " + CheckpointExtras.summary() + ", deepest " + deepest + " ms, clock slowed " + int(syncedMs) + " ms to meet the others, " +
            (PrivateServer.p2pSmoothing ? Smoothing.corrections + " corrections smoothed over " + PrivateServer.p2pSmoothingMs +
            " ms, largest " + int(Smoothing.largest) + ", " + Smoothing.tooLarge + " too large (shown at once)" : "no smoothing") + "), " :
            "lockstep, ") + "input delay " + startDelay + (delay != startDelay ?
            " raised to " + delay : "") + " ms, " + stalls + " waits" + (waitLog.length > 0 ? " (" + waitLog.join(", ") + ")" : "") + ", " + stalledMs + " ms waited, mods " +
            (modsDiffer != null ? "differ (" + modsDiffer + ")" : modsHeard > 0 ? "the same" : "not checked") + ", " +
            sentCount + " datagrams sent, " + receivedCount + " received; " + paths.join("; "));
         Smoothing.stop();
         if(Desync.mismatches > 0)
         {
            Modal.show("Out of sync","This match went out of sync with the other player's game " + int(Desync.firstAt / 1000) +
               " s in (" + Desync.summary() + ")." + (modsDiffer != null ? " Your content mods differ (" + modsDiffer +
               "): use the same mods." : "") + " Details are in Documents" + String.fromCharCode(92) + Platform.dataFolder() +
               String.fromCharCode(92) + "bh-private.txt.");
         }
         try
         {
            if(rollback)
            {
               Object(GameApp.mainInstance).var_13259.var_10934 = false;
            }
         }
         catch(e:Error)
         {
         }
         try
         {
            var members:Object = Object(GameApp.mainInstance).var_13259.var_6244.var_1751;
            for(var i:int = 0; members != null && i < int(members.length); i++)
            {
               if(members[i] != null && uint(members[i].var_4125) == uint(-1))
               {
                  members[i].var_4125 = 0;
               }
            }
         }
         catch(e:Error)
         {
         }
         if(getTimer() - t0 > 100)
         {
            PrivateServer.log("P2P end took " + (getTimer() - t0) + " ms (ms since its start: " + steps.join(", ") + ")");
         }
      }

      private static function onPacket(packet:Object) : Boolean
      {
         if(packet != null && (packet.type == TURN_OFFER || packet.type == TURN_PEERS))
         {
            try
            {
               if(packet.type == TURN_OFFER)
               {
                  onTurnOffer(packet);
               }
               else
               {
                  onTurnPeers(packet);
               }
            }
            catch(e0:Error)
            {
               PrivateServer.log("P2P: could not read " + packet.type + ": " + e0.message);
            }
            return true;
         }
         if(packet == null || packet.type != P2P_PEERS)
         {
            return false;
         }
         try
         {
            relayPort = packet.readUint();
            tokenHi = packet.readUint();
            tokenLo = packet.readUint();
            var n:uint = packet.readUint();
            for(var i:uint = 0; i < n; i++)
            {
               var id:uint = packet.readUint();
               var port:uint = packet.readUint();
               var count:uint = packet.readUint();
               var addresses:Array = [];
               for(var j:uint = 0; j < count; j++)
               {
                  addresses.push(packet.readString());
               }
               var peer:Object = peers[id];
               if(peer == null)
               {
                  peer = peers[id] = newPeer(id);
                  peerCount++;
               }
               if(peer.port != 0 && peer.port != port)
               {
                  peer.direct = null;
                  peer.directPort = 0;
                  peer.rtt = -1;
               }
               peer.port = port;
               peer.addresses = addresses;
            }
            lastRegister = 0;
            PrivateServer.log("P2P room " + room + ": addresses of " + n + " player(s), relay on UDP " + relayPort);
            P2PChoice.asked(room,P2PChoice.readAsk(packet));
         }
         catch(e:Error)
         {
            PrivateServer.log("P2P: could not read 11012: " + e.message);
         }
         return true;
      }

      private static function onFrame(core:Object) : void
      {
         if(!active)
         {
            return;
         }
         var now:int = getTimer();
         var elapsed:int = lastFrameAt > 0 ? now - lastFrameAt : 0;
         if(lastFrameAt > 0 && now - lastFrameAt > 100)
         {
            localHitchAt = now;
         }
         lastFrameAt = now;
         core.var_5692 = delay;
         if(rollback && !timeStarted)
         {
            core.var_12659 = 0;
            core.var_13849 = 0;
            core.var_10934 = true;
            timeStarted = true;
            PrivateServer.log("P2P room " + room + ": match time started for rollback");
         }
         if(rollback)
         {
            keepPlayerCheckpoints(core);
            Smoothing.beforeSteps(core);
         }
         if(uint(core.var_5300) == 0)
         {
            return;
         }
         var start:Number = base(core);
         if(rollback && !OnlineTraining.active)
         {
            core.method_2838(uint(core.var_13849));
         }
         if(passT > confirmed && passT > ownT && confirmed >= 0 && !Rejoin.active)
         {
            if(!skipLogged)
            {
               skipLogged = true;
               PrivateServer.log("P2P room " + room + ": this PC's player not sampled from " + passT +
                  " ms (out of the match): its inputs confirmed unchanged from there");
            }
            confirmed = passT;
            sendInputs();
         }
         findStates(core);
         if(++historyFrames >= 180)
         {
            historyFrames = 0;
            noteHistories(core);
         }
         if(rollback)
         {
            var final:Number = Rejoin.active ? Rejoin.through : confirmed;
            if(heldLate != uint.MAX_VALUE)
            {
               final = Math.min(final,heldLate - start - 1);
            }
            var anyPeer:Boolean = false;
            for each(var fedPeer:Object in peers)
            {
               if(!fedPeer.gone)
               {
                  anyPeer = true;
                  final = Math.min(final,fedPeer.fed != null ? Number(fedPeer.fed) : -1);
               }
            }
            if(anyPeer && final >= 0)
            {
               Desync.collect(core,start,Math.min(start + final,Number(core.var_13849)));
            }
            if(selfPending != null)
            {
               selfCompare(core,start);
            }
         }
         var everyone:Number = confirmed;
         for each(var spPeer:Object in peers)
         {
            if(!spPeer.gone)
            {
               everyone = Math.min(everyone,spPeer.fed != null ? Number(spPeer.fed) : -1);
            }
         }
         if(!Rejoin.active)
         {
            SpectateFeed.hostFrame(core,start,everyone);
         }
         var horizon:Number = Number.MAX_VALUE;
         var waitingOn:Object = null;
         var simulated:uint = uint(core.var_13849);
         var late:uint = uint.MAX_VALUE;
         if(Rejoin.active)
         {
            late = Rejoin.frame(core,start);
            for each(var rjPeer:Object in peers)
            {
               if(Rejoin.through > Number(rjPeer.confirmed))
               {
                  rjPeer.confirmed = uint(Rejoin.through);
               }
               rjPeer.heard = now;
            }
            if(!rollback)
            {
               late = uint.MAX_VALUE;
            }
            if(Rejoin.caughtUpAt >= 0 && rollback)
            {
               handBack(core,start);
            }
         }
         if(handBackT >= 0)
         {
            helloBackFrame(core,start,now);
         }
         for each(var peer:Object in peers)
         {
            if(peer.state != null)
            {
               for each(var c:Object in peer.pending)
               {
                  var at:uint = uint(start + c.t);
                  var redo:Boolean = false;
                  if(rollback && at <= simulated && at < late)
                  {
                     redo = RemoteInput.bitsAt(peer.state,at) != uint(c.b);
                     if(!redo)
                     {
                        samePredicted++;
                     }
                  }
                  RemoteInput.feed(peer.state,at,c.b);
                  if(redo)
                  {
                     late = at;
                  }
               }
               if(peer.pending.length > 0)
               {
                  peer.pending.length = 0;
               }
               peer.fed = peer.confirmed;
            }
            for(var botKey:String in peer.botPending)
            {
               var botState:Object = botStates[uint(botKey)];
               if(botState == null)
               {
                  continue;
               }
               for each(var pc:Object in peer.botPending[botKey])
               {
                  if(runsBots && int(pc.t) > botsTakenAt)
                  {
                     continue;
                  }
                  var bat:uint = uint(start + pc.t);
                  var botRedo:Boolean = rollback && bat <= simulated && bat < late &&
                     RemoteInput.bitsAt(botState,bat) != uint(pc.b);
                  RemoteInput.feed(botState,bat,pc.b);
                  if(botRedo)
                  {
                     late = bat;
                  }
               }
               if(peer.botPending[botKey].length > 0)
               {
                  peer.botPending[botKey].length = 0;
               }
            }
            if(!peer.gone && peer.confirmed < horizon)
            {
               horizon = peer.confirmed;
               waitingOn = peer;
            }
         }
         if(rollback && elapsed > 0 && elapsed < 100)
         {
            syncClock(core,start,now,elapsed);
         }
         if(rollback && diagnosed < DIAGNOSE)
         {
            watchPositions(core);
         }
         var fresh:Boolean = late != uint.MAX_VALUE;
         if(heldLate != uint.MAX_VALUE)
         {
            late = uint(Math.min(late,heldLate));
            heldLate = uint.MAX_VALUE;
         }
         if(late != uint.MAX_VALUE && mergeRollbacks && rolledAt == simulated && !Rejoin.active && !OnlineTraining.active)
         {
            heldLate = late;
            late = uint.MAX_VALUE;
            if(fresh)
            {
               merged++;
            }
         }
         if(late != uint.MAX_VALUE)
         {
            rolledAt = simulated;
            core.method_4383(late);
            Smoothing.rollingBack();
            if(diagnosed < DIAGNOSE)
            {
               var back:uint = uint(core.var_7830);
               var found:Boolean = false;
               try
               {
                  found = core.var_13110.method_3072(int(back + 16)) != null;
               }
               catch(err:Error)
               {
               }
               pendingCheck = {"late":late - start,"at":simulated - start,"back":back - start,"found":found,"going":Boolean(core.var_14920)};
            }
            rollbacks++;
            var depth:uint = simulated - late + 16;
            resimulated += uint(depth / 16);
            if(depth > deepest)
            {
               deepest = depth;
            }
         }
         else if(rollback && selfCheck && heldLate == uint.MAX_VALUE && anyPeer && final >= 0 && ++selfFrames >= SELF_CHECK_EVERY)
         {
            selfFrames = 0;
            selfForce(core,start,Math.min(start + final,Number(core.var_13849)));
         }
         if(rollback && OnlineTraining.active)
         {
            var fedAll:Number = Number.MAX_VALUE;
            for each(var tsPeer:Object in peers)
            {
               if(!tsPeer.gone)
               {
                  fedAll = Math.min(fedAll,tsPeer.fed != null ? Number(tsPeer.fed) : -1);
               }
            }
            TrainingSync.frame(core,start,late,fedAll);
            findStates(core);
            start = base(core);
         }
         if(now - lastSend > 50)
         {
            sendInputs();
         }
         if(waitingOn == null)
         {
            return;
         }
         var limit:uint = uint(start + horizon + (rollback ? MAX_PREDICT : 0));
         var target:uint = rollback ? uint(core.var_12659) : uint(core.var_11938);
         if(target > limit)
         {
            var excess:uint = target - limit;
            if(rollback)
            {
               core.var_12659 = limit;
               holdCountdown(excess);
            }
            else
            {
               core.var_11938 = limit;
               core.var_171 = uint(core.var_171) + excess;
            }
            if(stallStart < 0)
            {
               stallStart = now;
               stallAt = int(target - start);
               stallLocal = now - localHitchAt <= 1500;
               stalls++;
               if(now - localHitchAt > 1500)
               {
                  recentWaits.push(now);
               }
               while(recentWaits.length > 0 && now - int(recentWaits[0]) > 3000)
               {
                  recentWaits.shift();
               }
               if(recentWaits.length >= 3)
               {
                  raiseDelay("3 waits in 3 s");
               }
            }
            else if(now - stallStart > 100 && recentWaits.length > 0 && now - localHitchAt > 1500)
            {
               recentWaits = [];
               raiseDelay("a wait over 100 ms");
            }
            if(now - int(waitingOn.heard) > GIVE_UP)
            {
               giveUp(waitingOn,uint(limit + 16));
            }
         }
         else if(stallStart >= 0)
         {
            stalledMs += uint(now - stallStart);
            if(waitLog.length < 8)
            {
               waitLog.push((stallAt / 1000).toFixed(1) + " s: " + (now - stallStart) + " ms" + (stallLocal ? " local" : ""));
            }
            stallStart = -1;
         }
      }

      private static function selfForce(core:Object, start:Number, cap:Number) : void
      {
         if(cap - 160 <= start)
         {
            return;
         }
         var from:uint = uint(Math.floor((cap - 160) / 16) * 16);
         if(TrainingSync.appliedAt + 96 > from)
         {
            return;
         }
         var taken:Array = [];
         for(var t:uint = from; t <= uint(cap); t += 16)
         {
            if((t / 16) % 5 != 1)
            {
               continue;
            }
            var h:Object = Desync.playersHash(core,t);
            if(h != null)
            {
               var copies:Array = [];
               for each(var b:ByteArray in h.states)
               {
                  var copy:ByteArray = new ByteArray();
                  copy.writeBytes(b,0,b.length);
                  copies.push(copy);
               }
               taken.push({"t":t,"parts":h.parts,"states":copies});
            }
         }
         if(taken.length == 0)
         {
            return;
         }
         var simulated:uint = uint(core.var_13849);
         core.method_4383(from);
         Smoothing.rollingBack();
         selfForced++;
         rollbacks++;
         resimulated += uint((simulated - from + 16) / 16);
         selfPending = taken;
      }

      private static function selfCompare(core:Object, start:Number) : void
      {
         var taken:Array = selfPending;
         selfPending = null;
         for each(var c:Object in taken)
         {
            var h:Object = Desync.playersHash(core,uint(c.t));
            if(h == null)
            {
               continue;
            }
            for(var i:int = 0; i < int(c.parts.length) && i < int(h.parts.length); i++)
            {
               selfCompared++;
               if(uint(c.parts[i]) == uint(h.parts[i]))
               {
                  continue;
               }
               selfDiffered++;
               selfByPlayer[i] = int(selfByPlayer[i]) + 1;
               if(selfLogged < 16)
               {
                  selfLogged++;
                  var player:Object = core.var_7050[i];
                  PrivateServer.log("P2P self-check: player " + i + " (ID " + player.var_14656 + ") differs after a forced rollback at " +
                     (Number(c.t) - start) + " ms: " + uint(c.parts[i]).toString(16) + " -> " + uint(h.parts[i]).toString(16) + " " +
                     Desync.describe(h.states[i]) + " " + byteDiff(c.states[i],h.states[i]) + " sections " + sections(player));
               }
            }
         }
      }

      private static function sections(player:Object) : String
      {
         try
         {
            var probe:Object = new class_362(player as class_123);
            var total:uint = probe.var_5133.length;
            var parts:Array = [["bot",function():void { probe.method_6317(player.var_7753); }],
               ["powers",function():void { probe.method_487(player.var_2000); }],
               ["input",function():void { probe.method_6917(player.var_10012); }],
               ["c560",function():void { probe.method_6773(player.var_11807.var_142); }],
               ["stats",function():void { probe.method_7658(player.var_3140); }],
               ["trail",function():void { probe.method_6206(player.var_4638); }]];
            var sizes:Array = [];
            var sum:uint = 0;
            for each(var part:Array in parts)
            {
               probe.var_5133 = new ByteArray();
               part[1]();
               sizes.push(part[0] + " " + probe.var_5133.length);
               sum += probe.var_5133.length;
            }
            return "[total " + total + ", fixed " + (total - sum - 15) + "+15 at the end; " + sizes.join(", ") + "]";
         }
         catch(e:Error)
         {
            return "[" + e.message + "]";
         }
         return "";
      }

      private static function noteHistories(core:Object) : void
      {
         var out:Array = [];
         for each(var p:Object in core.var_7050)
         {
            var h:Array = p.var_10012 != null ? p.var_10012.var_11813 as Array : null;
            var pressed:int = 0;
            for each(var e:Object in h)
            {
               if(uint(e.var_1212) != 0)
               {
                  pressed++;
               }
            }
            out.push("ID " + p.var_14656 + (p.var_8233 != null ? " (bot)" : "") + " " + (h != null ? h.length + "/" + pressed : "none"));
         }
         historyLine = out.join(" | ");
      }

      private static function byteDiff(a:ByteArray, b:ByteArray) : String
      {
         var out:Array = [];
         var n:int = Math.min(a.length,b.length);
         for(var k:int = 0; k < n && out.length < 12; k++)
         {
            if(a[k] != b[k])
            {
               out.push(k + ":" + a[k] + ">" + b[k]);
            }
         }
         return "(" + a.length + "/" + b.length + " bytes; " + out.join(" ") + ")";
      }

      public static function selfCheckSummary() : String
      {
         if(selfForced == 0)
         {
            return "no self-check";
         }
         var who:Array = [];
         for(var k:String in selfByPlayer)
         {
            who.push("player " + k + " x" + selfByPlayer[k]);
         }
         return "self-check: " + selfForced + " forced rollbacks, " + selfCompared + " player checkpoints compared, " +
            (selfDiffered == 0 ? "all the same" : selfDiffered + " DIFFERED (" + who.join(", ") + ")") +
            (Desync.unknownLayout > 0 ? ", " + Desync.unknownLayout + " hashed whole (layout not found)" : "");
      }

      private static function watchPositions(core:Object) : void
      {
         var t:uint = uint(core.var_13849);
         var report:Array = [];
         try
         {
            var players:Object = core.var_7050;
            for(var i:int = 0; i < int(players.length); i++)
            {
               var pl:Object = players[i];
               var id:uint = uint(pl.var_14656);
               var x:Number = Number(pl.method_338());
               var y:Number = Number(pl.method_4344());
               var last:Object = lastPos[id];
               if(last != null && t > uint(last.t))
               {
                  var perStep:Number = Math.sqrt((x - last.x) * (x - last.x) + (y - last.y) * (y - last.y)) / ((t - uint(last.t)) / 16);
                  if(pendingCheck != null)
                  {
                     report.push((id == localId ? "you" : "player " + id) + " moved " + perStep.toFixed(1) + " per step (usually " +
                        Number(usualStep[id] || 0).toFixed(1) + ")");
                  }
                  else
                  {
                     usualStep[id] = usualStep[id] == null ? perStep : Number(usualStep[id]) * 0.9 + perStep * 0.1;
                  }
               }
               lastPos[id] = {"x":x,"y":y,"t":t};
            }
         }
         catch(e:Error)
         {
            report.push("positions unavailable: " + e.message);
         }
         if(pendingCheck != null)
         {
            diagnosed++;
            var c:Object = pendingCheck;
            pendingCheck = null;
            PrivateServer.log("P2P rollback check " + diagnosed + ": an input for " + c.late + " ms arrived at " + c.at +
               " ms; back to " + c.back + " ms, checkpoint " + (c.found ? "found" : "MISSING") + (c.going ? "" : ", not started") +
               "; " + report.join(", "));
         }
      }

      private static function syncClock(core:Object, start:Number, now:int, elapsed:int) : void
      {
         var mine:Number = Number(uint(core.var_12659)) - start;
         var ahead:Number = 0;
         for each(var peer:Object in peers)
         {
            if(peer.gone || peer.theirNow == null)
            {
               continue;
            }
            var rtt:int = bestRtt(peer);
            var theirs:Number = Number(peer.theirNow) + (now - int(peer.theirNowAt)) + (rtt >= 0 ? rtt / 2 : 0);
            ahead = Math.max(ahead,mine - theirs);
         }
         if(ahead > 16)
         {
            var cut:Number = Math.min(ahead - 16,elapsed * 0.1);
            if(cut >= 1)
            {
               core.var_12659 = uint(core.var_12659) - uint(cut);
               syncedMs += uint(cut);
               holdCountdown(uint(cut));
            }
         }
      }

      private static function holdCountdown(ms:uint) : void
      {
         try
         {
            var c:Object = ScreenManager.var_1487;
            if(ms == 0 || c == null || uint(c.var_11955) == 0)
            {
               return;
            }
            c.var_11955 = uint(c.var_11955) + ms;
            if(uint(c.var_10330) != 0)
            {
               c.var_10330 = uint(c.var_10330) + ms;
            }
         }
         catch(e:Error)
         {
         }
      }

      private static function matchNow() : uint
      {
         try
         {
            var core:Object = Object(GameApp.mainInstance).var_13259;
            if(uint(core.var_5300) == 0)
            {
               return 0;
            }
            var start:Number = base(core);
            var t:uint = rollback ? uint(core.var_12659) : uint(core.var_11938);
            return t > start ? uint(t - start) : 0;
         }
         catch(e:Error)
         {
         }
         return 0;
      }

      private static function raiseDelay(why:String) : void
      {
         recentWaits = [];
         if(rollback || delay >= MAX_DELAY || getTimer() - lastRaise < 2000)
         {
            return;
         }
         lastRaise = getTimer();
         delay += 16;
         PrivateServer.log("P2P room " + room + ": input delay raised to " + delay + " ms (" + why + ")");
      }

      private static function giveUp(peer:Object, time:uint) : void
      {
         peer.gone = true;
         if(peer.state != null)
         {
            RemoteInput.feed(peer.state,time,0);
         }
         PrivateServer.log("P2P room " + room + ": nothing from " + peer.name + " for " + GIVE_UP / 1000 + " s; no longer waiting");
         Modal.show(LOST_TITLE,"Lost the connection to " + peer.name + ". Their legend will stand still.");
      }

      private static function findStates(core:Object) : void
      {
         var was:Boolean = runsBots;
         runsBots = true;
         for(var key:String in peers)
         {
            if(!peers[key].gone && !peers[key].rejoined &&
               (rejoinedSelf || (botRunnerHighest ? uint(key) > localId : uint(key) < localId)))
            {
               runsBots = false;
            }
         }
         if(botController != 0 && (botController == localId || peers[botController] != null && !peers[botController].gone))
         {
            runsBots = botController == localId;
         }
         var players:Object = core.var_7050;
         for(var i:int = 0; i < int(players.length); i++)
         {
            var player:Object = players[i];
            var peer:Object = peers[uint(player.var_14656)];
            if(peer != null && peer.state == null && player.var_10012 != null)
            {
               peer.state = player.var_10012;
            }
            if(player.var_8233 != null && player.var_10012 != null)
            {
               botStates[uint(player.var_11355)] = player.var_10012;
            }
         }
         if(runsBots && !was && botsKnown)
         {
            takeBots(core);
         }
         botsKnown = hasBotStates();
      }

      private static function hasBotStates() : Boolean
      {
         for(var k:String in botStates)
         {
            return true;
         }
         return false;
      }

      private static function keepPlayerCheckpoints(core:Object) : void
      {
         var players:Object = core.var_7050;
         for(var i:int = 0; i < int(players.length); i++)
         {
            var player:Object = players[i];
            if(player.var_7944 == null)
            {
               player.var_7944 = new class_361();
               player.var_9577 = new IntMap();
            }
         }
      }

      private static function onSampling(state:Object, time:uint) : Boolean
      {
         if(!active)
         {
            return false;
         }
         if(Rejoin.active)
         {
            return true;
         }
         if(state.var_594.var_8233 != null)
         {
            var core:Object = Object(GameApp.mainInstance).var_13259;
            if(runsBots && OnlineTraining.active && botSampled[uint(state.var_594.var_11355)] != null &&
               time - base(core) < Number(botSampled[uint(state.var_594.var_11355)]))
            {
               return true;
            }
            return !runsBots || OnlineTraining.active && TrainingSync.handoffBy(time,base(core));
         }
         if(uint(state.var_594.var_14656) != localId)
         {
            return true;
         }
         if(handBackT >= 0 && time - base(Object(GameApp.mainInstance).var_13259) < handBackT)
         {
            return true;
         }
         return rollback && OnlineTraining.active && confirmed >= 0 &&
            time - base(Object(GameApp.mainInstance).var_13259) < confirmed;
      }

      private static function onSampled(state:Object, time:uint, bits:uint) : void
      {
         if(active)
         {
            var passCore:Object = Object(GameApp.mainInstance).var_13259;
            var passStart:Number = base(passCore);
            if(uint(passCore.var_5300) != 0 && time >= passStart)
            {
               var passRel:int = int(time - passStart);
               if(passRel > passT)
               {
                  passT = passRel;
               }
               if(state.var_594.var_8233 == null && uint(state.var_594.var_14656) == localId)
               {
                  ownT = passRel;
               }
            }
         }
         if(active && runsBots && state.var_594.var_8233 != null)
         {
            botSampledAt(state,time,bits);
            return;
         }
         if(!active || uint(state.var_594.var_14656) != localId)
         {
            return;
         }
         var core:Object = Object(GameApp.mainInstance).var_13259;
         var start:Number = base(core);
         if(uint(core.var_5300) == 0 || time < start)
         {
            return;
         }
         var rel:int = int(time - start);
         if(rel < handBackT)
         {
            return;
         }
         if(handBackT >= 0 && !ownSampledBack)
         {
            ownSampledBack = true;
            PrivateServer.log("P2P room " + room + ": rejoin: this PC's first own sample since the hand-back at " + rel +
               " ms (bits " + bits + ", held " + lastBits + ")");
         }
         var changed:Boolean = bits != lastBits;
         if(changed)
         {
            lastBits = bits;
            changes.push({"t":rel,"b":bits});
         }
         if(rel > confirmed)
         {
            confirmed = rel;
         }
         if(changed || ++idleSteps >= IDLE_EVERY)
         {
            idleSteps = 0;
            sendInputs();
         }
      }

      public static var IDLE_EVERY:int = 3;
      private static var idleSteps:int = 0;

      private static function takeBots(core:Object) : void
      {
         var start:Number = base(core);
         var simulated:uint = uint(core.var_13849);
         botsTakenAt = int(simulated - start);
         for(var entKey:String in botStates)
         {
            var state:Object = botStates[entKey];
            var bits:uint = RemoteInput.bitsAt(state,simulated);
            state.var_13831 = bits;
            botLast[entKey] = bits;
            botSampled[entKey] = int(simulated - start);
            if(botChanges[entKey] == null)
            {
               botChanges[entKey] = [];
            }
         }
         PrivateServer.log("P2P room " + room + ": this PC runs the bots from " + (simulated + 16 - start) + " ms" +
            (botController != 0 ? " (player " + botController + " controls them)" : ""));
      }

      private static function botSampledAt(state:Object, time:uint, bits:uint) : void
      {
         var core:Object = Object(GameApp.mainInstance).var_13259;
         var start:Number = base(core);
         if(uint(core.var_5300) == 0 || time < start)
         {
            return;
         }
         var ent:uint = uint(state.var_594.var_11355);
         var rel:int = int(time - start);
         if(botChanges[ent] == null)
         {
            botChanges[ent] = [];
            botLast[ent] = 0;
         }
         if(bits != uint(botLast[ent]))
         {
            botLast[ent] = bits;
            botChanges[ent].push({"t":rel,"b":bits});
         }
         botSampled[ent] = rel;
         if(botController == localId && rel > confirmed)
         {
            confirmed = rel;
            sendInputs();
         }
      }

      private static function sendInputs() : void
      {
         lastSend = getTimer();
         if(Rejoin.active)
         {
            return;
         }
         if(confirmed < 0)
         {
            return;
         }
         var oldestAck:int = int.MAX_VALUE;
         var anyGone:Boolean = false;
         for each(var peer:Object in peers)
         {
            if(peer.gone || peer.backPending)
            {
               anyGone = true;
               continue;
            }
            oldestAck = Math.min(oldestAck,peer.ack);
            var body:ByteArray = datagramInto(inputBody,INPUT);
            var list:Array = sendList;
            list.length = 0;
            var through:int = confirmed;
            if(runsBots)
            {
               for each(var sampled:int in botSampled)
               {
                  through = Math.min(through,sampled);
               }
            }
            for each(var c:Object in changes)
            {
               if(c.t > peer.ack)
               {
                  if(list.length == MAX_CHANGES)
                  {
                     through = Math.min(through,int(c.t) - 16);
                     break;
                  }
                  list.push(c);
               }
            }
            var botLists:Array = [];
            if(runsBots || hasBotChanges())
            {
               for(var entKey:String in botChanges)
               {
                  var bl:Array = [];
                  for each(var bc:Object in botChanges[entKey])
                  {
                     if(bc.t > peer.ack)
                     {
                        if(bl.length == MAX_CHANGES)
                        {
                           through = Math.min(through,int(bc.t) - 16);
                           break;
                        }
                        bl.push(bc);
                     }
                  }
                  botLists.push([uint(entKey),bl]);
               }
            }
            body.writeUnsignedInt(uint(through));
            body.writeUnsignedInt(uint(int(peer.confirmed) < 0 ? 0 : peer.confirmed));
            body.writeUnsignedInt(matchNow());
            var sent:Array = sendSent;
            sent.length = 0;
            for each(c in list)
            {
               if(int(c.t) <= through)
               {
                  sent.push(c);
               }
            }
            body.writeShort(sent.length);
            for each(c in sent)
            {
               body.writeUnsignedInt(uint(c.t));
               body.writeShort(c.b);
            }
            Desync.write(body);
            body.writeByte(botLists.length);
            for each(var entry:Array in botLists)
            {
               var upTo:Array = [];
               for each(bc in entry[1])
               {
                  if(int(bc.t) <= through)
                  {
                     upTo.push(bc);
                  }
               }
               body.writeUnsignedInt(entry[0]);
               body.writeShort(upTo.length);
               for each(bc in upTo)
               {
                  body.writeUnsignedInt(uint(bc.t));
                  body.writeShort(bc.b);
               }
            }
            if(OnlineTraining.active)
            {
               TrainingSync.write(body,peers);
            }
            sendTo(peer,body);
         }
         if(anyGone)
         {
            oldestAck = Math.min(oldestAck,confirmed - KEEP_FOR_GONE);
         }
         while(changes.length > 1 && int(changes[0].t) <= oldestAck && int(changes[1].t) <= oldestAck)
         {
            changes.shift();
         }
         for each(var bcs:Array in botChanges)
         {
            while(bcs.length > 1 && int(bcs[0].t) <= oldestAck && int(bcs[1].t) <= oldestAck)
            {
               bcs.shift();
            }
         }
      }

      private static function hasBotChanges() : Boolean
      {
         for(var k:String in botChanges)
         {
            return true;
         }
         return false;
      }

      private static function datagram(type:uint) : ByteArray
      {
         return datagramInto(new ByteArray(),type);
      }

      private static function datagramInto(b:ByteArray, type:uint) : ByteArray
      {
         b.length = 0;
         b.endian = Endian.BIG_ENDIAN;
         b.writeShort(MAGIC);
         b.writeByte(type);
         b.writeUnsignedInt(room);
         b.writeUnsignedInt(localId);
         return b;
      }

      private static function sendTo(peer:Object, body:ByteArray, viaRelay:Boolean = false) : void
      {
         if(pipe != null)
         {
            try
            {
               pipe.send(uint(peer.id),body);
               sentCount++;
            }
            catch(e0:Error)
            {
            }
            return;
         }
         if(socket == null)
         {
            return;
         }
         try
         {
            if(usesDirect(peer) && !viaRelay)
            {
               socket.send(body,0,0,peer.direct,peer.directPort);
            }
            else if(peer.viaTurn && sendTurn(peer,body))
            {
            }
            else if(relayPort != 0)
            {
               var wrapped:ByteArray = relayBody;
               wrapped.length = 0;
               wrapped.endian = Endian.BIG_ENDIAN;
               wrapped.writeShort(MAGIC);
               wrapped.writeByte(RELAY);
               wrapped.writeUnsignedInt(tokenHi);
               wrapped.writeUnsignedInt(tokenLo);
               wrapped.writeUnsignedInt(peer.id);
               wrapped.writeBytes(body);
               socket.send(wrapped,0,0,relayHost(),relayPort);
            }
            else
            {
               return;
            }
            sentCount++;
         }
         catch(e:Error)
         {
         }
      }

      private static function sendRegister() : void
      {
         if(socket == null || relayPort == 0)
         {
            return;
         }
         try
         {
            var b:ByteArray = new ByteArray();
            b.writeShort(MAGIC);
            b.writeByte(REGISTER);
            b.writeUnsignedInt(tokenHi);
            b.writeUnsignedInt(tokenLo);
            socket.send(b,0,0,relayHost(),relayPort);
         }
         catch(e:Error)
         {
         }
      }

      private static function relayHost() : String
      {
         return PrivateServer.host == "localhost" ? "127.0.0.1" : PrivateServer.host;
      }

      private static function fromRelay(address:String, port:int) : Boolean
      {
         if(relayPort == 0 || port != int(relayPort))
         {
            return false;
         }
         var host:String = relayHost();
         return address == host || !/^[0-9.]+$|:/.test(host);
      }

      private static function onPingTick(e:TimerEvent) : void
      {
         if(!active && !warming)
         {
            return;
         }
         var now:int = getTimer();
         if(warming && now - warmStart > WARM_MS)
         {
            PrivateServer.log("P2P room " + room + ": the found match didn't start; stopped pinging");
            stopWarm();
            return;
         }
         if(now - lastRegister > 2000)
         {
            lastRegister = now;
            sendRegister();
         }
         if(now - lastPing >= 250)
         {
            lastPing = now;
            if(!relayOnly)
            {
               pingCandidates(now);
            }
            pingRelayed(now);
         }
         if(warming)
         {
            return;
         }
         if(modsSent < 12 && now - lastModsSent >= 250)
         {
            lastModsSent = now;
            modsSent++;
            for each(var peer:Object in peers)
            {
               if(!peer.gone)
               {
                  var mods:ByteArray = datagram(MODS);
                  ModCheck.write(mods);
                  sendTo(peer,mods);
               }
            }
         }
         tune(now);
         NetTune.tick();
      }

      private static function tune(now:int) : void
      {
         if(NetTune.decided)
         {
            return;
         }
         var worst:Object = null;
         var ready:Boolean = true;
         var direct:Boolean = false;
         var relayed:Boolean = false;
         for each(var peer:Object in peers)
         {
            if(peer.gone)
            {
               continue;
            }
            var viaDirect:Boolean = usesDirect(peer);
            var m:Object = viaDirect ? NetTune.measure(peer.samples,int(peer.sentDirect || 0),int(peer.answeredDirect || 0)) :
               NetTune.measure(peer.relaySamples,int(peer.sentRelay || 0),int(peer.answeredRelay || 0));
            if(m == null || m.samples < NetTune.TUNE_SAMPLES || (peer.direct != null && !relayOnly && !peer.pathChosen))
            {
               ready = false;
            }
            if(m != null && (worst == null || m.rtt + m.jitter > worst.rtt + worst.jitter))
            {
               worst = m;
            }
            direct = direct || viaDirect;
            relayed = relayed || !viaDirect;
         }
         var late:Boolean = now - tuneStarted >= NetTune.TUNE_MS;
         if(worst == null || (!ready && !late))
         {
            chooseDelay();
            if(worst == null && now - tuneStarted > NetTune.TUNE_MS * 2)
            {
               NetTune.decided = true;
               PrivateServer.log("P2P room " + room + ": no round trips to tune the network settings on");
            }
            return;
         }
         NetTune.decided = true;
         var fixed:Boolean = PrivateServer.p2pDelaySet || !rollback;
         if(!fixed)
         {
            var d:uint = NetTune.delayFor(worst,MAX_AUTO_DELAY,HIGH_PING_DELAY);
            if(d > delay)
            {
               delay = d;
               delayFromPing = true;
            }
         }
         var smoothing:Boolean = rollback && PrivateServer.p2pSmoothing;
         if(smoothing)
         {
            NetTune.smoothingMs = uint(Math.max(NetTune.smoothingMs,NetTune.smoothingFor(worst)));
            Smoothing.setMs(NetTune.smoothingMs);
         }
         var relayName:String = "the relay";
         for each(peer in peers)
         {
            if(!peer.gone && !usesDirect(peer) && peer.viaTurn)
            {
               relayName = "Cloudflare's relay";
            }
         }
         var path:String = direct && relayed ? "direct and through " + relayName : (direct ? "direct" : "through " + relayName);
         var text:Array = NetTune.describe(worst,path,delay,fixed,rollback,smoothing,NetTune.smoothingMs);
         PrivateServer.log("P2P room " + room + ": network settings for the match: " + text.join("; ") + " (" + worst.samples +
            " round trips, 90th percentile " + worst.p90 + " ms)");
         NetTune.show(text);
      }

      private static function agreeSmoothing(peer:Object, wanted:uint) : void
      {
         if(wanted <= NetTune.smoothingMs || !(rollback && PrivateServer.p2pSmoothing) || wanted > 200)
         {
            return;
         }
         NetTune.smoothingMs = wanted;
         Smoothing.setMs(wanted);
         PrivateServer.log("P2P room " + room + ": smoothing raised to " + wanted + " ms to match " + peer.name + "'s");
         NetTune.update(2,"Rollback on, smoothing " + wanted + " ms (matched to " + peer.name + ")");
      }

      private static function pingRelayed(now:int) : void
      {
         for each(var peer:Object in peers)
         {
            if(peer.gone || (usesDirect(peer) && peer.pathChosen) || now - int(peer.relayPinged || 0) < NetTune.interval)
            {
               continue;
            }
            peer.relayPinged = now;
            var b:ByteArray = datagram(PING);
            b.writeUnsignedInt(uint(now));
            b.writeShort(delay);
            b.writeShort(NetTune.smoothingMs);
            sendTo(peer,b,true);
            peer.sentRelay = int(peer.sentRelay || 0) + 1;
            if(!peer.turnChosen && sendTurn(peer,b))
            {
               peer.sentTurn = int(peer.sentTurn || 0) + 1;
            }
            choosePath(peer);
            chooseRelay(peer);
         }
      }

      private static function bestRtt(peer:Object) : int
      {
         if(usesDirect(peer))
         {
            return int(peer.rtt);
         }
         return peer.relayRtt != null ? int(peer.relayRtt) : -1;
      }

      public static function relayPingOf(id:uint) : int
      {
         var peer:Object = peers != null ? peers[id] : null;
         if(peer == null)
         {
            return -1;
         }
         var planned:int = planRtt(peer.relaySamples);
         var viaTurn:int = peer.turnChosen ? -1 : planRtt(peer.turnSamples);
         if(viaTurn >= 0 && (planned < 0 || viaTurn < planned))
         {
            return viaTurn;
         }
         return planned >= 0 ? planned : (peer.relayRtt != null ? int(peer.relayRtt) : -1);
      }

      private static function pathRtt(peer:Object) : int
      {
         if(usesDirect(peer))
         {
            var planned:int = planRtt(peer.samples);
            return planned >= 0 ? planned : int(peer.rtt);
         }
         planned = planRtt(peer.relaySamples);
         return planned >= 0 ? planned : (peer.relayRtt != null ? int(peer.relayRtt) : -1);
      }

      private static function agreeDelay(peer:Object, wanted:uint) : void
      {
         if(PrivateServer.p2pDelaySet || wanted <= delay)
         {
            return;
         }
         wanted = uint(Math.min(wanted,rollback ? HIGH_PING_DELAY : MAX_DELAY));
         if(wanted > delay)
         {
            PrivateServer.log("P2P room " + room + ": input delay raised to " + wanted + " ms to match " + peer.name + "'s");
            delay = wanted;
            NetTune.update(1,"Input delay " + wanted + " ms (matched to " + peer.name + ")");
         }
      }

      private static function chooseDelay() : void
      {
         if(PrivateServer.p2pDelaySet)
         {
            return;
         }
         var worst:int = -1;
         for each(var peer:Object in peers)
         {
            if(!peer.gone)
            {
               worst = Math.max(worst,pathRtt(peer));
            }
         }
         if(worst < 0)
         {
            return;
         }
         var cap:uint = rollback ? MAX_AUTO_DELAY : MAX_DELAY;
         if(rollback && worst > 200)
         {
            cap = uint(Math.min(HIGH_PING_DELAY,Math.max(MAX_AUTO_DELAY,Math.ceil(worst / 4 / 16) * 16)));
         }
         var wanted:uint = uint(Math.min(cap,Math.max(32,Math.ceil((worst / 2 + 8) / 16) * 16)));
         if(wanted > delay)
         {
            PrivateServer.log("P2P room " + room + ": input delay " + (delayFromPing ? "raised" : "set") + " to " + wanted +
               " ms for a " + worst + " ms round trip");
            delay = wanted;
            delayFromPing = true;
         }
      }

      private static function pingCandidates(now:int) : void
      {
         if(socket == null && pipe == null)
         {
            return;
         }
         for each(var peer:Object in peers)
         {
            if(peer.port == 0 && pipe == null || peer.gone)
            {
               continue;
            }
            if(peer.direct != null || pipe != null)
            {
               if(now - int(peer.pinged || 0) >= NetTune.interval)
               {
                  peer.pinged = now;
                  try
                  {
                     var p:ByteArray = datagram(PING);
                     p.writeUnsignedInt(uint(now));
                     p.writeShort(delay);
                     p.writeShort(NetTune.smoothingMs);
                     if(pipe != null)
                     {
                        sendTo(peer,p);
                     }
                     else
                     {
                        socket.send(p,0,0,peer.direct,peer.directPort);
                     }
                     peer.sentDirect = int(peer.sentDirect || 0) + 1;
                  }
                  catch(e:Error)
                  {
                  }
               }
               continue;
            }
            for each(var address:String in peer.addresses)
            {
               try
               {
                  var b:ByteArray = datagram(PING);
                  b.writeUnsignedInt(uint(now));
                  socket.send(b,0,0,address,peer.port);
               }
               catch(e:Error)
               {
               }
            }
         }
      }

      private static function onDatagram(e:DatagramSocketDataEvent) : void
      {
         if(turn != null && turn.owns(e.srcAddress,e.srcPort) && turn.received(e.data,e.srcAddress,e.srcPort,getTimer()))
         {
            return;
         }
         received(e.data,e.srcAddress,e.srcPort);
      }

      public static function pipeReceived(b:ByteArray) : void
      {
         received(b,null,0);
      }

      private static function received(b:ByteArray, srcAddress:String, srcPort:int, viaTurn:Boolean = false) : void
      {
         try
         {
            if(!(active || warming) || b.length < 11 || b.readUnsignedShort() != MAGIC)
            {
               return;
            }
            var type:uint = b.readUnsignedByte();
            if(warming && type != PING && type != PONG)
            {
               return;
            }
            var fromRoom:uint = b.readUnsignedInt();
            var from:uint = b.readUnsignedInt();
            var peer:Object = peers[from];
            if(fromRoom != room || peer == null)
            {
               return;
            }
            receivedCount++;
            peer.heard = getTimer();
            var viaRelay:Boolean = !viaTurn && fromRelay(srcAddress,srcPort);
            if(type == PING)
            {
               var pong:ByteArray = datagram(PONG);
               pong.writeUnsignedInt(b.readUnsignedInt());
               if(b.bytesAvailable >= 2 && !warming)
               {
                  agreeDelay(peer,b.readUnsignedShort());
               }
               if(b.bytesAvailable >= 2 && !warming)
               {
                  agreeSmoothing(peer,b.readUnsignedShort());
               }
               if(viaTurn)
               {
                  if(!sendTurn(peer,pong))
                  {
                     sendTo(peer,pong,true);
                  }
               }
               else if(viaRelay)
               {
                  sendTo(peer,pong,true);
               }
               else if(pipe != null)
               {
                  sendTo(peer,pong);
               }
               else if(!relayOnly)
               {
                  socket.send(pong,0,0,srcAddress,srcPort);
               }
            }
            else if(type == PONG && viaTurn)
            {
               var turned:int = int(uint(getTimer()) - b.readUnsignedInt());
               if(turned >= 0)
               {
                  peer.lastTurnRtt = turned;
                  addSample(peer.turnSamples,turned);
                  peer.answeredTurn = int(peer.answeredTurn || 0) + 1;
                  if(peer.turnRtt == null || turned < int(peer.turnRtt))
                  {
                     peer.turnRtt = turned;
                  }
                  if(peer.viaTurn)
                  {
                     peer.lastRelayRtt = turned;
                     addSample(peer.relaySamples,turned);
                     peer.answeredRelay = int(peer.answeredRelay || 0) + 1;
                     if(peer.relayRtt == null || turned < int(peer.relayRtt))
                     {
                        peer.relayRtt = turned;
                     }
                  }
               }
               chooseRelay(peer);
            }
            else if(type == PONG && viaRelay)
            {
               var relayed:int = int(uint(getTimer()) - b.readUnsignedInt());
               if(relayed >= 0)
               {
                  peer.lastRelayRtt = relayed;
                  addSample(peer.relaySamples,relayed);
                  peer.answeredRelay = int(peer.answeredRelay || 0) + 1;
               }
               if(relayed >= 0 && (peer.relayRtt == null || relayed < int(peer.relayRtt)))
               {
                  peer.relayRtt = relayed;
               }
            }
            else if(type == PONG && !relayOnly)
            {
               var rtt:int = int(uint(getTimer()) - b.readUnsignedInt());
               if(peer.direct == null && pipe == null)
               {
                  peer.direct = srcAddress;
                  peer.directPort = srcPort;
                  PrivateServer.log("P2P room " + room + ": direct path to " + peer.name + " at " + srcAddress + ":" +
                     srcPort);
               }
               else if(rtt >= 0)
               {
                  peer.lastRtt = rtt;
                  addSample(peer.samples,rtt);
                  peer.answeredDirect = int(peer.answeredDirect || 0) + 1;
                  choosePath(peer);
                  if(peer.rtt < 0 || rtt < int(peer.rtt))
                  {
                     peer.rtt = rtt;
                  }
               }
            }
            else if(type == MODS)
            {
               if(!peer.modsSeen)
               {
                  peer.modsSeen = true;
                  modsHeard++;
                  var differ:String = ModCheck.compare(b);
                  if(differ != null && modsDiffer == null)
                  {
                     modsDiffer = peer.name + ": " + differ;
                  }
                  PrivateServer.log("P2P room " + room + ": " + (differ == null ? "same content mods as " + peer.name + " (" +
                     ModCheck.count + ")" : "content mods differ from " + peer.name + "'s (" + differ + ")"));
               }
            }
            else if(type == INPUT)
            {
               var through:int = int(b.readUnsignedInt());
               var ack:int = int(b.readUnsignedInt());
               peer.theirNow = b.readUnsignedInt();
               peer.theirNowAt = getTimer();
               var n:int = b.readUnsignedShort();
               if(ack > peer.ack)
               {
                  peer.ack = ack;
               }
               if(peer.backPending && ack >= handBackT - 16)
               {
                  peer.backPending = false;
                  var est:Number = Number(peer.theirNow) + (int(peer.rtt) > 0 ? int(peer.rtt) / 2 : 0);
                  backJump = Math.max(backJump,est);
                  PrivateServer.log("P2P room " + room + ": " + peer.name + " took this PC back at " + handBackT +
                     " ms (their match time " + peer.theirNow + " ms)");
               }
               var first:uint = b.position;
               var applied:int = int(peer.applied);
               if(n > 0 && b.bytesAvailable >= n * 6)
               {
                  b.position = first + (n - 1) * 6;
                  var newest:int = int(b.readUnsignedInt());
                  b.position = first;
                  if(newest <= applied)
                  {
                     b.position = first + n * 6;
                     n = 0;
                  }
               }
               for(var i:int = 0; i < n; i++)
               {
                  var t:int = int(b.readUnsignedInt());
                  var bits:uint = b.readUnsignedShort();
                  if(t > applied)
                  {
                     applied = t;
                     peer.pending.push({"t":t,"b":bits});
                  }
               }
               peer.applied = applied;
               if(through > int(peer.confirmed))
               {
                  peer.confirmed = through;
               }
               Desync.read(peer.name,b);
               if(b.bytesAvailable >= 1)
               {
                  var botCount:int = b.readUnsignedByte();
                  for(var bi:int = 0; bi < botCount && b.bytesAvailable >= 6; bi++)
                  {
                     var ent:uint = b.readUnsignedInt();
                     var bn:int = b.readUnsignedShort();
                     var botApplied:int = peer.botApplied[ent] != null ? int(peer.botApplied[ent]) : -1;
                     if(peer.botPending[ent] == null)
                     {
                        peer.botPending[ent] = [];
                     }
                     for(var bj:int = 0; bj < bn && b.bytesAvailable >= 6; bj++)
                     {
                        var bt:int = int(b.readUnsignedInt());
                        var bb:uint = b.readUnsignedShort();
                        if(bt > botApplied)
                        {
                           botApplied = bt;
                           peer.botPending[ent].push({"t":bt,"b":bb});
                        }
                     }
                     peer.botApplied[ent] = botApplied;
                  }
                  TrainingSync.read(b);
               }
            }
            else if(type == HELLO_BACK)
            {
               takeBack(peer,b);
            }
            else if(type == BYE && !peer.gone)
            {
               peer.gone = true;
               PrivateServer.log("P2P room " + room + ": " + peer.name + " left the match");
               Modal.show("Player left",peer.name + " left the match.");
            }
         }
         catch(err:Error)
         {
         }
      }

      private static function handBack(core:Object, start:Number) : void
      {
         var t:int = int(Math.ceil((Rejoin.through + 2 * delay) / 16)) * 16;
         var own:Object = null;
         for each(var p:Object in core.var_7050)
         {
            if(uint(p.var_14656) == localId && p.var_8233 == null)
            {
               own = p.var_10012;
            }
         }
         if(own == null)
         {
            return;
         }
         var held:uint = RemoteInput.bitsAt(own,uint(start + t - 16));
         own.var_13831 = held;
         lastBits = held;
         changes = [];
         confirmed = t - 16;
         handBackT = t;
         for each(var peer:Object in peers)
         {
            peer.backPending = !peer.gone;
            if(int(peer.confirmed) > int(peer.applied))
            {
               peer.applied = peer.confirmed;
            }
            peer.heard = getTimer();
         }
         Rejoin.handBack(t);
         SpectateFeed.resumeAt(core,start,start + t - 16);
         sendHelloBack();
      }

      private static function sendHelloBack() : void
      {
         handBackSent = getTimer();
         var n:int = 0;
         for each(var counted:Object in peers)
         {
            n++;
         }
         for each(var peer:Object in peers)
         {
            if(!peer.backPending)
            {
               continue;
            }
            var body:ByteArray = datagram(HELLO_BACK);
            body.writeUnsignedInt(uint(handBackT));
            body.writeByte(n);
            for each(var other:Object in peers)
            {
               body.writeUnsignedInt(uint(other.id));
               body.writeUnsignedInt(uint(int(other.confirmed) < 0 ? 0 : other.confirmed));
            }
            sendTo(peer,body);
         }
      }

      private static function helloBackFrame(core:Object, start:Number, now:int) : void
      {
         var waiting:Boolean = false;
         for each(var peer:Object in peers)
         {
            if(peer.backPending)
            {
               waiting = true;
               peer.heard = now;
            }
         }
         if(waiting && now - handBackSent >= 100)
         {
            sendHelloBack();
         }
         if(backJump >= 0)
         {
            var mine:Number = Number(uint(core.var_12659)) - start;
            if(backJump > mine + 16)
            {
               core.var_12659 = uint(start + backJump);
               Smoothing.jumped();
               PrivateServer.log("P2P room " + room + ": rejoin: match clock moved up " + uint(backJump - mine) +
                  " ms to the others'");
            }
            backJump = -1;
         }
      }

      private static function takeBack(peer:Object, b:ByteArray) : void
      {
         var t:int = int(b.readUnsignedInt());
         var n:int = b.readUnsignedByte();
         var mine:int = -1;
         for(var i:int = 0; i < n; i++)
         {
            var id:uint = b.readUnsignedInt();
            var c:uint = b.readUnsignedInt();
            if(id == localId)
            {
               mine = int(c);
            }
         }
         if(peer.backT != null && int(peer.backT) == t || mine < 0)
         {
            return;
         }
         var wasGone:Boolean = peer.gone;
         peer.backT = t;
         peer.rejoined = true;
         peer.gone = false;
         peer.heard = getTimer();
         peer.confirmed = t - 16;
         peer.applied = t - 16;
         peer.fed = t - 16;
         peer.pending = [];
         peer.ack = mine;
         var first:int = changes.length > 0 ? int(changes[0].t) : -1;
         Modal.close(LOST_TITLE);
         PrivateServer.log("P2P room " + room + ": " + peer.name + " is back (rejoin" + (wasGone ? "" : ", not given up yet") +
            "): its inputs from " + t + " ms, ours after " + mine + " ms" +
            (first > mine + 16 ? "; WARNING: our oldest kept change is at " + first + " ms" : ""));
         sendInputs();
      }

      private static function localAddresses() : Array
      {
         var out:Array = [];
         try
         {
            if(!NetworkInfo.isSupported)
            {
               return out;
            }
            for each(var iface:Object in NetworkInfo.networkInfo.findInterfaces())
            {
               if(!iface.active)
               {
                  continue;
               }
               for each(var a:Object in iface.addresses)
               {
                  var address:String = String(a.address);
                  if(a.ipVersion == "IPv4" && address.indexOf("127.") != 0 && address.indexOf("169.254.") != 0 &&
                     out.indexOf(address) < 0 && out.length < 8)
                  {
                     out.push(address);
                  }
               }
            }
         }
         catch(e:Error)
         {
         }
         return out;
      }
   }
}
