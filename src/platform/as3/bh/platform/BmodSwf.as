package bh.platform
{
   import flash.utils.ByteArray;
   import flash.utils.Endian;

   public final class BmodSwf
   {
      public static const END:int = 0;

      public static const SHOW_FRAME:int = 1;

      public static const SET_BACKGROUND:int = 9;

      public static const FILE_ATTRIBUTES:int = 69;

      public static const SYMBOL_CLASS:int = 76;

      public static const METADATA:int = 77;

      public static const DO_ABC:int = 82;

      public static const BINARY_DATA:int = 87;

      public static const NOT_COPIED:Array = [0,1,69,76,77,82,87,9,56,72,41,64,65,86];

      private static const LONG_TAGS:Array = [20,21,35,36,90,6];

      private static const CHARACTER_TAGS:Array = [2,22,32,83,39,6,20,21,35,36,90];

      private var d:ByteArray;

      public var p:int;

      private var b:int = 0;

      private var end:int;

      private var out:ByteArray;

      private var cur:int = 0;

      private var n:int = 0;

      public function BmodSwf(data:ByteArray, pos:int, limit:int = -1)
      {
         d = data;
         p = pos;
         end = limit;
         if(data == null)
         {
            out = new ByteArray();
         }
         else if(limit < 0)
         {
            end = int(data.length);
         }
      }

      public static function at(data:ByteArray, i:int, limit:int) : int
      {
         if(i < 0 || i >= limit)
         {
            throw new Error("past the end of a tag at " + i);
         }
         return int(data[i]);
      }

      public function ub(bits:int) : int
      {
         var v:int = 0;
         for(var i:int = 0; i < bits; i++)
         {
            var bit:int = (at(d,p,end) >> (7 - b)) & 1;
            v = (v << 1) | bit;
            b++;
            if(b == 8)
            {
               b = 0;
               p++;
            }
         }
         return v;
      }

      public function sb(bits:int) : Number
      {
         var v:Number = ub(bits);
         if(bits > 0 && v >= Math.pow(2,bits - 1))
         {
            return v - Math.pow(2,bits);
         }
         return v;
      }

      public function align() : void
      {
         if(b != 0)
         {
            b = 0;
            p++;
         }
      }

      public function put(v:Number, bits:int) : void
      {
         for(var i:int = bits - 1; i >= 0; i--)
         {
            var bit:int = int(Math.floor(v / Math.pow(2,i)) % 2);
            cur = (cur << 1) | bit;
            n++;
            if(n == 8)
            {
               out.writeByte(cur);
               cur = 0;
               n = 0;
            }
         }
      }

      public function done() : ByteArray
      {
         if(n != 0)
         {
            put(0,8 - n);
         }
         return out;
      }

      public static function read(data:ByteArray) : Object
      {
         if(data.length < 8)
         {
            throw new Error("not a SWF (too short)");
         }
         var sig:String = String.fromCharCode(int(data[0])) + String.fromCharCode(int(data[1])) + String.fromCharCode(int(data[2]));
         var body:ByteArray = data;
         var start:int = 8;
         if(sig == "CWS")
         {
            body = new ByteArray();
            body.writeBytes(data,8,data.length - 8);
            body.uncompress();
            start = 0;
         }
         else if(sig != "FWS")
         {
            throw new Error("not a SWF (starts with " + sig + ")");
         }
         var nbits:int = int(body[start]) >> 3;
         var rectLen:int = (5 + 4 * nbits + 7) >> 3;
         var rect:ByteArray = new ByteArray();
         rect.writeBytes(body,start,rectLen);
         var pos:int = start + rectLen;
         var rate:int = u16(body,pos);
         var count:int = u16(body,pos + 2);
         pos += 4;
         var tags:Array = [];
         var total:int = body.length;
         while(pos + 2 <= total)
         {
            var codeLen:int = u16(body,pos);
            pos += 2;
            var code:int = codeLen >> 6;
            var length:int = codeLen & 0x3F;
            if(length == 0x3F)
            {
               length = u32(body,pos);
               pos += 4;
            }
            if(pos + length > total)
            {
               length = total - pos;
            }
            tags.push({"code":code,"src":body,"pos":pos,"len":length});
            pos += length;
            if(code == END)
            {
               break;
            }
         }
         return {"version":int(data[3]),"rect":rect,"rate":rate,"count":count,"tags":tags};
      }

      public static function tag(code:int, body:ByteArray) : Object
      {
         return {"code":code,"src":body,"pos":0,"len":int(body.length)};
      }

      public static function copy(t:Object) : ByteArray
      {
         var src:ByteArray = t.src;
         var out:ByteArray = new ByteArray();
         if(int(t.len) > 0)
         {
            out.writeBytes(src,int(t.pos),int(t.len));
         }
         out.position = 0;
         return out;
      }

      public static function u16(data:ByteArray, pos:int) : int
      {
         return int(data[pos]) | (int(data[pos + 1]) << 8);
      }

      public static function u32(data:ByteArray, pos:int) : int
      {
         return int(data[pos]) | (int(data[pos + 1]) << 8) | (int(data[pos + 2]) << 16) | (int(data[pos + 3]) << 24);
      }

      public static function id(t:Object) : int
      {
         var src:ByteArray = t.src;
         return u16(src,int(t.pos));
      }

      private static function writeU16(out:ByteArray, v:int) : void
      {
         out.writeByte(v & 0xFF);
         out.writeByte((v >> 8) & 0xFF);
      }

      private static function writeU32(out:ByteArray, v:int) : void
      {
         out.writeByte(v & 0xFF);
         out.writeByte((v >> 8) & 0xFF);
         out.writeByte((v >> 16) & 0xFF);
         out.writeByte((v >> 24) & 0xFF);
      }

      public static function writeTag(out:ByteArray, t:Object) : void
      {
         var len:int = int(t.len);
         var code:int = int(t.code);
         if(len < 0x3F && LONG_TAGS.indexOf(code) < 0)
         {
            writeU16(out,(code << 6) | len);
         }
         else
         {
            writeU16(out,(code << 6) | 0x3F);
            writeU32(out,len);
         }
         if(len > 0)
         {
            var src:ByteArray = t.src;
            out.writeBytes(src,int(t.pos),len);
         }
      }

      public static function tagBytes(code:int, body:ByteArray) : ByteArray
      {
         var out:ByteArray = new ByteArray();
         writeTag(out,tag(code,body));
         return out;
      }

      public static function write(header:Object, tags:Array) : ByteArray
      {
         var body:ByteArray = new ByteArray();
         var rect:ByteArray = header.rect;
         body.writeBytes(rect);
         writeU16(body,int(header.rate));
         writeU16(body,int(header.count));
         for each(var t:Object in tags)
         {
            writeTag(body,t);
         }
         var out:ByteArray = new ByteArray();
         out.writeByte(0x46);
         out.writeByte(0x57);
         out.writeByte(0x53);
         out.writeByte(int(header.version));
         writeU32(out,8 + int(body.length));
         out.writeBytes(body);
         return out;
      }

      public static function symbolClass(t:Object) : Array
      {
         var data:ByteArray = t.src;
         var limit:int = int(t.pos) + int(t.len);
         var count:int = u16(data,int(t.pos));
         var out:Array = [];
         var i:int = int(t.pos) + 2;
         for(var k:int = 0; k < count && i + 2 <= limit; k++)
         {
            var cid:int = u16(data,i);
            var j:int = i + 2;
            while(j < limit && int(data[j]) != 0)
            {
               j++;
            }
            data.position = i + 2;
            out.push([cid,data.readUTFBytes(j - i - 2)]);
            i = j + 1;
         }
         return out;
      }

      public static function symbolClassTag(entries:Array) : ByteArray
      {
         var out:ByteArray = new ByteArray();
         writeU16(out,entries.length);
         for each(var e:Array in entries)
         {
            writeU16(out,int(e[0]));
            out.writeUTFBytes(String(e[1]));
            out.writeByte(0);
         }
         return out;
      }

      public static function symbols(tags:Array) : Array
      {
         var out:Array = [];
         for each(var t:Object in tags)
         {
            if(int(t.code) == SYMBOL_CLASS)
            {
               out = out.concat(symbolClass(t));
            }
         }
         return out;
      }

      public static function jsonPrefix(text:String) : String
      {
         var depth:int = 0;
         var inString:Boolean = false;
         var started:Boolean = false;
         for(var i:int = 0; i < text.length; i++)
         {
            var c:String = text.charAt(i);
            if(inString)
            {
               if(c == "\\")
               {
                  i++;
               }
               else if(c == "\"")
               {
                  inString = false;
               }
               continue;
            }
            if(c == "\"")
            {
               inString = true;
            }
            else if(c == "{" || c == "[")
            {
               depth++;
               started = true;
            }
            else if(c == "}" || c == "]")
            {
               depth--;
               if(started && depth == 0)
               {
                  return text.substr(0,i + 1);
               }
            }
         }
         return text;
      }

      public static function readBmod(data:ByteArray) : Object
      {
         var swf:Object = read(data);
         var meta:Object = null;
         for each(var t:Object in swf.tags)
         {
            if(int(t.code) == METADATA && meta == null)
            {
               var src:ByteArray = t.src;
               src.position = int(t.pos);
               var text:String = src.readUTFBytes(int(t.len));
               meta = JSON.parse(jsonPrefix(text));
            }
         }
         if(meta == null)
         {
            throw new Error("no Metadata tag, so not a .bmod");
         }
         swf.meta = meta;
         swf.symbols = symbols(swf.tags);
         return swf;
      }

      public static function binaryData(tags:Array) : Object
      {
         var out:Object = {};
         for each(var t:Object in tags)
         {
            if(int(t.code) == BINARY_DATA && int(t.len) >= 6)
            {
               out["b" + id(t)] = {"code":0,"src":t.src,"pos":int(t.pos) + 6,"len":int(t.len) - 6};
            }
         }
         return out;
      }

      private static function skipRect(data:ByteArray, pos:int, limit:int) : int
      {
         var r:BmodSwf = new BmodSwf(data,pos,limit);
         var bits:int = r.ub(5);
         for(var i:int = 0; i < 4; i++)
         {
            r.sb(bits);
         }
         r.align();
         return r.p;
      }

      private static function skipMatrix(data:ByteArray, pos:int, limit:int) : int
      {
         var r:BmodSwf = new BmodSwf(data,pos,limit);
         var bits:int = 0;
         for(var i:int = 0; i < 2; i++)
         {
            if(r.ub(1) != 0)
            {
               bits = r.ub(5);
               r.sb(bits);
               r.sb(bits);
            }
         }
         bits = r.ub(5);
         r.sb(bits);
         r.sb(bits);
         r.align();
         return r.p;
      }

      private static function rgb(data:ByteArray, pos:int, limit:int) : int
      {
         return (at(data,pos,limit) << 16) | (at(data,pos + 1,limit) << 8) | at(data,pos + 2,limit);
      }

      private static function fillColours(data:ByteArray, pos:int, limit:int, ver:int, out:BmodMap) : int
      {
         var kind:int = at(data,pos,limit);
         pos++;
         var size:int = ver >= 3 ? 4 : 3;
         if(kind == 0)
         {
            if(out != null)
            {
               out.add(rgb(data,pos,limit),1);
            }
            return pos + size;
         }
         if(kind == 0x10 || kind == 0x12 || kind == 0x13)
         {
            pos = skipMatrix(data,pos,limit);
            var count:int = at(data,pos,limit) & 0x0F;
            pos++;
            for(var i:int = 0; i < count; i++)
            {
               var c:int = rgb(data,pos + 1,limit);
               if(out != null)
               {
                  out.add(c,1);
               }
               pos += 1 + size;
            }
            return pos + (kind == 0x13 ? 2 : 0);
         }
         if(kind >= 0x40 && kind <= 0x43)
         {
            return skipMatrix(data,pos + 2,limit);
         }
         throw new Error("fill style type " + kind);
      }

      private static function styleColours(data:ByteArray, pos:int, limit:int, ver:int, out:BmodMap) : int
      {
         var count:int = at(data,pos,limit);
         pos++;
         if(count == 0xFF && ver >= 2)
         {
            count = at(data,pos,limit) | (at(data,pos + 1,limit) << 8);
            pos += 2;
         }
         for(var i:int = 0; i < count; i++)
         {
            pos = fillColours(data,pos,limit,ver,out);
         }
         return skipLines(data,pos,limit,ver);
      }

      private static function skipLines(data:ByteArray, pos:int, limit:int, ver:int) : int
      {
         var count:int = at(data,pos,limit);
         pos++;
         if(count == 0xFF && ver >= 2)
         {
            count = at(data,pos,limit) | (at(data,pos + 1,limit) << 8);
            pos += 2;
         }
         for(var i:int = 0; i < count; i++)
         {
            if(ver == 4)
            {
               var flags:int = at(data,pos + 2,limit);
               var join:int = (flags >> 4) & 3;
               var hasFill:int = (flags >> 3) & 1;
               pos += 4 + (join == 2 ? 2 : 0);
               pos = hasFill != 0 ? fillColours(data,pos,limit,ver,null) : pos + 4;
            }
            else
            {
               pos += 2 + (ver >= 3 ? 4 : 3);
            }
         }
         return pos;
      }

      private static function skipEdge(r:BmodSwf) : void
      {
         var straight:int = r.ub(1);
         var bits:int = r.ub(4) + 2;
         if(straight != 0)
         {
            if(r.ub(1) != 0)
            {
               r.sb(bits);
               r.sb(bits);
            }
            else
            {
               r.ub(1);
               r.sb(bits);
            }
         }
         else
         {
            for(var i:int = 0; i < 4; i++)
            {
               r.sb(bits);
            }
         }
      }

      private static function walkShape(data:ByteArray, start:int, limit:int, ver:int, out:BmodMap, stopAtNew:Boolean) : Boolean
      {
         var r:BmodSwf = new BmodSwf(data,start,limit);
         var nf:int = r.ub(4);
         var nl:int = r.ub(4);
         while(true)
         {
            if(r.ub(1) == 0)
            {
               var flags:int = r.ub(5);
               if(flags == 0)
               {
                  return false;
               }
               if((flags & 1) != 0)
               {
                  var bits:int = r.ub(5);
                  r.sb(bits);
                  r.sb(bits);
               }
               if((flags & 2) != 0)
               {
                  r.ub(nf);
               }
               if((flags & 4) != 0)
               {
                  r.ub(nf);
               }
               if((flags & 8) != 0)
               {
                  r.ub(nl);
               }
               if((flags & 16) != 0)
               {
                  if(stopAtNew)
                  {
                     return true;
                  }
                  r.align();
                  r = new BmodSwf(data,styleColours(data,r.p,limit,ver > 2 ? ver : 2,out),limit);
                  nf = r.ub(4);
                  nl = r.ub(4);
               }
            }
            else
            {
               skipEdge(r);
            }
         }
         return false;
      }

      public static function usesNewStyles(t:Object) : Boolean
      {
         var data:ByteArray = t.src;
         var limit:int = int(t.pos) + int(t.len);
         var start:int = styleColours(data,skipRect(data,int(t.pos) + 2,limit),limit,1,null);
         return walkShape(data,start,limit,1,null,true);
      }

      public static function fixShapes(tags:Array) : Array
      {
         var out:Array = [];
         var fixed:int = 0;
         for each(var t:Object in tags)
         {
            if(int(t.code) == 2)
            {
               try
               {
                  if(usesNewStyles(t))
                  {
                     t = {"code":22,"src":t.src,"pos":int(t.pos),"len":int(t.len)};
                     fixed++;
                  }
               }
               catch(e:Error)
               {
               }
            }
            out.push(t);
         }
         return [out,fixed];
      }

      public static function shapeColours(t:Object, ver:int) : BmodMap
      {
         var out:BmodMap = new BmodMap();
         var data:ByteArray = t.src;
         var limit:int = int(t.pos) + int(t.len);
         var pos:int = skipRect(data,int(t.pos) + 2,limit);
         if(ver == 4)
         {
            pos = skipRect(data,pos,limit) + 1;
         }
         walkShape(data,styleColours(data,pos,limit,ver,out),limit,ver,out,false);
         return out;
      }

      public static function spriteChildren(t:Object) : Array
      {
         var data:ByteArray = t.src;
         var limit:int = int(t.pos) + int(t.len);
         var pos:int = int(t.pos) + 4;
         var out:Array = [];
         while(pos + 2 <= limit)
         {
            var cl:int = u16(data,pos);
            pos += 2;
            var code:int = cl >> 6;
            var len:int = cl & 0x3F;
            if(len == 0x3F)
            {
               len = u32(data,pos);
               pos += 4;
            }
            var s:int = pos;
            var e:int = pos + len < limit ? pos + len : limit;
            pos += len;
            if(code == 26 && e > s && (int(data[s]) & 0x02) != 0)
            {
               out.push(at(data,s + 3,e) | (at(data,s + 4,e) << 8));
            }
            else if(code == 70 && e - s > 2 && (int(data[s]) & 0x02) != 0)
            {
               var i:int = s + 4;
               if((int(data[s + 1]) & 0x08) != 0 || (int(data[s + 1]) & 0x10) != 0)
               {
                  while(i < e && int(data[i]) != 0)
                  {
                     i++;
                  }
                  if(i >= e)
                  {
                     throw new Error("no class name end");
                  }
                  i++;
               }
               out.push(at(data,i,e) | (at(data,i + 1,e) << 8));
            }
            if(code == END)
            {
               break;
            }
         }
         return out;
      }

      private var shapeSet:Object;

      private var spriteSet:Object;

      private var memo:Object;

      private static function shapeVersion(code:int) : int
      {
         return code == 2 ? 1 : (code == 22 ? 2 : (code == 32 ? 3 : (code == 83 ? 4 : 0)));
      }

      private function collect(cid:int, seen:Object) : BmodMap
      {
         if(("s" + cid) in shapeSet)
         {
            return shapeSet["s" + cid];
         }
         var total:BmodMap = new BmodMap();
         if(!(("s" + cid) in spriteSet))
         {
            return total;
         }
         var children:Array = spriteSet["s" + cid];
         for each(var child:int in children)
         {
            if(!(("s" + child) in seen))
            {
               seen["s" + child] = true;
               var part:BmodMap = collect(child,seen);
               for each(var c:* in part.keys)
               {
                  total.add(c,Number(part.get(c)));
               }
            }
         }
         return total;
      }

      public static function symbolColours(tags:Array) : BmodMap
      {
         var r:BmodSwf = new BmodSwf(null,0);
         r.shapeSet = {};
         r.spriteSet = {};
         var names:BmodMap = new BmodMap();
         for each(var t:Object in tags)
         {
            var code:int = int(t.code);
            var ver:int = shapeVersion(code);
            if(ver != 0)
            {
               try
               {
                  r.shapeSet["s" + id(t)] = shapeColours(t,ver);
               }
               catch(e:Error)
               {
               }
            }
            else if(code == 39)
            {
               r.spriteSet["s" + id(t)] = spriteChildren(t);
            }
            else if(code == SYMBOL_CLASS)
            {
               for each(var entry:Array in symbolClass(t))
               {
                  names.set(int(entry[0]),String(entry[1]));
               }
            }
         }
         var out:BmodMap = new BmodMap();
         for each(var cid:* in names.keys)
         {
            var seen:Object = {};
            seen["s" + cid] = true;
            out.set(names.get(cid),r.collect(int(cid),seen));
         }
         return out;
      }

      public static function readMatrix(data:ByteArray, pos:int, limit:int) : Array
      {
         var r:BmodSwf = new BmodSwf(data,pos,limit);
         var a:Number = 1;
         var dd:Number = 1;
         var bb:Number = 0;
         var c:Number = 0;
         var bits:int = 0;
         if(r.ub(1) != 0)
         {
            bits = r.ub(5);
            a = r.sb(bits) / 65536;
            dd = r.sb(bits) / 65536;
         }
         if(r.ub(1) != 0)
         {
            bits = r.ub(5);
            bb = r.sb(bits) / 65536;
            c = r.sb(bits) / 65536;
         }
         bits = r.ub(5);
         var tx:Number = r.sb(bits) / 20;
         var ty:Number = r.sb(bits) / 20;
         return [a,bb,c,dd,tx,ty];
      }

      private static function rect(data:ByteArray, pos:int, limit:int) : Array
      {
         var r:BmodSwf = new BmodSwf(data,pos,limit);
         var bits:int = r.ub(5);
         var x0:Number = r.sb(bits) / 20;
         var x1:Number = r.sb(bits) / 20;
         var y0:Number = r.sb(bits) / 20;
         var y1:Number = r.sb(bits) / 20;
         return [x0,y0,x1,y1];
      }

      public static function addBox(box:Array, cb:Array, m:Array) : Array
      {
         var corners:Array = [[cb[0],cb[1]],[cb[2],cb[1]],[cb[0],cb[3]],[cb[2],cb[3]]];
         for each(var xy:Array in corners)
         {
            var x:Number = xy[0];
            var y:Number = xy[1];
            var px:Number = Number(m[0]) * x + Number(m[2]) * y + Number(m[4]);
            var py:Number = Number(m[1]) * x + Number(m[3]) * y + Number(m[5]);
            if(box == null)
            {
               box = [px,py,px,py];
            }
            else
            {
               box = [Math.min(box[0],px),Math.min(box[1],py),Math.max(box[2],px),Math.max(box[3],py)];
            }
         }
         return box;
      }

      public static function boundsReader(tags:Array) : BmodSwf
      {
         var r:BmodSwf = new BmodSwf(null,0);
         r.shapeSet = {};
         r.spriteSet = {};
         r.memo = {};
         for each(var t:Object in tags)
         {
            var code:int = int(t.code);
            if(code == 2 || code == 22 || code == 32 || code == 83)
            {
               r.shapeSet["s" + id(t)] = t;
            }
            else if(code == 39)
            {
               r.spriteSet["s" + id(t)] = t;
            }
         }
         return r;
      }

      private static function places(t:Object) : Array
      {
         var data:ByteArray = t.src;
         var limit:int = int(t.pos) + int(t.len);
         var pos:int = int(t.pos) + 4;
         var list:Array = [];
         while(pos + 2 <= limit)
         {
            var cl:int = u16(data,pos);
            pos += 2;
            var kind:int = cl >> 6;
            var len:int = cl & 0x3F;
            if(len == 0x3F)
            {
               len = u32(data,pos);
               pos += 4;
            }
            var s:int = pos;
            var e:int = pos + len < limit ? pos + len : limit;
            pos += len;
            if(kind == SHOW_FRAME || kind == END)
            {
               break;
            }
            if(kind == 26 && (at(data,s,e) & 0x02) != 0)
            {
               var cid:int = at(data,s + 3,e) | (at(data,s + 4,e) << 8);
               var m:Array = (int(data[s]) & 0x04) != 0 ? readMatrix(data,s + 5,e) : [1,0,0,1,0,0];
               list.push([cid,m]);
            }
         }
         return list;
      }

      public function boundsOf(cid:int) : Array
      {
         return boundsAt(cid,0);
      }

      private function boundsAt(cid:int, depth:int) : Array
      {
         var k:String = "s" + cid;
         if(k in memo)
         {
            return memo[k];
         }
         if(k in shapeSet)
         {
            var st:Object = shapeSet[k];
            var src:ByteArray = st.src;
            memo[k] = rect(src,int(st.pos) + 2,int(st.pos) + int(st.len));
            return memo[k];
         }
         var box:Array = null;
         if((k in spriteSet) && depth < 20)
         {
            for each(var place:Array in places(spriteSet[k]))
            {
               var cb:Array = boundsAt(int(place[0]),depth + 1);
               if(cb != null)
               {
                  box = addBox(box,cb,place[1]);
               }
            }
         }
         memo[k] = box;
         return box;
      }

      public static function pyRound(v:Number) : Number
      {
         var f:Number = Math.floor(v);
         var diff:Number = v - f;
         if(diff > 0.5)
         {
            return f + 1;
         }
         if(diff < 0.5)
         {
            return f;
         }
         return f % 2 == 0 ? f : f + 1;
      }

      public static function bitLength(v:Number) : int
      {
         var bits:int = 0;
         while(v >= 1)
         {
            v = Math.floor(v / 2);
            bits++;
         }
         return bits;
      }

      public static function nbits(values:Array) : int
      {
         var best:int = 1;
         for each(var v:Number in values)
         {
            var size:int = (v >= 0 ? bitLength(v) : bitLength(-v - 1)) + 1;
            if(size > best)
            {
               best = size;
            }
         }
         return best;
      }

      private static function putSigned(w:BmodSwf, v:Number, bits:int) : void
      {
         w.put(v < 0 ? v + Math.pow(2,bits) : v,bits);
      }

      public static function writeMatrix(a:Number, bb:Number, c:Number, dd:Number, tx:Number, ty:Number) : ByteArray
      {
         var w:BmodSwf = new BmodSwf(null,0);
         var sx:Number = pyRound(a * 65536);
         var sy:Number = pyRound(dd * 65536);
         w.put(1,1);
         var bits:int = nbits([sx,sy]);
         w.put(bits,5);
         putSigned(w,sx,bits);
         putSigned(w,sy,bits);
         var r0:Number = pyRound(bb * 65536);
         var r1:Number = pyRound(c * 65536);
         if(r0 != 0 || r1 != 0)
         {
            w.put(1,1);
            bits = nbits([r0,r1]);
            w.put(bits,5);
            putSigned(w,r0,bits);
            putSigned(w,r1,bits);
         }
         else
         {
            w.put(0,1);
         }
         var x:Number = pyRound(tx * 20);
         var y:Number = pyRound(ty * 20);
         bits = nbits([x,y]);
         w.put(bits,5);
         putSigned(w,x,bits);
         putSigned(w,y,bits);
         return w.done();
      }

      public static function iconSprite(iconId:int, parts:Array, boundsOf:BmodSwf, target:Array, fit:Object, fill:Number,
         drop:Number, centre:Array) : ByteArray
      {
         var box:Array = null;
         for each(var part:Array in parts)
         {
            var cb:Array = boundsOf.boundsOf(int(part[0]));
            if(cb != null && !(fit != null && !(("s" + part[0]) in fit)))
            {
               box = addBox(box,cb,part[1]);
            }
         }
         if(box == null)
         {
            return null;
         }
         var scale:Number = fill * Math.min((target[2] - target[0]) / Math.max(0.000001,box[2] - box[0]),
            (target[3] - target[1]) / Math.max(0.000001,box[3] - box[1]));
         var cx:Number = centre != null ? Number(centre[0]) : (target[0] + target[2]) / 2;
         var cy:Number = centre != null ? Number(centre[1]) : (target[1] + target[3]) / 2;
         var ox:Number = cx - scale * (box[0] + box[2]) / 2;
         var oy:Number = cy - scale * (box[1] + box[3]) / 2 + drop * (target[3] - target[1]);
         var inner:ByteArray = new ByteArray();
         var depth:int = 1;
         for each(part in parts)
         {
            var m:Array = part[1];
            var place:ByteArray = new ByteArray();
            place.writeByte(0x06);
            writeU16(place,depth);
            writeU16(place,int(part[0]));
            place.writeBytes(writeMatrix(m[0] * scale,m[1] * scale,m[2] * scale,m[3] * scale,m[4] * scale + ox,m[5] * scale + oy));
            inner.writeBytes(tagBytes(26,place));
            depth++;
         }
         inner.writeBytes(tagBytes(SHOW_FRAME,new ByteArray()));
         inner.writeBytes(tagBytes(END,new ByteArray()));
         var out:ByteArray = new ByteArray();
         writeU16(out,iconId);
         writeU16(out,1);
         out.writeBytes(inner);
         return out;
      }

      public static function maxCharacterId(tags:Array) : int
      {
         var best:int = 0;
         for each(var t:Object in tags)
         {
            if(CHARACTER_TAGS.indexOf(int(t.code)) >= 0 && id(t) > best)
            {
               best = id(t);
            }
         }
         return best;
      }

      private var abc:ByteArray;

      private var ints:Array;

      private var strings:Array;

      private var namespaces:Array;

      private var multinames:Array;

      private var frameScripts:Object;

      private var bodies:Object;

      private var classNames:Array;

      private function abcU30() : int
      {
         var result:int = 0;
         var shift:int = 0;
         while(true)
         {
            var bt:int = int(abc[p]);
            p++;
            result = result | ((bt & 0x7F) << shift);
            if((bt & 0x80) == 0 || shift >= 28)
            {
               break;
            }
            shift += 7;
         }
         return result;
      }

      private function abcByte() : int
      {
         var bt:int = int(abc[p]);
         p++;
         return bt;
      }

      private function plainName(index:int) : String
      {
         return index > 0 && index < multinames.length ? strings[int(multinames[index][1])] : null;
      }

      private function qualified(index:int) : String
      {
         if(index <= 0 || index >= multinames.length)
         {
            return null;
         }
         var m:Array = multinames[index];
         var name:String = strings[int(m[1])];
         var ns:String = int(m[0]) > 0 && int(m[0]) < namespaces.length ? strings[int(namespaces[int(m[0])])] : "";
         return ns == null || ns == "" ? name : ns + "." + name;
      }

      private function traits(owner:String) : void
      {
         var count:int = abcU30();
         for(var i:int = 0; i < count; i++)
         {
            var name:int = abcU30();
            var kind:int = abcByte();
            var low:int = kind & 0x0F;
            if(low == 0 || low == 6)
            {
               abcU30();
               abcU30();
               if(abcU30() != 0)
               {
                  p++;
               }
            }
            else if(low == 1 || low == 2 || low == 3)
            {
               abcU30();
               var method:int = abcU30();
               if(owner != null && low == 1 && plainName(name) == "frame1")
               {
                  frameScripts["c" + owner] = method;
               }
            }
            else if(low == 4 || low == 5)
            {
               abcU30();
               abcU30();
            }
            else
            {
               throw new Error("unknown ABC trait kind " + kind);
            }
            if((kind & 0x40) != 0)
            {
               var meta:int = abcU30();
               for(var j:int = 0; j < meta; j++)
               {
                  abcU30();
               }
            }
         }
      }

      private function parseAbc() : void
      {
         p += 4;
         ints = [0];
         strings = [""];
         namespaces = [0];
         multinames = [[0,0]];
         frameScripts = {};
         bodies = {};
         classNames = [];
         var count:int = abcU30();
         var i:int = 0;
         var j:int = 0;
         for(i = 1; i < count; i++)
         {
            ints.push(abcU30());
         }
         count = abcU30();
         for(i = 1; i < count; i++)
         {
            abcU30();
         }
         count = abcU30();
         for(i = 1; i < count; i++)
         {
            p += 8;
         }
         count = abcU30();
         for(i = 1; i < count; i++)
         {
            var len:int = abcU30();
            abc.position = p;
            strings.push(abc.readUTFBytes(len));
            p += len;
         }
         count = abcU30();
         for(i = 1; i < count; i++)
         {
            p++;
            namespaces.push(abcU30());
         }
         count = abcU30();
         for(i = 1; i < count; i++)
         {
            var sets:int = abcU30();
            for(j = 0; j < sets; j++)
            {
               abcU30();
            }
         }
         count = abcU30();
         for(i = 1; i < count; i++)
         {
            var kind:int = abcByte();
            if(kind == 0x07 || kind == 0x0D)
            {
               var ns:int = abcU30();
               multinames.push([ns,abcU30()]);
            }
            else if(kind == 0x0F || kind == 0x10)
            {
               multinames.push([0,abcU30()]);
            }
            else if(kind == 0x11 || kind == 0x12)
            {
               multinames.push([0,0]);
            }
            else if(kind == 0x09 || kind == 0x0E)
            {
               var mn:int = abcU30();
               abcU30();
               multinames.push([0,mn]);
            }
            else if(kind == 0x1B || kind == 0x1C)
            {
               abcU30();
               multinames.push([0,0]);
            }
            else if(kind == 0x1D)
            {
               var base:int = abcU30();
               var params:int = abcU30();
               for(j = 0; j < params; j++)
               {
                  abcU30();
               }
               multinames.push([0,base < multinames.length ? int(multinames[base][1]) : 0]);
            }
            else
            {
               throw new Error("unknown ABC multiname kind " + kind);
            }
         }
         count = abcU30();
         for(i = 0; i < count; i++)
         {
            var paramCount:int = abcU30();
            abcU30();
            for(j = 0; j < paramCount; j++)
            {
               abcU30();
            }
            abcU30();
            var flags:int = abcByte();
            if((flags & 0x08) != 0)
            {
               var options:int = abcU30();
               for(j = 0; j < options; j++)
               {
                  abcU30();
                  p++;
               }
            }
            if((flags & 0x80) != 0)
            {
               for(j = 0; j < paramCount; j++)
               {
                  abcU30();
               }
            }
         }
         count = abcU30();
         for(i = 0; i < count; i++)
         {
            abcU30();
            var items:int = abcU30();
            for(j = 0; j < items * 2; j++)
            {
               abcU30();
            }
         }
         var classCount:int = abcU30();
         for(i = 0; i < classCount; i++)
         {
            var name:String = qualified(abcU30());
            classNames.push(name);
            abcU30();
            var iflags:int = abcByte();
            if((iflags & 0x08) != 0)
            {
               abcU30();
            }
            var interfaces:int = abcU30();
            for(j = 0; j < interfaces; j++)
            {
               abcU30();
            }
            abcU30();
            traits(name);
         }
         for(i = 0; i < classCount; i++)
         {
            abcU30();
            traits(null);
         }
         count = abcU30();
         for(i = 0; i < count; i++)
         {
            abcU30();
            traits(null);
         }
         count = abcU30();
         for(i = 0; i < count; i++)
         {
            var method:int = abcU30();
            for(j = 0; j < 4; j++)
            {
               abcU30();
            }
            var length:int = abcU30();
            bodies["m" + method] = p;
            p += length;
            var exceptions:int = abcU30();
            for(j = 0; j < exceptions * 5; j++)
            {
               abcU30();
            }
            traits(null);
         }
      }

      private function palette(start:int) : Array
      {
         p = start;
         var length:int = abcU30();
         var stop:int = p + length;
         var stack:Array = [];
         while(p < stop)
         {
            var op:int = abcByte();
            if(op == 0xD0 || op == 0xD1 || op == 0xD2 || op == 0xD3)
            {
               stack.push(null);
            }
            else if(op == 0x30 || op == 0x29)
            {
               stack.pop();
            }
            else if(op == 0x24)
            {
               var bt:int = abcByte();
               stack.push(bt >= 0x80 ? bt - 0x100 : bt);
            }
            else if(op == 0x25)
            {
               var sv:int = abcU30();
               stack.push(sv >= 0x8000 && sv < 0x10000 ? sv - 0x10000 : sv);
            }
            else if(op == 0x2D)
            {
               stack.push(ints[abcU30()]);
            }
            else if(op == 0x2E || op == 0x2F)
            {
               abcU30();
               stack.push(0);
            }
            else if(op == 0x56)
            {
               var count:int = abcU30();
               if(count > stack.length)
               {
                  return null;
               }
               stack.push(stack.splice(stack.length - count,count));
            }
            else if(op == 0x68 || op == 0x61)
            {
               var name:String = plainName(abcU30());
               var value:* = stack.pop();
               stack.pop();
               if(name == "a" && value is Array)
               {
                  return value as Array;
               }
            }
            else if(op == 0x5D || op == 0x5E || op == 0x60)
            {
               abcU30();
               stack.push(null);
            }
            else if(op == 0x66)
            {
               abcU30();
               stack.pop();
               stack.push(null);
            }
            else if(op == 0x46 || op == 0x4F)
            {
               abcU30();
               var args:int = abcU30();
               if(args + 1 > stack.length)
               {
                  return null;
               }
               stack.splice(stack.length - args - 1,args + 1);
               if(op == 0x46)
               {
                  stack.push(null);
               }
            }
            else if(op == 0x20 || op == 0x21 || op == 0x26 || op == 0x27 || op == 0x28)
            {
               stack.push(null);
            }
            else if(op == 0x2C)
            {
               stack.push(strings[abcU30()]);
            }
            else if(op == 0xF0 || op == 0xF1 || op == 0x80)
            {
               abcU30();
            }
            else if(op == 0xEF)
            {
               p++;
               abcU30();
               p++;
               abcU30();
            }
            else if(op == 0x2A)
            {
               stack.push(stack[stack.length - 1]);
            }
            else if(!(op == 0x82 || op == 0x85 || op == 0x73 || op == 0x74 || op == 0x75 || op == 0x88 || op == 0x89))
            {
               return null;
            }
         }
         return null;
      }

      public static function abcClasses(tags:Array, into:Object) : void
      {
         for each(var t:Object in tags)
         {
            var src:ByteArray = t.src;
            var start:int = -1;
            var code:int = int(t.code);
            var limit:int = int(t.pos) + int(t.len);
            if(code == DO_ABC)
            {
               start = int(t.pos) + 4;
               while(start < limit && int(src[start]) != 0)
               {
                  start++;
               }
               start++;
            }
            else if(code == 72)
            {
               start = int(t.pos);
            }
            if(start < 0)
            {
               continue;
            }
            var r:BmodSwf = new BmodSwf(null,0);
            r.abc = src;
            r.p = start;
            try
            {
               r.parseAbc();
            }
            catch(e:Error)
            {
               continue;
            }
            for each(var name:String in r.classNames)
            {
               if(name == null)
               {
                  continue;
               }
               var list:Array = null;
               if((("c" + name) in r.frameScripts) && (("m" + r.frameScripts["c" + name]) in r.bodies))
               {
                  try
                  {
                     list = r.palette(int(r.bodies["m" + r.frameScripts["c" + name]]));
                  }
                  catch(e2:Error)
                  {
                     list = null;
                  }
               }
               if(!(("c" + name) in into) || list != null)
               {
                  into["c" + name] = list;
               }
            }
         }
      }

      private static function u30(out:ByteArray, v:int) : void
      {
         while(true)
         {
            var bt:int = v & 0x7F;
            v = v >>> 7;
            if(v != 0)
            {
               out.writeByte(bt | 0x80);
            }
            else
            {
               out.writeByte(bt);
               return;
            }
         }
      }

      private var poolIndex:Object;

      private function str(s:String) : int
      {
         if(!(("s" + s) in poolIndex))
         {
            poolIndex["s" + s] = strings.length;
            strings.push(s);
         }
         return int(poolIndex["s" + s]);
      }

      private function nsIndex(kind:int, name:String) : int
      {
         var k:String = "n" + kind + ":" + name;
         if(!(k in poolIndex))
         {
            poolIndex[k] = namespaces.length;
            namespaces.push([kind,str(name)]);
         }
         return int(poolIndex[k]);
      }

      private function qname(nsKind:int, nsName:String, name:String) : int
      {
         var ns:int = nsIndex(nsKind,nsName);
         var k:String = "q" + ns + ":" + name;
         if(!(k in poolIndex))
         {
            poolIndex[k] = multinames.length;
            multinames.push([ns,str(name)]);
         }
         return int(poolIndex[k]);
      }

      private function integer(v:int) : int
      {
         var k:String = "i" + v;
         if(!(k in poolIndex))
         {
            poolIndex[k] = ints.length;
            ints.push(v);
         }
         return int(poolIndex[k]);
      }

      private static function ops(code:ByteArray, list:Array) : void
      {
         for each(var op:int in list)
         {
            code.writeByte(op);
         }
      }

      public static function abcBlock(classes:Array, colours:Object) : ByteArray
      {
         var w:BmodSwf = new BmodSwf(null,0);
         w.strings = [""];
         w.namespaces = [null];
         w.multinames = [null];
         w.ints = [null];
         w.poolIndex = {};
         var pkg:int = 0x16;
         var internalNs:int = 0x17;
         var protectedNs:int = 0x18;
         var bases:Array = [["","Object"],["flash.events","EventDispatcher"],["flash.display","DisplayObject"],
            ["flash.display","InteractiveObject"],["flash.display","DisplayObjectContainer"],["flash.display","Sprite"],
            ["flash.display","MovieClip"]];
         var methods:int = 0;
         var bodyList:Array = [];
         var instances:ByteArray = new ByteArray();
         var classInfos:ByteArray = new ByteArray();
         var scripts:ByteArray = new ByteArray();
         var movieClip:int = w.qname(pkg,"flash.display","MovieClip");
         var slotA:int = w.qname(pkg,"","a");
         var arrayType:int = w.qname(pkg,"","Array");
         var frame1:int = w.qname(internalNs,"","frame1");
         var addFrameScript:int = w.qname(pkg,"","addFrameScript");
         for(var ci:int = 0; ci < classes.length; ci++)
         {
            var name:String = classes[ci];
            var list:Array = (("c" + name) in colours) ? (colours["c" + name] as Array) : null;
            var self:int = w.qname(pkg,"",name);
            var iinit:int = methods;
            methods++;
            var code:ByteArray = new ByteArray();
            ops(code,[0xD0,0x30,0xD0,0x49]);
            u30(code,0);
            if(list != null)
            {
               code.writeByte(0x5D);
               u30(code,addFrameScript);
               ops(code,[0x24,0,0xD0,0x66]);
               u30(code,frame1);
               code.writeByte(0x4F);
               u30(code,addFrameScript);
               u30(code,2);
            }
            code.writeByte(0x47);
            bodyList.push([iinit,3,1,10,11,code]);
            var frameMethod:int = -1;
            if(list != null)
            {
               frameMethod = methods;
               methods++;
               code = new ByteArray();
               ops(code,[0xD0,0x30,0xD0]);
               for each(var colour:int in list)
               {
                  code.writeByte(0x2D);
                  u30(code,w.integer(colour));
               }
               code.writeByte(0x56);
               u30(code,list.length);
               code.writeByte(0x68);
               u30(code,slotA);
               code.writeByte(0x47);
               bodyList.push([frameMethod,list.length + 1 > 2 ? list.length + 1 : 2,1,10,11,code]);
            }
            var cinit:int = methods;
            methods++;
            code = new ByteArray();
            ops(code,[0xD0,0x30,0x47]);
            bodyList.push([cinit,1,1,9,10,code]);
            var sinit:int = methods;
            methods++;
            code = new ByteArray();
            ops(code,[0xD0,0x30,0x65,0]);
            for each(var base:Array in bases)
            {
               code.writeByte(0x60);
               u30(code,w.qname(pkg,base[0],base[1]));
               code.writeByte(0x30);
            }
            code.writeByte(0x60);
            u30(code,movieClip);
            code.writeByte(0x58);
            u30(code,ci);
            for(var k:int = 0; k < bases.length; k++)
            {
               code.writeByte(0x1D);
            }
            code.writeByte(0x68);
            u30(code,self);
            code.writeByte(0x47);
            bodyList.push([sinit,2,1,1,9,code]);
            u30(instances,self);
            u30(instances,movieClip);
            instances.writeByte(0x08);
            u30(instances,w.nsIndex(protectedNs,name));
            u30(instances,0);
            u30(instances,iinit);
            u30(instances,list != null ? 2 : 1);
            u30(instances,slotA);
            instances.writeByte(0);
            u30(instances,0);
            u30(instances,arrayType);
            u30(instances,0);
            if(list != null)
            {
               u30(instances,frame1);
               instances.writeByte(1);
               u30(instances,0);
               u30(instances,frameMethod);
            }
            u30(classInfos,cinit);
            u30(classInfos,0);
            u30(scripts,sinit);
            u30(scripts,1);
            u30(scripts,self);
            scripts.writeByte(4);
            u30(scripts,1);
            u30(scripts,ci);
         }
         var out:ByteArray = new ByteArray();
         ops(out,[16,0,46,0]);
         u30(out,w.ints.length > 1 ? w.ints.length : 0);
         var i:int = 0;
         for(i = 1; i < w.ints.length; i++)
         {
            u30(out,int(w.ints[i]));
         }
         u30(out,0);
         u30(out,0);
         u30(out,w.strings.length);
         for(i = 1; i < w.strings.length; i++)
         {
            var utf:ByteArray = new ByteArray();
            utf.writeUTFBytes(String(w.strings[i]));
            u30(out,utf.length);
            out.writeBytes(utf);
         }
         u30(out,w.namespaces.length);
         for(i = 1; i < w.namespaces.length; i++)
         {
            out.writeByte(int(w.namespaces[i][0]));
            u30(out,int(w.namespaces[i][1]));
         }
         u30(out,0);
         u30(out,w.multinames.length);
         for(i = 1; i < w.multinames.length; i++)
         {
            out.writeByte(0x07);
            u30(out,int(w.multinames[i][0]));
            u30(out,int(w.multinames[i][1]));
         }
         u30(out,methods);
         for(i = 0; i < methods; i++)
         {
            ops(out,[0,0,0,0]);
         }
         u30(out,0);
         u30(out,classes.length);
         out.writeBytes(instances);
         out.writeBytes(classInfos);
         u30(out,classes.length);
         out.writeBytes(scripts);
         u30(out,bodyList.length);
         for each(var mb:Array in bodyList)
         {
            for(k = 0; k < 5; k++)
            {
               u30(out,int(mb[k]));
            }
            var c:ByteArray = mb[5];
            u30(out,c.length);
            out.writeBytes(c);
            u30(out,0);
            u30(out,0);
         }
         return out;
      }

      private static function anmString(z:ByteArray) : String
      {
         var len:int = z.readUnsignedShort();
         return len > 0 ? z.readUTFBytes(len) : "";
      }

      public static function headshotFrame(file:ByteArray) : Array
      {
         var z:ByteArray = new ByteArray();
         z.writeBytes(file,4,file.length - 4);
         z.uncompress();
         z.endian = Endian.LITTLE_ENDIAN;
         z.position = 0;
         while(z.readBoolean())
         {
            anmString(z);
            var index:String = anmString(z);
            anmString(z);
            var count:int = int(z.readUnsignedInt());
            for(var a:int = 0; a < count; a++)
            {
               var name:String = anmString(z);
               var frames:int = int(z.readUnsignedInt());
               for(var k:int = 0; k < 5; k++)
               {
                  z.readUnsignedInt();
               }
               var dataCount:int = int(z.readUnsignedInt());
               z.position = z.position + dataCount * 4;
               var size:int = int(z.readUnsignedInt());
               var start:int = z.position;
               if(index == "a__HeadShotAnimation" && name == "FaceIdle" && frames > 0)
               {
                  return readFrame(z);
               }
               z.position = start + size;
            }
         }
         return null;
      }

      private static function readFrame(z:ByteArray) : Array
      {
         z.readShort();
         for(var k:int = 0; k < 2; k++)
         {
            if(z.readBoolean())
            {
               z.readDouble();
               z.readDouble();
            }
         }
         var count:int = z.readShort();
         var bones:Array = [];
         for(var i:int = 0; i < count; i++)
         {
            if(z.readBoolean())
            {
               if(!z.readBoolean())
               {
                  z.readByte();
               }
               bones.push({"dup":true});
               continue;
            }
            var bone:Object = {"id":int(z.readShort())};
            var opaque:Boolean = z.readBoolean();
            if(z.readBoolean())
            {
               bone.transform = "prev";
            }
            else
            {
               var flags:Boolean = z.readBoolean();
               var kind:String = "full";
               if(flags)
               {
                  kind = z.readBoolean() ? "identity" : "symmetric";
               }
               bone.transform = kind;
               if(kind == "symmetric")
               {
                  bone.m = [z.readFloat(),z.readFloat()];
               }
               else if(kind == "full")
               {
                  bone.m = [z.readFloat(),z.readFloat(),z.readFloat(),z.readFloat()];
               }
            }
            if(z.readBoolean())
            {
               bone.pos = "prev";
            }
            else
            {
               bone.pos = [z.readFloat(),z.readFloat()];
            }
            if(z.readBoolean())
            {
               z.readByte();
            }
            if(!opaque)
            {
               z.readUnsignedByte();
            }
            bones.push(bone);
         }
         return bones;
      }
   }
}
