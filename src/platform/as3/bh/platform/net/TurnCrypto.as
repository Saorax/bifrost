package bh.platform.net
{
   import flash.utils.ByteArray;
   import flash.utils.Endian;

   public final class TurnCrypto
   {
      private static const MD5_SHIFT:Array = [7,12,17,22,5,9,14,20,4,11,16,23,6,10,15,21];
      private static var md5Table:Array = null;

      public function TurnCrypto()
      {
      }

      public static function utf8(text:String) : ByteArray
      {
         var b:ByteArray = new ByteArray();
         b.writeUTFBytes(text);
         return b;
      }

      public static function hex(b:ByteArray) : String
      {
         var out:String = "";
         for(var i:uint = 0; i < b.length; i++)
         {
            out += (b[i] < 16 ? "0" : "") + b[i].toString(16);
         }
         return out;
      }

      private static function rotl(x:int, n:int) : int
      {
         return x << n | x >>> 32 - n;
      }

      private static function padded(message:ByteArray, bigEndian:Boolean) : ByteArray
      {
         var b:ByteArray = new ByteArray();
         b.writeBytes(message,0,message.length);
         b.writeByte(0x80);
         while(b.length % 64 != 56)
         {
            b.writeByte(0);
         }
         var bits:Number = message.length * 8;
         var low:int = int(uint(bits % 4294967296));
         var high:int = int(uint(Math.floor(bits / 4294967296)));
         b.endian = bigEndian ? Endian.BIG_ENDIAN : Endian.LITTLE_ENDIAN;
         if(bigEndian)
         {
            b.writeInt(high);
            b.writeInt(low);
         }
         else
         {
            b.writeInt(low);
            b.writeInt(high);
         }
         b.position = 0;
         return b;
      }

      public static function md5(message:ByteArray) : ByteArray
      {
         var i:int;
         if(md5Table == null)
         {
            md5Table = [];
            for(i = 0; i < 64; i++)
            {
               md5Table.push(int(uint(Math.floor(Math.abs(Math.sin(i + 1)) * 4294967296))));
            }
         }
         var b:ByteArray = padded(message,false);
         var h0:int = 0x67452301;
         var h1:int = int(0xEFCDAB89);
         var h2:int = int(0x98BADCFE);
         var h3:int = 0x10325476;
         var m:Array = new Array(16);
         while(b.bytesAvailable > 0)
         {
            for(i = 0; i < 16; i++)
            {
               m[i] = b.readInt();
            }
            var a:int = h0;
            var bb:int = h1;
            var c:int = h2;
            var d:int = h3;
            for(i = 0; i < 64; i++)
            {
               var f:int;
               var g:int;
               if(i < 16)
               {
                  f = bb & c | ~bb & d;
                  g = i;
               }
               else if(i < 32)
               {
                  f = d & bb | ~d & c;
                  g = (5 * i + 1) % 16;
               }
               else if(i < 48)
               {
                  f = bb ^ c ^ d;
                  g = (3 * i + 5) % 16;
               }
               else
               {
                  f = c ^ (bb | ~d);
                  g = 7 * i % 16;
               }
               f = (f + a + int(md5Table[i]) + int(m[g])) | 0;
               a = d;
               d = c;
               c = bb;
               bb = (bb + rotl(f,int(MD5_SHIFT[(i >> 4) * 4 + (i & 3)]))) | 0;
            }
            h0 = (h0 + a) | 0;
            h1 = (h1 + bb) | 0;
            h2 = (h2 + c) | 0;
            h3 = (h3 + d) | 0;
         }
         var out:ByteArray = new ByteArray();
         out.endian = Endian.LITTLE_ENDIAN;
         out.writeInt(h0);
         out.writeInt(h1);
         out.writeInt(h2);
         out.writeInt(h3);
         out.endian = Endian.BIG_ENDIAN;
         out.position = 0;
         return out;
      }

      public static function sha1(message:ByteArray) : ByteArray
      {
         var b:ByteArray = padded(message,true);
         var h0:int = 0x67452301;
         var h1:int = int(0xEFCDAB89);
         var h2:int = int(0x98BADCFE);
         var h3:int = 0x10325476;
         var h4:int = int(0xC3D2E1F0);
         var w:Array = new Array(80);
         var i:int;
         while(b.bytesAvailable > 0)
         {
            for(i = 0; i < 16; i++)
            {
               w[i] = b.readInt();
            }
            for(i = 16; i < 80; i++)
            {
               w[i] = rotl(int(w[i - 3]) ^ int(w[i - 8]) ^ int(w[i - 14]) ^ int(w[i - 16]),1);
            }
            var a:int = h0;
            var bb:int = h1;
            var c:int = h2;
            var d:int = h3;
            var e:int = h4;
            for(i = 0; i < 80; i++)
            {
               var f:int;
               var k:int;
               if(i < 20)
               {
                  f = bb & c | ~bb & d;
                  k = 0x5A827999;
               }
               else if(i < 40)
               {
                  f = bb ^ c ^ d;
                  k = 0x6ED9EBA1;
               }
               else if(i < 60)
               {
                  f = bb & c | bb & d | c & d;
                  k = int(0x8F1BBCDC);
               }
               else
               {
                  f = bb ^ c ^ d;
                  k = int(0xCA62C1D6);
               }
               var t:int = (rotl(a,5) + f + e + k + int(w[i])) | 0;
               e = d;
               d = c;
               c = rotl(bb,30);
               bb = a;
               a = t;
            }
            h0 = (h0 + a) | 0;
            h1 = (h1 + bb) | 0;
            h2 = (h2 + c) | 0;
            h3 = (h3 + d) | 0;
            h4 = (h4 + e) | 0;
         }
         var out:ByteArray = new ByteArray();
         out.writeInt(h0);
         out.writeInt(h1);
         out.writeInt(h2);
         out.writeInt(h3);
         out.writeInt(h4);
         out.position = 0;
         return out;
      }

      public static function hmacSha1(key:ByteArray, message:ByteArray, length:int = -1) : ByteArray
      {
         var k:ByteArray = key.length > 64 ? sha1(key) : key;
         var inner:ByteArray = new ByteArray();
         var outer:ByteArray = new ByteArray();
         for(var i:int = 0; i < 64; i++)
         {
            var x:int = i < k.length ? k[i] : 0;
            inner.writeByte(x ^ 0x36);
            outer.writeByte(x ^ 0x5C);
         }
         inner.writeBytes(message,0,length < 0 ? message.length : length);
         outer.writeBytes(sha1(inner));
         return sha1(outer);
      }

      public static function longTermKey(username:String, realm:String, password:String) : ByteArray
      {
         return md5(utf8(username + ":" + realm + ":" + password));
      }
   }
}
