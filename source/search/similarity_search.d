module search.similarity_search;

import std.stdio;
import std.conv;
import std.algorithm;
import std.array : split;
import std.string : strip;
import search.interfaces;
import core.structures : WordEntry;
import algorithms.bktree : BKTree;

/**
 * 類似検索エンジン
 * 
 * BK-Treeを使用して編集距離による類似検索を行う
 */
class SimilaritySearchEngine : ISearchEngine
{
    private SearchContext context;
    private size_t defaultMaxDistance = 2;

    /**
     * コンストラクタ
     * 
     * Params:
     *      context = 検索コンテキスト
     */
    this(SearchContext context)
    {
        this.context = context;
    }

    /**
     * 類似検索を実行する
     * 
     * クエリフォーマット: "単語" または "単語,最大距離"
     * 
     * Params:
     *      query = 検索クエリ
     *      options = 検索オプション
     * 
     * Returns:
     *      検索結果
     */
    override SearchResult search(string query, SearchOptions options = SearchOptions.init)
    {
        SearchTimer timer;
        timer.start();

        size_t[] matchedIDs;

        // BK-Treeにキャスト
        auto bkTree = cast(BKTree) context.bkTree;
        if (bkTree is null)
        {
            long elapsedTime = timer.stop();
            return SearchResult(matchedIDs, elapsedTime, "類似検索", 0, false);
        }

        // クエリの解析（単語[,最大距離]）
        string searchWord;
        size_t maxDistance = defaultMaxDistance;

        auto queryParts = query.split(",");
        searchWord = queryParts[0].strip();

        if (queryParts.length >= 2)
        {
            try
            {
                maxDistance = to!size_t(queryParts[1].strip());
            }
            catch (Exception e)
            {
                // 無効な距離パラメータの場合はデフォルト値を使用
                maxDistance = defaultMaxDistance;
            }
        }

        // デバッグ情報を表示
        writefln("類似検索: 単語='%s', 最大距離=%d", searchWord, maxDistance);

        // BK-Treeを使用して類似検索
        auto results = bkTree.search(searchWord, maxDistance, false);

        writefln("BK-Tree検索結果: %d件", results.length);

        // 結果をSimilarityResultに変換
        foreach (r; results)
        {
            if (r.id in *context.idDict)
            {
                auto entry = (*context.idDict)[r.id];
                if (options.showDeleted || !entry.isDeleted)
                {
                    matchedIDs ~= r.id;
                }
            }
        }

        long elapsedTime = timer.stop();

        // 結果をフィルタリング
        matchedIDs = filterResults(matchedIDs, context.idDict, options);

        return SearchResult(
            matchedIDs,
            elapsedTime,
            "類似検索",
            matchedIDs.length,
            false
        );
    }

    /**
     * 拡張類似検索を実行する（より網羅的）
     * 
     * Params:
     *      query = 検索クエリ
     *      options = 検索オプション
     * 
     * Returns:
     *      検索結果
     */
    SearchResult searchExtended(string query, SearchOptions options = SearchOptions.init)
    {
        SearchTimer timer;
        timer.start();

        size_t[] matchedIDs;

        // BK-Treeにキャスト
        auto bkTree = cast(BKTree) context.bkTree;
        if (bkTree is null)
        {
            long elapsedTime = timer.stop();
            return SearchResult(matchedIDs, elapsedTime, "拡張類似検索", 0, false);
        }

        // クエリの解析
        string searchWord;
        size_t maxDistance = defaultMaxDistance;

        auto queryParts = query.split(",");
        searchWord = queryParts[0].strip();

        if (queryParts.length >= 2)
        {
            try
            {
                maxDistance = to!size_t(queryParts[1].strip());
            }
            catch (Exception e)
            {
                maxDistance = defaultMaxDistance;
            }
        }

        // BK-Treeを使用して拡張類似検索
        auto results = bkTree.search(searchWord, maxDistance, true); // 拡張モード

        // 結果を変換
        foreach (r; results)
        {
            if (r.id in *context.idDict)
            {
                auto entry = (*context.idDict)[r.id];
                if (options.showDeleted || !entry.isDeleted)
                {
                    matchedIDs ~= r.id;
                }
            }
        }

        long elapsedTime = timer.stop();

        // 結果をフィルタリング
        matchedIDs = filterResults(matchedIDs, context.idDict, options);

        return SearchResult(
            matchedIDs,
            elapsedTime,
            "拡張類似検索",
            matchedIDs.length,
            false
        );
    }

    /**
     * BK-Tree検索結果を取得する（詳細情報付き）
     * 
     * Params:
     *      query = 検索クエリ
     *      options = 検索オプション
     * 
     * Returns:
     *      BK-Tree検索結果の配列
     */
    BKTree.Result[] searchDetailed(string query, SearchOptions options = SearchOptions.init)
    {
        auto bkTree = cast(BKTree) context.bkTree;
        if (bkTree is null)
            return [];

        // クエリの解析
        string searchWord;
        size_t maxDistance = defaultMaxDistance;

        auto queryParts = query.split(",");
        searchWord = queryParts[0].strip();

        if (queryParts.length >= 2)
        {
            try
            {
                maxDistance = to!size_t(queryParts[1].strip());
            }
            catch (Exception e)
            {
                maxDistance = defaultMaxDistance;
            }
        }

        return bkTree.search(searchWord, maxDistance, false);
    }

    /**
     * 検索エンジンの名前を取得する
     */
    override string getName() const
    {
        return "SimilaritySearch";
    }

    /**
     * 検索の説明を取得する
     */
    override string getDescription() const
    {
        return "BK-Treeを使用して編集距離による類似検索を行います";
    }

    /**
     * デフォルトの最大距離を設定する
     * 
     * Params:
     *      distance = 新しいデフォルト最大距離
     */
    void setDefaultMaxDistance(size_t distance)
    {
        this.defaultMaxDistance = distance;
    }

    /**
     * デフォルトの最大距離を取得する
     * 
     * Returns:
     *      現在のデフォルト最大距離
     */
    size_t getDefaultMaxDistance() const
    {
        return defaultMaxDistance;
    }
}
