using System.Net;
using System.Net.Sockets;
using System.Buffers.Binary;

namespace BhRelay;

sealed class Grants
{
    readonly object gate = new();
    readonly Dictionary<ulong, (long Room, uint Player)> byToken = new();
    readonly Dictionary<(long Room, uint Player), ulong> tokenOf = new();
    readonly Dictionary<ulong, SocketAddress> addr = new();
    readonly Dictionary<ulong, (long Start, int Count, long Bytes, bool Logged)> window = new();
    public int MaxRate = 400, MaxBytes = 160_000;
    public long Dropped;
    long swept = Environment.TickCount64;

    public void Line(string text)
    {
        var p = text.Split(' ', StringSplitOptions.RemoveEmptyEntries);
        if (p.Length == 0) return;
        lock (gate)
        {
            if (p[0] == "GRANT" && p.Length == 4 && ulong.TryParse(p[1], out var token) && long.TryParse(p[2], out var room)
                && uint.TryParse(p[3], out var player))
            {
                if (tokenOf.TryGetValue((room, player), out var old) && old != token)
                {
                    byToken.Remove(old);
                    addr.Remove(old);
                }
                byToken[token] = (room, player);
                tokenOf[(room, player)] = token;
            }
            else if (p[0] == "REVOKE" && p.Length == 2 && ulong.TryParse(p[1], out var t))
            {
                if (byToken.Remove(t, out var who)) tokenOf.Remove(who);
                addr.Remove(t);
            }
            else if (p[0] == "CLOSE" && p.Length == 2 && long.TryParse(p[1], out var r))
            {
                foreach (var key in tokenOf.Keys.Where(k => k.Room == r).ToList())
                {
                    var tk = tokenOf[key];
                    tokenOf.Remove(key);
                    byToken.Remove(tk);
                    addr.Remove(tk);
                }
            }
        }
    }

    public int Count { get { lock (gate) return byToken.Count; } }

    public SocketAddress? Route(ulong token, byte kind, uint to, SocketAddress from, int size)
    {
        lock (gate)
        {
            if (!byToken.TryGetValue(token, out var who)) return null;
            if (!addr.TryGetValue(token, out var known) || !known.Equals(from))
            {
                var copy = new SocketAddress(from.Family, from.Size);
                from.Buffer.Span.CopyTo(copy.Buffer.Span);
                addr[token] = copy;
            }
            var now = Environment.TickCount64;
            if (!window.TryGetValue(token, out var w) || now - w.Start >= 1000) w = (now, 0, 0, w.Logged);
            w.Count++;
            w.Bytes += size;
            bool over = w.Count > MaxRate || w.Bytes > MaxBytes;
            if (over)
            {
                Dropped++;
                if (!w.Logged) Console.WriteLine($"relay: token {token:x16} over the cap ({MaxRate} datagrams / {MaxBytes} bytes a second): dropping its excess");
                w.Logged = true;
            }
            window[token] = w;
            if (now - swept >= 60_000)
            {
                swept = now;
                foreach (var t in window.Where(kv => now - kv.Value.Start >= 60_000).Select(kv => kv.Key).ToList()) window.Remove(t);
            }
            if (over) return null;
            if (kind != 0x10 || to == who.Player) return null;
            return tokenOf.TryGetValue((who.Room, to), out var target) && addr.TryGetValue(target, out var a) ? a : null;
        }
    }
}

static class Program
{
    const ushort Magic = 0xBF02;
    const int Header = 11, MaxDatagram = 1400;

    static int Main(string[] args)
    {
        string host = "0.0.0.0";
        int port = 0, control = 0, threads = Math.Clamp(Environment.ProcessorCount / 2, 1, 4);
        int maxRate = 400, maxBytes = 160_000;
        for (int i = 0; i + 1 < args.Length; i += 2)
        {
            switch (args[i])
            {
                case "--host": host = args[i + 1]; break;
                case "--port": port = int.Parse(args[i + 1]); break;
                case "--control": control = int.Parse(args[i + 1]); break;
                case "--threads": threads = Math.Max(1, int.Parse(args[i + 1])); break;
                case "--max-rate": maxRate = int.Parse(args[i + 1]); break;
                case "--max-bytes": maxBytes = int.Parse(args[i + 1]); break;
            }
        }
        var secret = Environment.GetEnvironmentVariable("BH_RELAY_SECRET") ?? "";
        if (port == 0 || control == 0 || secret.Length == 0)
        {
            Console.WriteLine("usage: bh-relay --host H --port P --control C (BH_RELAY_SECRET set)");
            return 2;
        }
        var grants = new Grants { MaxRate = maxRate, MaxBytes = maxBytes };
        new Thread(() => Control(control, secret, grants)) { IsBackground = true }.Start();

        var sock = new Socket(AddressFamily.InterNetwork, SocketType.Dgram, ProtocolType.Udp);
        if (OperatingSystem.IsWindows())
        {
            const int SIO_UDP_CONNRESET = -1744830452;
            sock.IOControl(SIO_UDP_CONNRESET, new byte[] { 0 }, null);
        }
        sock.ReceiveBufferSize = 4 << 20;
        sock.SendBufferSize = 4 << 20;
        sock.Bind(new IPEndPoint(IPAddress.Parse(host), port));
        Console.WriteLine($"relay (native) on UDP {host}:{port}, control 127.0.0.1:{control}, {threads} threads, cap {maxRate} datagrams / {maxBytes} bytes a second per token");
        for (int w = 0; w < threads; w++) new Thread(() => Serve(sock, grants)) { IsBackground = true }.Start();
        var last = Environment.TickCount64;
        while (true)
        {
            Thread.Sleep(10_000);
            var now = Environment.TickCount64;
            if (now - last >= 300_000)
            {
                Console.WriteLine($"relayed {Interlocked.Exchange(ref relayed, 0)} datagrams in the last {(now - last) / 1000} s ({grants.Count} tokens, {Interlocked.Read(ref grants.Dropped)} over the cap so far)");
                last = now;
            }
        }
    }

    static long relayed;

    static void Serve(Socket sock, Grants grants)
    {
        var buf = new byte[2048];
        var from = new SocketAddress(AddressFamily.InterNetwork);
        long mine = 0;
        while (true)
        {
            int n;
            try
            {
                n = sock.ReceiveFrom(buf, SocketFlags.None, from);
            }
            catch (SocketException)
            {
                continue;
            }
            if (n < Header || n > MaxDatagram || BinaryPrimitives.ReadUInt16BigEndian(buf) != Magic) continue;
            byte kind = buf[2];
            ulong token = ((ulong)BinaryPrimitives.ReadUInt32BigEndian(buf.AsSpan(3)) << 32) |
                          BinaryPrimitives.ReadUInt32BigEndian(buf.AsSpan(7));
            if (kind == 0x10 && n < Header + 4) continue;
            uint to = kind == 0x10 ? BinaryPrimitives.ReadUInt32BigEndian(buf.AsSpan(Header)) : 0;
            var target = grants.Route(token, kind, to, from, n);
            if (target == null) continue;
            try
            {
                sock.SendTo(buf.AsSpan(Header + 4, n - Header - 4), SocketFlags.None, target);
                if (++mine == 1024)
                {
                    Interlocked.Add(ref relayed, mine);
                    mine = 0;
                }
            }
            catch (SocketException)
            {
            }
        }
    }

    static void Control(int port, string secret, Grants grants)
    {
        var listener = new TcpListener(IPAddress.Loopback, port);
        listener.Server.SetSocketOption(SocketOptionLevel.Socket, SocketOptionName.ReuseAddress, true);
        listener.Start();
        while (true)
        {
            var client = listener.AcceptTcpClient();
            new Thread(() =>
            {
                using (client)
                using (var reader = new StreamReader(client.GetStream()))
                {
                    if (reader.ReadLine() != "AUTH " + secret)
                    {
                        Console.WriteLine("control: refused a connection (wrong secret)");
                        return;
                    }
                    Console.WriteLine("control: the server connected");
                    try
                    {
                        string? line;
                        while ((line = reader.ReadLine()) != null) grants.Line(line);
                    }
                    catch (IOException)
                    {
                    }
                    Console.WriteLine("control: the server disconnected (grants kept)");
                }
            }) { IsBackground = true }.Start();
        }
    }
}
