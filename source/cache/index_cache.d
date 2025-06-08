module cache.index_cache;

import std.stdio;
import std.file;
import std.datetime;
import std.container : RedBlackTree;
import core.index_types : GramIndexType;

/**
 * インデックスキャッシュを管理する構造体
 *
 * プレフィックス・サフィックス・グラム・長さインデックスをバイナリ形式で
 * キャッシュファイルに保存・読み込みするための機能を提供します。
 * インデックス構築の高速化に寄与します。
 */
struct IndexCache
{
    string path; /// キャッシュファイルの絶対パス
    
    /**
     * コンストラクタ
     * 
     * Params:
     *      cachePath = キャッシュファイルのパス
     */
    this(string cachePath)
    {
        this.path = cachePath;
    }

    /**
     * キャッシュファイルが有効かどうかを判定する
     *
     * キャッシュファイルの最終更新時刻がCSVファイルより新しい場合に有効と判定します。
     *
     * Params:
     *      csvPath = 元のCSVファイルのパス
     *
     * Returns:
     *      キャッシュが有効な場合はtrue、無効な場合はfalse
     */
    bool isValid(string csvPath)
    {
        if (!exists(path))
            return false;
        if (!exists(csvPath))
            return true; // CSVファイルが存在しない場合はキャッシュを有効とみなす
        return timeLastModified(path) > timeLastModified(csvPath);
    }

    /**
     * プレフィックス・サフィックスインデックスをバイナリ形式でキャッシュに保存する
     *
     * Params:
     *      prefix = プレフィックス検索用のRedBlackTree
     *      suffix = サフィックス検索用のRedBlackTree
     */
    void save(RedBlackTree!string prefix, RedBlackTree!string suffix)
    {
        try
        {
            auto file = File(path, "wb");
            scope (exit)
                file.close();
            
            // magic number
            file.rawWrite(cast(const(ubyte[])) "LTC1");
            
            // prefix tree
            writeValue!uint(file, cast(uint) prefix.length);
            foreach (word; prefix)
            {
                ushort len = cast(ushort) word.length;
                writeValue!ushort(file, len);
                file.rawWrite(cast(const(ubyte[])) word);
            }
            
            // suffix tree
            writeValue!uint(file, cast(uint) suffix.length);
            foreach (word; suffix)
            {
                ushort len = cast(ushort) word.length;
                writeValue!ushort(file, len);
                file.rawWrite(cast(const(ubyte[])) word);
            }
        }
        catch (Exception e)
        {
            import std.stdio : writeln;
            writeln("キャッシュ保存中にエラーが発生しました: ", e.msg);
        }
    }

    /**
     * プレフィックス・サフィックスインデックスをキャッシュから読み込む
     *
     * Params:
     *      prefix = 読み込み先のプレフィックスツリー（出力）
     *      suffix = 読み込み先のサフィックスツリー（出力）
     *
     * Returns:
     *      読み込みに成功した場合はtrue、失敗した場合はfalse
     */
    bool load(out RedBlackTree!string prefix, out RedBlackTree!string suffix)
    {
        try
        {
            if (!exists(path))
                return false;
                
            auto file = File(path, "rb");
            scope (exit)
                file.close();
                
            ubyte[4] magic;
            file.rawRead(magic[]);
            if (magic != cast(ubyte[4]) "LTC1")
                return false;
            
            uint preCount;
            readValue!uint(file, preCount);
            prefix = new RedBlackTree!string;
            foreach (i; 0 .. preCount)
            {
                ushort len;
                readValue!ushort(file, len);
                char[] buf;
                buf.length = len;
                file.rawRead(cast(ubyte[]) buf);
                prefix.insert(cast(string) buf.idup);
            }
            
            uint sufCount;
            readValue!uint(file, sufCount);
            suffix = new RedBlackTree!string;
            foreach (i; 0 .. sufCount)
            {
                ushort len;
                readValue!ushort(file, len);
                char[] buf;
                buf.length = len;
                file.rawRead(cast(ubyte[]) buf);
                suffix.insert(cast(string) buf.idup);
            }
            
            return true;
        }
        catch (Exception e)
        {
            import std.stdio : writeln;
            writeln("キャッシュ読み込み中にエラーが発生しました: ", e.msg);
            return false;
        }
    }

    /**
     * 全インデックス（プレフィックス・サフィックス・グラム・長さ）をキャッシュに保存する
     *
     * Params:
     *      prefix = プレフィックス検索用のRedBlackTree
     *      suffix = サフィックス検索用のRedBlackTree
     *      gram = n-gram検索用のインデックス
     *      lenIdx = 長さ検索用のインデックス
     */
    void saveFull(
        RedBlackTree!string prefix,
        RedBlackTree!string suffix,
        GramIndexType[string] gram,
        bool[size_t][size_t] lenIdx)
    {
        try
        {
            auto file = File(path, "wb");
            scope (exit)
                file.close();
                
            file.rawWrite(cast(ubyte[]) "LTC2"); // 新しいmagic

            // prefix / suffix 既存ロジック
            writeValue!uint(file, cast(uint) prefix.length);
            foreach (w; prefix)
            {
                ushort l = cast(ushort) w.length;
                writeValue!ushort(file, l);
                file.rawWrite(cast(const(ubyte[])) w);
            }
            writeValue!uint(file, cast(uint) suffix.length);
            foreach (w; suffix)
            {
                ushort l = cast(ushort) w.length;
                writeValue!ushort(file, l);
                file.rawWrite(cast(const(ubyte[])) w);
            }

            // gramIndex
            writeValue!uint(file, cast(uint) gram.length);
            foreach (g, idsSet; gram)
            {
                ushort l = cast(ushort) g.length;
                writeValue!ushort(file, l);
                file.rawWrite(cast(const(ubyte[])) g);

                auto ids = idsSet.keys();
                writeValue!uint(file, cast(uint) ids.length);
                foreach (id; ids)
                    writeValue!uint(file, cast(uint) id);
            }

            // lengthIndex
            writeValue!uint(file, cast(uint) lenIdx.length);
            foreach (len, idMap; lenIdx)
            {
                writeValue!ushort(file, cast(ushort) len);
                auto ids = idMap.keys;
                writeValue!uint(file, cast(uint) ids.length);
                foreach (id; ids)
                    writeValue!uint(file, cast(uint) id);
            }
        }
        catch (Exception e)
        {
            import std.stdio : writeln;
            writeln("拡張キャッシュ保存中にエラーが発生しました: ", e.msg);
        }
    }

    /**
     * 全インデックス（プレフィックス・サフィックス・グラム・長さ）をキャッシュから読み込む
     *
     * Params:
     *      prefix = 読み込み先のプレフィックスツリー（出力）
     *      suffix = 読み込み先のサフィックスツリー（出力）
     *      gram = 読み込み先のn-gramインデックス（出力）
     *      lenIdx = 読み込み先の長さインデックス（出力）
     *
     * Returns:
     *      読み込みに成功した場合はtrue、失敗した場合はfalse
     */
    bool loadFull(out RedBlackTree!string prefix,
        out RedBlackTree!string suffix,
        ref GramIndexType[string] gram,
        ref bool[size_t][size_t] lenIdx)
    {
        try
        {
            if (!exists(path))
                return false;
                
            auto file = File(path, "rb");
            scope (exit)
                file.close();
                
            ubyte[4] mag;
            file.rawRead(mag[]);
            if (mag != cast(ubyte[4]) "LTC2")
                return false;

            uint preCnt;
            readValue!uint(file, preCnt);
            prefix = new RedBlackTree!string;
            foreach (i; 0 .. preCnt)
            {
                ushort l;
                readValue!ushort(file, l);
                char[] buf;
                buf.length = l;
                file.rawRead(cast(ubyte[]) buf);
                prefix.insert(cast(string) buf.idup);
            }

            uint sufCnt;
            readValue!uint(file, sufCnt);
            suffix = new RedBlackTree!string;
            foreach (i; 0 .. sufCnt)
            {
                ushort l;
                readValue!ushort(file, l);
                char[] buf;
                buf.length = l;
                file.rawRead(cast(ubyte[]) buf);
                suffix.insert(cast(string) buf.idup);
            }

            uint gramCnt;
            readValue!uint(file, gramCnt);
            gram.clear();
            foreach (i; 0 .. gramCnt)
            {
                ushort l;
                readValue!ushort(file, l);
                char[] buf;
                buf.length = l;
                file.rawRead(cast(ubyte[]) buf);
                string g = cast(string) buf.idup;
                uint idN;
                readValue!uint(file, idN);
                GramIndexType set;
                set.initialize(idN + 1);
                foreach (j; 0 .. idN)
                {
                    uint id;
                    readValue!uint(file, id);
                    set.add(id);
                }
                gram[g] = set;
            }

            uint lenCnt;
            readValue!uint(file, lenCnt);
            lenIdx.clear();
            foreach (i; 0 .. lenCnt)
            {
                ushort ln;
                readValue!ushort(file, ln);
                uint idN;
                readValue!uint(file, idN);
                if (ln !in lenIdx)
                    lenIdx[ln] = null;
                foreach (j; 0 .. idN)
                {
                    uint id;
                    readValue!uint(file, id);
                    lenIdx[ln][id] = true;
                }
            }

            return true;
        }
        catch (Exception e)
        {
            import std.stdio : writeln;
            writeln("拡張キャッシュ読み込み中にエラーが発生しました: ", e.msg);
            return false;
        }
    }
    
    /**
     * キャッシュファイルを削除する
     * 
     * Returns:
     *      削除に成功した場合はtrue
     */
    bool remove()
    {
        try
        {
            if (exists(path))
            {
                std.file.remove(path);
                return true;
            }
            return false;
        }
        catch (Exception e)
        {
            import std.stdio : writeln;
            writeln("キャッシュファイル削除中にエラーが発生しました: ", e.msg);
            return false;
        }
    }
    
    /**
     * キャッシュファイルのサイズを取得する（バイト）
     * 
     * Returns:
     *      ファイルサイズ。ファイルが存在しない場合は0
     */
    ulong getSize()
    {
        try
        {
            if (exists(path))
                return std.file.getSize(path);
            return 0;
        }
        catch (Exception e)
        {
            return 0;
        }
    }
    
    /**
     * キャッシュの統計情報を表示する
     */
    void displayStats()
    {
        import std.stdio : writefln;
        
        writeln("=== キャッシュ統計 ===");
        writefln("パス: %s", path);
        writefln("存在: %s", exists(path) ? "Yes" : "No");
        if (exists(path))
        {
            auto size = getSize();
            writefln("サイズ: %.2f KB", size / 1024.0);
            writefln("最終更新: %s", timeLastModified(path));
        }
        writeln("==================");
    }
}

// バイナリI/Oヘルパー関数

/**
 * 指定した型の値をバイナリ形式でファイルに書き込む
 *
 * 型Tの値をバイト配列に変換してファイルに直接書き込みます。
 * エンディアンに依存するため、同じアーキテクチャ間でのみ使用してください。
 *
 * Params:
 *      T = 書き込む値の型
 *      f = 書き込み先のファイル
 *      v = 書き込む値
 */
private void writeValue(T)(File f, T v)
{
    ubyte[T.sizeof] tmp;
    import core.stdc.string : memcpy;

    memcpy(tmp.ptr, &v, T.sizeof);
    f.rawWrite(tmp[]);
}

/**
 * 指定した型の値をバイナリ形式でファイルから読み込む
 *
 * ファイルからバイト配列を読み込み、型Tの値に変換します。
 * writeValueで書き込んだデータを読み込むために使用します。
 *
 * Params:
 *      T = 読み込む値の型
 *      f = 読み込み元のファイル
 *      v = 読み込み先の変数（参照）
 */
private void readValue(T)(File f, ref T v)
{
    ubyte[T.sizeof] tmp;
    f.rawRead(tmp[]);
    import core.stdc.string : memcpy;

    memcpy(&v, tmp.ptr, T.sizeof);
}

/**
 * キャッシュマネージャークラス
 * 
 * 複数のキャッシュファイルを管理するためのクラス
 */
class CacheManager
{
    private IndexCache[string] caches;
    
    /**
     * キャッシュを追加する
     * 
     * Params:
     *      name = キャッシュ名
     *      path = キャッシュファイルのパス
     */
    void addCache(string name, string path)
    {
        caches[name] = IndexCache(path);
    }
    
    /**
     * 指定した名前のキャッシュを取得する
     * 
     * Params:
     *      name = キャッシュ名
     * 
     * Returns:
     *      キャッシュオブジェクトへのポインタ。存在しない場合はnull
     */
    IndexCache* getCache(string name)
    {
        if (name in caches)
            return &caches[name];
        return null;
    }
    
    /**
     * すべてのキャッシュファイルを削除する
     */
    void removeAllCaches()
    {
        foreach (ref cache; caches.values)
        {
            cache.remove();
        }
    }
    
    /**
     * キャッシュの統計情報を表示する
     */
    void displayAllStats()
    {
        import std.stdio : writeln;
        
        writeln("=== 全キャッシュ統計 ===");
        foreach (name, ref cache; caches)
        {
            writefln("キャッシュ名: %s", name);
            cache.displayStats();
            writeln();
        }
        writeln("====================");
    }
} 

 