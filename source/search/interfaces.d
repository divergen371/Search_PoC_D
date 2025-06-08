module search.interfaces;

import std.datetime.stopwatch : StopWatch;
import core.structures : WordEntry;

/**
 * 検索結果を表す構造体
 */
struct SearchResult
{
    size_t[] matchedIDs; // マッチしたIDの配列
    long elapsedTime; // 検索にかかった時間（マイクロ秒）
    string searchType; // 検索の種類
    size_t totalResults; // 結果の総数
    bool hasMore; // さらに結果があるかどうか
}

/**
 * 検索オプションを表す構造体
 */
struct SearchOptions
{
    size_t maxResults = 1000; // 最大結果数
    bool showDeleted = false; // 削除済みエントリを含むか
    bool caseSensitive = true; // 大文字小文字を区別するか
    size_t timeout = 30_000; // タイムアウト（ミリ秒）
}

/**
 * 類似検索の結果を表す構造体
 */
struct SimilarityResult
{
    size_t id; // 単語ID
    size_t distance; // 編集距離

    int opCmp(const SimilarityResult other) const
    {
        if (distance != other.distance)
            return distance < other.distance ? -1 : 1;
        if (id != other.id)
            return id < other.id ? -1 : 1;
        return 0;
    }
}

/**
 * 検索エンジンの基底インターフェース
 */
interface ISearchEngine
{
    /**
     * 検索を実行する
     * 
     * Params:
     *      query = 検索クエリ
     *      options = 検索オプション
     * 
     * Returns:
     *      検索結果
     */
    SearchResult search(string query, SearchOptions options = SearchOptions.init);

    /**
     * 検索エンジンの名前を取得する
     * 
     * Returns:
     *      検索エンジンの名前
     */
    string getName() const;

    /**
     * 検索エンジンがサポートする検索の説明を取得する
     * 
     * Returns:
     *      検索の説明
     */
    string getDescription() const;
}

/**
 * 検索コンテキストを表す構造体
 * 
 * 各検索エンジンが必要とする共通データを提供する
 */
struct SearchContext
{
    WordEntry[string]* wordDict; // 単語 -> エントリ
    WordEntry[size_t]* idDict; // ID -> エントリ
    void* prefixTree; // プレフィックスツリー（RedBlackTree!string）
    void* suffixTree; // サフィックスツリー（RedBlackTree!string）
    void* gramIndex; // N-gramインデックス
    void* lengthIndex; // 長さインデックス
    void* bkTree; // BK-Tree
}

/**
 * 検索時間を計測するヘルパー構造体
 */
struct SearchTimer
{
    private StopWatch sw;

    void start()
    {
        sw.reset();
        sw.start();
    }

    long stop()
    {
        sw.stop();
        return sw.peek.total!"usecs";
    }

    long elapsed() const
    {
        return sw.peek.total!"usecs";
    }
}

/**
 * 検索結果をフィルタリングするヘルパー関数
 * 
 * Params:
 *      results = フィルタリング対象の結果
 *      idDict = ID -> WordEntry のマッピング
 *      options = 検索オプション
 * 
 * Returns:
 *      フィルタリングされた結果
 */
size_t[] filterResults(size_t[] results, WordEntry[size_t]* idDict, SearchOptions options)
{
    import std.algorithm : filter;
    import std.array : array;

    // 削除済みエントリの処理
    auto filtered = results;
    if (!options.showDeleted)
    {
        filtered = results.filter!(id => id in *idDict && !(*idDict)[id].isDeleted).array;
    }

    // 最大結果数の制限
    if (filtered.length > options.maxResults)
    {
        filtered = filtered[0 .. options.maxResults];
    }

    return filtered;
}
