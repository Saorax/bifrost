package bh.platform
{
   import flash.filesystem.File;
   import flash.filesystem.FileMode;
   import flash.filesystem.FileStream;
   import flash.utils.ByteArray;
   import flash.utils.Endian;

   public final class AviWriter
   {
      public static const PART_LIMIT:Number = 1000 * 1024 * 1024;

      private var out:FileStream;
      private var index:ByteArray;
      private var width:int;
      private var height:int;
      private var fps:int;
      private var moviStart:Number = 0;
      private var biggest:uint = 0;
      public var frames:uint = 0;
      public var bytes:Number = 0;
      public var file:File;

      public function AviWriter(file:File, width:int, height:int, fps:int)
      {
         this.file = file;
         this.width = width;
         this.height = height;
         this.fps = fps;
         index = new ByteArray();
         index.endian = Endian.LITTLE_ENDIAN;
         out = new FileStream();
         out.open(file,FileMode.WRITE);
         out.endian = Endian.LITTLE_ENDIAN;
         var h:ByteArray = header();
         out.writeBytes(h);
         moviStart = h.length - 4;
         bytes = h.length;
      }

      private function header() : ByteArray
      {
         var b:ByteArray = new ByteArray();
         b.endian = Endian.LITTLE_ENDIAN;
         fourcc(b,"RIFF");
         b.writeUnsignedInt(0);
         fourcc(b,"AVI ");
         fourcc(b,"LIST");
         b.writeUnsignedInt(4 + 64 + 12 + 64 + 48);
         fourcc(b,"hdrl");
         fourcc(b,"avih");
         b.writeUnsignedInt(56);
         b.writeUnsignedInt(uint(Math.round(1000000 / fps)));
         b.writeUnsignedInt(0);
         b.writeUnsignedInt(0);
         b.writeUnsignedInt(0x10);
         b.writeUnsignedInt(0);
         b.writeUnsignedInt(0);
         b.writeUnsignedInt(1);
         b.writeUnsignedInt(0);
         b.writeUnsignedInt(width);
         b.writeUnsignedInt(height);
         b.writeUnsignedInt(0);
         b.writeUnsignedInt(0);
         b.writeUnsignedInt(0);
         b.writeUnsignedInt(0);
         fourcc(b,"LIST");
         b.writeUnsignedInt(4 + 64 + 48);
         fourcc(b,"strl");
         fourcc(b,"strh");
         b.writeUnsignedInt(56);
         fourcc(b,"vids");
         fourcc(b,"MJPG");
         b.writeUnsignedInt(0);
         b.writeShort(0);
         b.writeShort(0);
         b.writeUnsignedInt(0);
         b.writeUnsignedInt(1);
         b.writeUnsignedInt(fps);
         b.writeUnsignedInt(0);
         b.writeUnsignedInt(0);
         b.writeUnsignedInt(0);
         b.writeUnsignedInt(0xFFFFFFFF);
         b.writeUnsignedInt(0);
         b.writeShort(0);
         b.writeShort(0);
         b.writeShort(width);
         b.writeShort(height);
         fourcc(b,"strf");
         b.writeUnsignedInt(40);
         b.writeUnsignedInt(40);
         b.writeInt(width);
         b.writeInt(height);
         b.writeShort(1);
         b.writeShort(24);
         fourcc(b,"MJPG");
         b.writeUnsignedInt(width * height * 3);
         b.writeUnsignedInt(0);
         b.writeUnsignedInt(0);
         b.writeUnsignedInt(0);
         b.writeUnsignedInt(0);
         fourcc(b,"LIST");
         b.writeUnsignedInt(0);
         fourcc(b,"movi");
         return b;
      }

      private static function fourcc(b:ByteArray, s:String) : void
      {
         for(var i:int = 0; i < 4; i++)
         {
            b.writeByte(s.charCodeAt(i));
         }
      }

      public function get full() : Boolean
      {
         return bytes >= PART_LIMIT;
      }

      public function add(jpeg:ByteArray) : void
      {
         var size:uint = jpeg.length;
         var offset:Number = bytes - moviStart;
         out.writeByte(0x30);
         out.writeByte(0x30);
         out.writeByte(0x64);
         out.writeByte(0x63);
         out.writeUnsignedInt(size);
         out.writeBytes(jpeg);
         var padded:uint = size + (size & 1);
         if(padded != size)
         {
            out.writeByte(0);
         }
         bytes += 8 + padded;
         index.writeByte(0x30);
         index.writeByte(0x30);
         index.writeByte(0x64);
         index.writeByte(0x63);
         index.writeUnsignedInt(0x10);
         index.writeUnsignedInt(uint(offset));
         index.writeUnsignedInt(size);
         if(size > biggest)
         {
            biggest = size;
         }
         frames++;
      }

      public function close() : void
      {
         if(out == null)
         {
            return;
         }
         var moviEnd:Number = bytes;
         out.writeByte(0x69);
         out.writeByte(0x64);
         out.writeByte(0x78);
         out.writeByte(0x31);
         out.writeUnsignedInt(index.length);
         out.writeBytes(index);
         bytes += 8 + index.length;
         out.close();
         var u:FileStream = new FileStream();
         u.open(file,FileMode.UPDATE);
         u.endian = Endian.LITTLE_ENDIAN;
         u.position = 4;
         u.writeUnsignedInt(uint(bytes - 8));
         u.position = 48;
         u.writeUnsignedInt(frames);
         u.position = 60;
         u.writeUnsignedInt(biggest + 8);
         u.position = 140;
         u.writeUnsignedInt(frames);
         u.position = 144;
         u.writeUnsignedInt(biggest + 8);
         u.position = moviStart - 4;
         u.writeUnsignedInt(uint(moviEnd - moviStart));
         u.close();
         out = null;
      }
   }
}
