module search.prefix_search;

import std.stdio;
import std.algorithm;
import std.container : RedBlackTree;
import search.interfaces;
import core.structures : WordEntry;

/**
 * 前方一致検索エンジン
 * 
 * 指定されたプレフィックスで始まる単語を検索する
 */
class PrefixSearchEngine : ISearchEngine
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
     * 前方一致検索を実行する
     * 
     * Params:
     *      query = 検索クエリ（プレフィックス）
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

        // プレフィックスツリーにキャスト
        auto prefixTree = cast(RedBlackTree!string) context.prefixTree;
        if (prefixTree is null)
        {
            long elapsedTime = timer.stop();
            return SearchResult(matchedIDs, elapsedTime, "前方一致検索", 0, false);
        }

        // RedBlackTreeを使って効率的に検索
        foreach (word; prefixTree)
        {
            if (word.startsWith(query))
            {
                if (auto entryPtr = word in *context.wordDict)
                {
                    auto entry = *entryPtr;

                    // 削除チェック
                    if (options.showDeleted || !entry.isDeleted)
                    {
                        matchedIDs ~= entry.id;
                    }
                }
            }
            else if (word > query && !word.startsWith(query))
            {
                // キーより大きいけど前方一致しない場合は終了
                // (RedBlackTreeはソートされているため)
                break;
            }
        }

        long elapsedTime = timer.stop();

        // 結果をフィルタリングしてソート
        matchedIDs = filterResults(matchedIDs, context.idDict, options);
        matchedIDs.sort();

        return SearchResult(
            matchedIDs,
            elapsedTime,
            "前方一致検索",
            matchedIDs.length,
            false
        );
    }

    /**
     * 検索エンジンの名前を取得する
     */
    override string getName() const
    {
        return "PrefixSearch";
    }

    /**
     * 検索の説明を取得する
     */
    override string getDescription() const
    {
        return "指定されたプレフィックスで始まる単語を検索します";
    }
}
