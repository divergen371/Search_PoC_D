module core.index_types;

import std.bitmanip : BitArray;
import std.algorithm : min;

/**
 * n-gram検索用のインデックス構造の最適化
 * ビット配列を使ったIDセット管理クラス
 *
 * この構造体は、単語IDのセットを効率的に管理するためのビットベースの実装です。
 * 検索処理の高速化とメモリ使用量の最適化を目的としています。
 */
struct GramIndexType
{
    private BitArray bits;
    private size_t maxID;

    /**
     * ビット配列を指定サイズで初期化する
     *
     * Params:
     *      maxSize = 初期化するビットアレイの最大サイズ（デフォルト1024）
     */
    void initialize(size_t maxSize = 1024)
    {
        // BitArrayの初期化
        auto storage = new size_t[(maxSize + 63) / 64 + 1];
        bits = BitArray(storage, maxSize);
        maxID = maxSize;
    }

    /**
     * IDをセットに追加する
     *
     * 必要に応じてビット配列のサイズを自動的に拡張します。
     *
     * Params:
     *      id = 追加するID
     */
    void add(size_t id)
    {
        // 必要に応じてサイズを拡張
        if (id >= maxID)
        {
            // 拡張時はより大きなビットアレイを作成
            size_t newSize = id + 1024;
            auto newStorage = new size_t[(newSize + 63) / 64 + 1];
            auto newBits = BitArray(newStorage, newSize);

            // 既存の値をコピー
            for (size_t i = 0; i < min(bits.length, newSize); i++)
            {
                if (i < bits.length && bits[i])
                    newBits[i] = true;
            }

            // 入れ替え
            bits = newBits;
            maxID = newSize;
        }

        if (id < bits.length)
            bits[id] = true;
    }

    /**
     * IDをセットから削除する
     *
     * Params:
     *      id = 削除するID
     */
    void remove(size_t id)
    {
        if (id < bits.length)
            bits[id] = false;
    }

    /**
     * 指定したIDがセットに含まれているか確認する
     *
     * Params:
     *      id = 確認するID
     *
     * Returns:
     *      IDが含まれている場合はtrue、そうでなければfalse
     */
    bool contains(size_t id) const
    {
        return id < bits.length && bits[id];
    }

    /**
     * セットに含まれるすべてのIDを配列として取得する
     *
     * Returns:
     *      セットに含まれるすべてのIDの配列
     */
    size_t[] keys() const
    {
        size_t[] result;
        for (size_t i = 0; i < bits.length; i++)
        {
            if (bits[i])
                result ~= i;
        }
        return result;
    }

    /**
     * セットに含まれるIDの数を取得する
     *
     * Returns:
     *      含まれるIDの数
     */
    size_t length() const
    {
        size_t count = 0;
        foreach (i; 0 .. bits.length)
        {
            if (bits[i])
                count++;
        }
        return count;
    }

    /**
     * セットからすべてのIDを削除する
     */
    void clear()
    {
        foreach (i; 0 .. bits.length)
            bits[i] = false;
    }

    /**
     * 指定されたIDセットとの論理積をとる
     *
     * 現在のセットと引数で指定されたセットの両方に存在するIDのみを残す
     *
     * Params:
     *      other = 交差するIDセット
     */
    void intersectWith(const ref GramIndexType other)
    {
        size_t minLength = min(bits.length, other.bits.length);
        for (size_t i = 0; i < minLength; i++)
        {
            bits[i] = bits[i] && other.bits[i];
        }

        // other より長い部分はfalseにする
        for (size_t i = minLength; i < bits.length; i++)
        {
            bits[i] = false;
        }
    }

    /**
     * 指定されたIDセットとの論理和をとる
     *
     * 現在のセットまたは引数で指定されたセットに存在するIDを含める
     *
     * Params:
     *      other = 結合するIDセット
     */
    void unionWith(const ref GramIndexType other)
    {
        // 必要に応じてサイズを拡張
        if (other.bits.length > bits.length)
        {
            size_t newSize = other.bits.length;
            auto newStorage = new size_t[(newSize + 63) / 64 + 1];
            auto newBits = BitArray(newStorage, newSize);

            // 既存の値をコピー
            for (size_t i = 0; i < bits.length; i++)
            {
                if (bits[i])
                    newBits[i] = true;
            }

            bits = newBits;
            maxID = newSize;
        }

        // 論理和を実行
        size_t minLength = min(bits.length, other.bits.length);
        for (size_t i = 0; i < minLength; i++)
        {
            bits[i] = bits[i] || other.bits[i];
        }
    }

    /**
     * in演算子のオーバーロード
     *
     * IDがセット内に存在するかを `id in set` の構文で確認できるようにする
     *
     * Params:
     *      id = 確認するID
     *
     * Returns:
     *      IDが含まれている場合はtrue、そうでなければfalse
     */
    auto opBinaryRight(string op : "in")(size_t id) const
    {
        return contains(id);
    }

    /**
     * 統計情報を取得する
     * 
     * Returns:
     *      インデックスの統計情報
     */
    IndexStatistics getStatistics() const
    {
        IndexStatistics stats;
        stats.totalCapacity = bits.length;
        stats.usedEntries = length();
        stats.utilizationRate = (stats.usedEntries * 100.0) / stats.totalCapacity;
        return stats;
    }
}

/**
 * インデックス統計情報を表す構造体
 */
struct IndexStatistics
{
    size_t totalCapacity; /// 総容量
    size_t usedEntries; /// 使用済みエントリ数
    double utilizationRate; /// 使用率（パーセント）

    /**
     * 統計情報を表示する
     */
    void display() const
    {
        import std.stdio : writefln;

        writefln("=== インデックス統計 ===");
        writefln("総容量: %d", totalCapacity);
        writefln("使用済み: %d", usedEntries);
        writefln("使用率: %.2f%%", utilizationRate);
        writefln("=====================");
    }
}

/**
 * ハッシュベースのIDセット（代替実装）
 * 
 * メモリ使用量が少ない場合やスパースなIDセットに適している
 */
struct HashIDSet
{
    private bool[size_t] idMap;

    /**
     * IDをセットに追加する
     */
    void add(size_t id)
    {
        idMap[id] = true;
    }

    /**
     * IDをセットから削除する
     */
    void remove(size_t id)
    {
        idMap.remove(id);
    }

    /**
     * 指定したIDがセットに含まれているか確認する
     */
    bool contains(size_t id) const
    {
        return (id in idMap) !is null;
    }

    /**
     * セットに含まれるすべてのIDを配列として取得する
     */
    size_t[] keys() const
    {
        return idMap.keys;
    }

    /**
     * セットに含まれるIDの数を取得する
     */
    size_t length() const
    {
        return idMap.length;
    }

    /**
     * セットからすべてのIDを削除する
     */
    void clear()
    {
        idMap.clear();
    }
}
