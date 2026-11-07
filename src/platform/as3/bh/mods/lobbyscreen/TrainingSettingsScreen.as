package bh.mods.lobbyscreen
{
   import bh.platform.GameMenus;
   import bh.platform.SettingsWindow;
   import bh.platform.TrainingDummy;
   import bh.platform.TrainingKeys;
   import bh.platform.MoveEditor;
   import bh.platform.TrainingState;
   import bh.platform.UiKit;
   import flash.display.Bitmap;
   import flash.display.BitmapData;
   import flash.display.Sprite;
   import flash.events.MouseEvent;
   import flash.filesystem.File;
   import flash.text.TextField;
   import flash.utils.Dictionary;

   public class TrainingSettingsScreen extends SettingsWindow
   {
      private static const TABS:Array = ["PLAYER","BOT","PRACTICE"];

      private static const WITH_ONLINE:Array = ["PLAYER","BOT","PRACTICE","ONLINE TRAINING"];

      private static const ONLINE:int = 3;

      private static const ROW_H:Number = 64;

      private static const AVATAR:Number = 48;

      public static var online:Object = null;

      private static var startTab:int = -1;

      private static var mapSet:int = 0;

      private static const MAP_COLS:int = 3;

      private static const ABOUT:Object = {
         "Player_GameModeType":"The kind of training: on your own, against a bot, or a game mode's practice.",
         "Player_Hero":"Your legend (changes when you confirm).",
         "Player_Costume":"Your legend's skin.",
         "Player_Color":"Your legend's colour.",
         "Player_SpawnWeapon":"Pick a weapon, then DO (or select) to drop it on you.",
         "Player_SpawnGadget":"Pick a gadget, then DO (or select) to give it to you.",
         "Player_ShowDamage":"Damage numbers on each hit.",
         "Player_ShowImpulse":"The force of each hit as an arrow.",
         "Player_ShowStun":"The stun left after each hit.",
         "Player_ShowHitboxes":"Attacks' hitboxes while they are active.",
         "Player_ShowHurtBoxes":"Where each legend can be hit.",
         "Player_ShowSpawnPoints":"Marks the stage's spawn points (11.00).",
         "Player_ItemsToggle":"Weapons and gadgets falling onto the stage.",
         "Player_BhFrameData":"Your last move's frame data and frame advantage (Bifrost).",
         "Player_BhHitboxTrail":"Keeps each frame's hitboxes on screen for a moment, with Show Hitboxes on (Bifrost).",
         "Player_BhOnlinePractice":"A simulated ping: input delay and rollback as in a P2P match (Bifrost).",
         "Player_BhStateSlot":"The slot F1 saves into and F2 loads from. Each slot keeps its own state until the match ends (Bifrost).",
         "Bot_ControlBot":"Who moves the bot: you, the CPU, both of you, or mirroring you.",
         "Bot_Hero":"The bot's legend (changes when you confirm).",
         "Bot_Costume":"The bot's skin.",
         "Bot_SpawnWeapon":"Pick a weapon, then DO (or select) to drop it on the bot.",
         "Bot_SpawnGadget":"Pick a gadget, then DO (or select) to give it to the bot.",
         "Bot_Difficulty":"How the bot behaves: stand, jump, attack, or play at a bot level.",
         "Bot_Constraint":"Limits which attacks the playing bot may use.",
         "Bot_ReactionDodge":"The bot dodges, in this direction, when it is hit.",
         "Bot_ReactionJump":"The bot jumps, in this direction, when it is hit.",
         "Bot_ReactionAttack":"The bot attacks with this, when it is hit.",
         "Bot_SetDamage":"Pick a damage, then DO (or select) to set the bot to it.",
         "Bot_HealthResetToggle":"Puts the bot's damage back after a while without being hit.",
         "Bot_PositionResetToggle":"Puts the bot back at its place after a while.",
         "Bot_ResetMode":"What the resets above wait for.",
         "Bot_BhDrift":"After a hit the bot holds this direction (its DI in true combos) until it lands, or until it starts back to the stage when knocked off (Bifrost).",
         "Bot_BhRecovery":"How the bot gets back to the stage when knocked off (Bifrost).",
         "Bot_BhDummySlot":"The slot the dummy records into and plays back. Recordings stay between matches (Bifrost)."};

      private static const LABELS:Object = {"Player_GameModeType":"TRAINING TYPE","Bot_ControlBot":"BOT CONTROL"};

      public static var current:TrainingSettingsScreen;
      public static var closing:Boolean = false;

      public function TrainingSettingsScreen(core:GameCore)
      {
         super(core);
      }

      override protected function get title() : String
      {
         return "TRAINING SETTINGS";
      }

      override protected function get gameMenu() : String
      {
         return GameMenus.TRAINING;
      }

      override protected function get tabNames() : Array
      {
         return online != null ? WITH_ONLINE : TABS;
      }

      public static function openOnline() : void
      {
         if(online == null)
         {
            return;
         }
         if(current != null)
         {
            current.showTab(ONLINE);
            return;
         }
         startTab = ONLINE;
         ScreenManager.var_14532.Display();
      }

      override protected function optionTabs() : Array
      {
         return [0,1];
      }

      override protected function canEdit() : Boolean
      {
         return true;
      }

      override protected function statusText() : String
      {
         if(tab == ONLINE && online != null)
         {
            var note:String = String(online.note());
            return note != "" ? note : "Train with a Steam friend over Steam, with no game server.";
         }
         return tab == 2 ? "The Bifrost Training keys: these work in Training at any time." :
            "Legend, bot and mode changes apply when you confirm.";
      }

      override public function OnCreateScreen() : void
      {
         current = this;
         if(startTab >= 0)
         {
            tab = startTab;
            startTab = -1;
         }
         super.OnCreateScreen();
      }

      override protected function close(apply:Boolean) : void
      {
         closing = true;
         super.close(apply);
         closing = false;
      }

      private static const SECTIONS:Array = [
         [[["YOU",["Player_GameModeType","Player_Hero","Player_Costume","Player_Color"]],
           ["ITEMS",["Player_SpawnWeapon","Player_SpawnGadget","Player_ItemsToggle"]]],
          [["ON SCREEN",["Player_ShowDamage","Player_ShowImpulse","Player_ShowStun","Player_ShowHitboxes",
             "Player_ShowHurtBoxes","Player_BhHitboxTrail","Player_BhFrameData"]],
           ["NETWORK",["Player_BhOnlinePractice"]]]],
         [[["THE BOT",["Bot_ControlBot","Bot_Hero","Bot_Costume","Bot_Difficulty","Bot_Constraint"]],
           ["GIVE THE BOT",["Bot_SpawnWeapon","Bot_SpawnGadget","Bot_SetDamage"]],
           ["RECORDED DUMMY",["Bot_BhDummySlot"]]],
          [["WHEN IT IS HIT",["Bot_ReactionDodge","Bot_ReactionJump","Bot_ReactionAttack","Bot_BhDrift","Bot_BhRecovery"]],
           ["RESETS",["Bot_HealthResetToggle","Bot_PositionResetToggle","Bot_ResetMode"]]]]];

      private var describe:TextField;
      private var describeLabel:TextField;

      override protected function buildTab(i:int) : void
      {
         describe = null;
         if(i == 2)
         {
            buildPractice();
            return;
         }
         if(i == ONLINE)
         {
            buildOnline();
            return;
         }
         var shown:Array = [];
         var byName:Object = {};
         for each(var w:Object in widgets(i))
         {
            if(kindOf(w) != "Instruction" && w.var_3713)
            {
               shown.push(w);
               byName[optionName(w)] = w;
            }
         }
         var layout:Array = SECTIONS[i];
         var cols:Array = [[],[]];
         var placed:Dictionary = new Dictionary();
         for(var c:int = 0; c < 2; c++)
         {
            for each(var sec:Array in layout[c])
            {
               var rows:Array = [];
               for each(var name:String in sec[1])
               {
                  if(byName[name] != null)
                  {
                     rows.push(byName[name]);
                     placed[byName[name]] = true;
                  }
               }
               cols[c].push([sec[0],rows]);
            }
         }
         var more:Array = [];
         for each(var m:Object in shown)
         {
            if(!placed[m])
            {
               more.push(m);
            }
         }
         if(more.length > 0)
         {
            cols[columnHeight(cols[0]) <= columnHeight(cols[1]) ? 0 : 1].push(["MORE",more]);
         }
         var listHeight:Number = area.height - 48;
         for(c = 0; c < 2; c++)
         {
            var col:Sprite = panel(area.x + c * (COL_W + 10),area.y,COL_W,listHeight);
            var list:Sprite = scroller(col,10,8,COL_W - 20,listHeight - 14);
            var y:Number = 0;
            for each(var s:Array in cols[c])
            {
               if(s[1].length == 0)
               {
                  continue;
               }
               UiKit.text(list,s[0],6,y + 2,13,UiKit.GREY,UiKit.XBOLD);
               y += 24;
               for each(var r:Object in s[1])
               {
                  y += row(list,r,0,y,COL_W - 30,null,LABELS[optionName(r)]) + 2;
               }
               y += 6;
            }
         }
         if(shown.length == 0)
         {
            UiKit.text(tabBody,"Nothing to set here.",area.x + COL_W / 2,area.y + 180,16,UiKit.GREY,UiKit.BOLD,0,true);
         }
         var bar:Sprite = panel(area.x,area.y + listHeight + 6,area.width,42);
         describeLabel = UiKit.text(bar,"",14,4,14,UiKit.WHITE,UiKit.XBOLD);
         describe = UiKit.text(bar,"",14,22,13,UiKit.LIGHT,UiKit.MEDIUM);
      }

      private static function columnHeight(sections:Array) : Number
      {
         var h:Number = 0;
         for each(var s:Array in sections)
         {
            h += s[1].length > 0 ? 30 : 0;
            for each(var r:Object in s[1])
            {
               h += rowHeight(r) + 2;
            }
         }
         return h;
      }

      override protected function focused(it:Object) : void
      {
         if(describe == null || it.w == null)
         {
            return;
         }
         var label:String = LABELS[optionName(it.w)] || labelOf(it.w);
         var about:String = ABOUT[optionName(it.w)];
         describeLabel.text = label != null ? label.toUpperCase() : "";
         describe.text = about != null ? about : "";
         UiKit.fit(describe,1030);
      }

      private function buildPractice() : void
      {
         var left:Sprite = panel(area.x,area.y,LIST_W,area.height);
         UiKit.text(left,"STATE AND DUMMY",12,8,14,UiKit.GREY,UiKit.XBOLD);
         var acts:Array = [
            ["SAVE STATE  (F1)",function():void { TrainingState.save(); }],
            ["LOAD STATE  (F2)",function():void { TrainingState.load(); }],
            ["STATE SLOT " + (TrainingState.slot + 1) + " OF " + TrainingState.SLOTS + "  (" + TrainingState.describeSlot(TrainingState.slot).toUpperCase() + ")",
               function():void { TrainingState.slot = TrainingState.slot + 1; }],
            ["RECORDING SLOT " + (TrainingDummy.slot + 1) + " OF " + TrainingDummy.SLOTS + "  (" + TrainingDummy.describeSlot().toUpperCase() + ")",
               function():void { TrainingDummy.slot = TrainingDummy.slot + 1; }],
            [TrainingDummy.isRecording ? "STOP RECORDING  (Shift+F1)" : "RECORD THE DUMMY  (Shift+F1)",function():void { TrainingDummy.toggleRecord(); }],
            [TrainingDummy.playing && !TrainingDummy.once ? "STOP THE REPLAY  (Shift+F2)" : "REPLAY ON A LOOP  (Shift+F2)",function():void { TrainingDummy.togglePlay(); }],
            ["REPLAY ONCE  (Ctrl+F2)",function():void { TrainingDummy.playOnce(); }],
            [TrainingKeys.on ? "HIDE THE KEY LIST  (F9)" : "SHOW THE KEY LIST  (F9)",function():void { TrainingKeys.on = !TrainingKeys.on; }],
            ["MOVE EDITOR",function():void { MoveEditor.open(); }]];
         for(var i:int = 0; i < acts.length; i++)
         {
            var b:Sprite = button(left,acts[i][0],10,36 + i * 40,LIST_W - 20,actor(acts[i][1]));
            items.push({"kind":"button","act":actor(acts[i][1]),"sprite":b,"width":LIST_W - 20,"height":30});
         }
         UiKit.text(left,"Saved states last for the whole match, and each slot keeps its own. Recordings play toward you from either side. " +
            "Loading a saved state restarts the recording from that moment. Recordings stay between matches.",
            12,36 + acts.length * 40 + 4,12,UiKit.LIGHT,UiKit.MEDIUM,LIST_W - 24);
         var right:Sprite = panel(DX,area.y,DW,area.height);
         UiKit.text(right,"BIFROST TRAINING KEYS",12,8,14,UiKit.GREY,UiKit.XBOLD);
         var y:Number = 36;
         var keyRows:Array = TrainingKeys.rows(game.owner);
         var step:Number = Math.min(26,(area.height - y - 14) / keyRows.length);
         for each(var r:Array in keyRows)
         {
            UiKit.fit(UiKit.text(right,r[0],14,y,13,UiKit.WHITE,UiKit.BOLD),110);
            UiKit.fit(UiKit.text(right,r[1],130,y,13,UiKit.LIGHT,UiKit.MEDIUM),250);
            UiKit.fit(UiKit.text(right,r[2],392,y,13,UiKit.TEAL,UiKit.BOLD),200);
            y += step;
         }
      }

      private function actor(act:Function) : Function
      {
         return function():void
         {
            act();
            build();
         };
      }

      private function get onlineLeftW() : Number
      {
         return Math.round(area.width * 0.58);
      }

      private function get onlineRightX() : Number
      {
         return area.x + onlineLeftW + 16;
      }

      private function get onlineRightW() : Number
      {
         return area.width - onlineLeftW - 16;
      }

      private function onlineButton(parent:Sprite, label:String, x:Number, y:Number, w:Number, act:Function, h:Number,
                                    size:int, listed:Boolean = true) : Sprite
      {
         var b:Sprite = button(parent,label,x,y,w,act,h,size);
         if(listed)
         {
            items.push({"kind":"button","act":act,"sprite":b,"parent":parent,"width":w,"height":h});
         }
         return b;
      }

      private function buildOnline() : void
      {
         var friends:Array = online.friends() as Array || [];
         var incoming:Array = online.incoming() as Array || [];
         var state:String = String(online.state());
         var partner:String = String(online.partner() || "");
         var playing:Array = friends.filter(function(f:Object, ... rest):Boolean
         {
            return f.playing;
         });
         var others:Array = friends.filter(function(f:Object, ... rest):Boolean
         {
            return !f.playing && f.online;
         });
         var leftW:Number = onlineLeftW;
         var rightW:Number = onlineRightW;
         var left:Sprite = panel(area.x,area.y,leftW,area.height);
         var right:Sprite = panel(onlineRightX,area.y,rightW,area.height);
         UiKit.text(left,"IN BRAWLHALLA NOW  ·  " + playing.length,14,10,14,UiKit.GREY,UiKit.XBOLD);
         var list:Sprite = scroller(left,0,36,leftW,area.height - 42);
         var y:Number = 0;
         if(playing.length == 0)
         {
            UiKit.text(list,"None of your Steam friends is in Brawlhalla right now. When one starts the game, they show " +
               "here with an INVITE button.",14,4,13,UiKit.LIGHT,UiKit.MEDIUM,leftW - 40);
            y = 56;
         }
         for each(var f:Object in playing)
         {
            friendRow(list,y,f,state,partner);
            y += ROW_H + 6;
         }
         if(others.length > 0)
         {
            UiKit.text(list,"ONLINE, NOT IN BRAWLHALLA  ·  " + others.length,14,y + 8,12,UiKit.GREY,UiKit.XBOLD);
            y += 34;
            for each(f in others)
            {
               friendRow(list,y,f,state,partner);
               y += ROW_H + 6;
            }
         }
         UiKit.text(right,"INVITES TO YOU",14,10,14,UiKit.GREY,UiKit.XBOLD);
         var ry:Number = 36;
         if(incoming.length == 0)
         {
            UiKit.text(right,"No invites right now.",14,ry,13,UiKit.LIGHT,UiKit.MEDIUM,rightW - 28);
            ry += 30;
         }
         for each(var inv:Object in incoming)
         {
            inviteRow(right,ry,inv);
            ry += ROW_H + 6;
         }
         UiKit.rect(right,14,ry + 6,rightW - 28,1,UiKit.LINE);
         var maps:Array = online.maps() as Array || [];
         if(maps.length > 0)
         {
            mapGrid(right,ry + 16,maps);
            return;
         }
         UiKit.text(right,"HOW IT WORKS",14,ry + 16,12,UiKit.GREY,UiKit.XBOLD);
         UiKit.text(right,"It runs between your two PCs through Steam, with no game server. Both of you need to be in Training " +
            "on the same version. Starting closes your current Training match, and you start on the map of whoever invited. " +
            "Once you're playing, either of you can change the map here. Leave the match to end it.",
            14,ry + 38,13,UiKit.LIGHT,UiKit.MEDIUM,rightW - 28);
      }

      private function mapGrid(right:Sprite, y:Number, maps:Array) : void
      {
         var rightW:Number = onlineRightW;
         var currentMap:String = String(online.currentMap());
         UiKit.text(right,"MAP  ·  " + currentMap.toUpperCase(),14,y,12,UiKit.GREY,UiKit.XBOLD);
         var sets:Array = mapSets(maps);
         if(mapSet >= sets.length)
         {
            mapSet = 0;
         }
         var top:Number = y + 24 + setChips(right,14,y + 24,rightW - 28,sets);
         var picked:String = mapSet > 0 ? String(sets[mapSet]) : null;
         var shown:Array = [];
         for(var k:int = 0; k < maps.length; k++)
         {
            if(picked == null || (maps[k].length > 3 && (maps[k][3] as Array).indexOf(picked) >= 0))
            {
               shown.push(maps[k]);
            }
         }
         var grid:Sprite = scroller(right,0,top + 10,rightW,area.height - top - 16);
         var cardW:Number = Math.floor((rightW - 28 - (MAP_COLS - 1) * 8) / MAP_COLS);
         var picH:Number = Math.round(cardW * 9 / 16);
         for(var i:int = 0; i < shown.length; i++)
         {
            mapCard(grid,14 + (i % MAP_COLS) * (cardW + 8),2 + Math.floor(i / MAP_COLS) * (picH + 34),cardW,picH,shown[i],
               String(shown[i][1]) == currentMap);
         }
      }

      private static function mapSets(maps:Array) : Array
      {
         var counts:Object = {};
         var order:Array = [];
         for(var i:int = 0; i < maps.length; i++)
         {
            var in_:Array = maps[i].length > 3 ? maps[i][3] as Array : null;
            for(var j:int = 0; in_ != null && j < in_.length; j++)
            {
               var s:String = String(in_[j]);
               if(counts[s] == null)
               {
                  counts[s] = 0;
                  order.push(s);
               }
               counts[s]++;
            }
         }
         var useful:Array = [];
         for(var k:int = 0; k < order.length; k++)
         {
            if(counts[order[k]] >= 2 && counts[order[k]] < maps.length)
            {
               useful.push(order[k]);
            }
         }
         useful.sort(function(a:String, b:String):int
         {
            return counts[a] != counts[b] ? counts[b] - counts[a] : (a < b ? -1 : (a > b ? 1 : 0));
         });
         return ["All maps"].concat(useful);
      }

      private function setChips(parent:Sprite, x:Number, y:Number, w:Number, sets:Array) : Number
      {
         var cx:Number = 0;
         var cy:Number = 0;
         for(var i:int = 0; i < sets.length; i++)
         {
            var on:Boolean = i == mapSet;
            var chip:Sprite = new Sprite();
            chip.buttonMode = true;
            parent.addChild(chip);
            var label:TextField = UiKit.text(chip,String(sets[i]).toUpperCase(),12,4,11,on ? UiKit.NAVY_TEXT : UiKit.LIGHT,UiKit.XBOLD);
            var chipW:Number = label.width + 24;
            if(cx > 0 && cx + chipW > w)
            {
               cx = 0;
               cy += 30;
            }
            chip.x = x + cx;
            chip.y = y + cy;
            chip.setChildIndex(UiKit.rect(chip,0,0,chipW,24,on ? UiKit.TEAL : UiKit.LINE,24),0);
            var act:Function = setPicker(i);
            chip.addEventListener(MouseEvent.CLICK,clicked(act));
            items.push({"kind":"button","act":act,"sprite":chip,"parent":parent,"width":chipW,"height":24});
            cx += chipW + 6;
         }
         return cy + 24;
      }

      private function mapCard(grid:Sprite, x:Number, y:Number, w:Number, picH:Number, map:Array, here:Boolean) : void
      {
         var card:Sprite = new Sprite();
         card.x = x;
         card.y = y;
         card.buttonMode = !here;
         grid.addChild(card);
         UiKit.rect(card,-2,-2,w + 4,picH + 30,here ? UiKit.TEAL : UiKit.LINE,8);
         var pic:Sprite = new Sprite();
         card.addChild(pic);
         UiKit.rect(pic,0,0,w,picH,UiKit.NAVY_TEXT,6);
         var thumb:String = map.length > 2 ? String(map[2]) : "";
         if(thumb != "")
         {
            UiKit.picture(pic,File.applicationDirectory.resolvePath(thumb),w,picH,true);
         }
         UiKit.fit(UiKit.text(card,String(map[1]).toUpperCase(),w / 2,picH + 5,11,here ? UiKit.NAVY_TEXT : UiKit.WHITE,UiKit.XBOLD,0,true),
            w - 8);
         if(here)
         {
            return;
         }
         var act:Function = mapPicker(uint(map[0]));
         card.addEventListener(MouseEvent.CLICK,clicked(act));
         items.push({"kind":"button","act":act,"sprite":card,"parent":grid,"width":w,"height":picH + 26});
      }

      private static function clicked(act:Function) : Function
      {
         return function(e:MouseEvent):void
         {
            e.stopPropagation();
            act();
         };
      }

      private function setPicker(i:int) : Function
      {
         return function():void
         {
            mapSet = i;
            build();
         };
      }

      private static function noop() : void
      {
      }

      private function mapPicker(id:uint) : Function
      {
         return function():void
         {
            online.pickMap(id);
            build();
         };
      }

      private function avatarOf(parent:Sprite, x:Number, y:Number, f:Object, dim:Boolean) : void
      {
         UiKit.rect(parent,x - 2,y - 2,AVATAR + 4,AVATAR + 4,dim ? UiKit.LINE : UiKit.TEAL,6);
         var bd:BitmapData = f.avatar as BitmapData;
         if(bd != null)
         {
            var pic:Bitmap = new Bitmap(bd);
            pic.smoothing = true;
            pic.x = x;
            pic.y = y;
            pic.width = pic.height = AVATAR;
            pic.alpha = dim ? 0.5 : 1;
            parent.addChild(pic);
         }
         else
         {
            UiKit.rect(parent,x,y,AVATAR,AVATAR,UiKit.BODY,4);
            var initial:String = String(f.name || "?").charAt(0).toUpperCase();
            UiKit.text(parent,initial,x + AVATAR / 2,y + 10,22,UiKit.GREY,UiKit.XBOLD,0,true);
         }
      }

      private function friendRow(list:Sprite, y:Number, f:Object, state:String, partner:String) : void
      {
         var r:Sprite = new Sprite();
         r.y = y;
         list.addChild(r);
         var w:Number = onlineLeftW - 20;
         var dim:Boolean = !f.playing;
         UiKit.rect(r,10,0,w,ROW_H,UiKit.BODY,6);
         avatarOf(r,18,8,f,dim);
         UiKit.fit(UiKit.text(r,String(f.name),78,10,17,dim ? UiKit.LIGHT : UiKit.WHITE,UiKit.BOLD),w - 260);
         var mine:Boolean = String(f.id) == partner;
         var status:String = !f.playing ? "ONLINE" : (mine && state == "inviting" ? "INVITED, WAITING FOR AN ANSWER" :
            (mine && (state == "accepting" || state == "leaving") ? "JOINING..." : (mine && state == "running" ? "PLAYING WITH YOU" :
            "IN BRAWLHALLA")));
         UiKit.fit(UiKit.text(r,status,78,36,12,f.playing ? UiKit.TEAL : UiKit.GREY,UiKit.XBOLD),w - 260);
         if(!f.playing)
         {
            return;
         }
         var busy:Boolean = state != "idle";
         var cancel:Boolean = mine && state == "inviting";
         var run:Function = cancel ? function():void
         {
            online.cancel();
            build();
         } : (busy ? noop : function():void
         {
            online.invite(String(f.id),String(f.name));
            build();
         });
         var b:Sprite = onlineButton(r,cancel ? "CANCEL" : "INVITE",w - 150,(ROW_H - 34) / 2,140,run,34,14,cancel || !busy);
         if(busy && !cancel)
         {
            b.alpha = 0.4;
         }
      }

      private function inviteRow(parent:Sprite, y:Number, inv:Object) : void
      {
         var r:Sprite = new Sprite();
         r.y = y;
         parent.addChild(r);
         var w:Number = onlineRightW - 28;
         UiKit.rect(r,14,0,w,ROW_H,UiKit.BODY,6);
         avatarOf(r,22,8,inv,false);
         UiKit.fit(UiKit.text(r,String(inv.name),82,6,16,UiKit.WHITE,UiKit.BOLD),w - 90);
         onlineButton(r,"ACCEPT",82,30,96,function():void
         {
            online.accept(String(inv.id));
            build();
         },28,12);
         onlineButton(r,"DECLINE",186,30,96,function():void
         {
            online.decline(String(inv.id));
            build();
         },28,12);
      }

      override protected function extraSignature() : String
      {
         if(tab == ONLINE)
         {
            return online != null ? String(online.signature()) : "";
         }
         if(tab != 2)
         {
            return "";
         }
         var parts:Array = [];
         for each(var r:Array in TrainingKeys.rows(game.owner))
         {
            parts.push(String(r[2]).indexOf(" s ago") >= 0 ? "saved" : r[2]);
         }
         return parts.join("|") + TrainingKeys.on;
      }

      override public function HandleInput(input:int) : Boolean
      {
         if(MoveEditor.shown != null)
         {
            return MoveEditor.shown.HandleInput(input);
         }
         return super.HandleInput(input);
      }

      override public function OnDestroyScreen() : void
      {
         current = null;
         super.OnDestroyScreen();
      }
   }
}
