module search.exact_search;

import std.stdio;
import search.interfaces;
import core.structures : WordEntry;

/**
 * 完全一致検索エンジン
 * 
 * 指定された単語と完全に一致する単語を検索する
 */
class ExactSearchEngine : ISearchEngine
{
    private SearchContext context;

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
     * 完全一致検索を実行する
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

        // 辞書から直接検索（高速）
        if (auto entryPtr = query in *context.wordDict)
        {
            auto entry = *entryPtr;

            // 削除チェック
            if (options.showDeleted || !entry.isDeleted)
            {
                matchedIDs ~= entry.id;
            }
        }

        long elapsedTime = timer.stop();

        // 結果をフィルタリング
        matchedIDs = filterResults(matchedIDs, context.idDict, options);

        return SearchResult(
            matchedIDs,
            elapsedTime,
            "完全一致検索",
            matchedIDs.length,
            false
        );
    }

    /**
     * 検索エンジンの名前を取得する
     */
    override string getName() const
    {
        return "ExactSearch";
    }

    /**
     * 検索の説明を取得する
     */
    override string getDescription() const
    {
        return "指定された単語と完全に一致する単語を検索します";
    }
}
