module search.suffix_search;

import std.stdio;
import std.algorithm;
import std.container : RedBlackTree;
import search.interfaces;
import core.structures : WordEntry;
import utils.string_utils : revStr;

/**
 * 後方一致検索エンジン
 * 
 * 指定されたサフィックスで終わる単語を検索する
 */
class SuffixSearchEngine : ISearchEngine
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
     * 後方一致検索を実行する
     * 
     * Params:
     *      query = 検索クエリ（サフィックス）
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

        // サフィックスツリーにキャスト
        auto suffixTree = cast(RedBlackTree!string) context.suffixTree;
        if (suffixTree is null)
        {
            long elapsedTime = timer.stop();
            return SearchResult(matchedIDs, elapsedTime, "後方一致検索", 0, false);
        }

        // サフィックス検索のため、クエリを逆順にする
        string reversedQuery = revStr(query);

        // RedBlackTreeを使って効率的に検索
        foreach (reversedWord; suffixTree)
        {
            if (reversedWord.startsWith(reversedQuery))
            {
                // 逆順の単語を元に戻す
                string originalWord = revStr(reversedWord);

                if (auto entryPtr = originalWord in *context.wordDict)
                {
                    auto entry = *entryPtr;

                    // 削除チェック
                    if (options.showDeleted || !entry.isDeleted)
                    {
                        matchedIDs ~= entry.id;
                    }
                }
            }
            else if (reversedWord > reversedQuery && !reversedWord.startsWith(reversedQuery))
            {
                // キーより大きいけど前方一致しない場合は終了
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
            "後方一致検索",
            matchedIDs.length,
            false
        );
    }

    /**
     * 検索エンジンの名前を取得する
     */
    override string getName() const
    {
        return "SuffixSearch";
    }

    /**
     * 検索の説明を取得する
     */
    override string getDescription() const
    {
        return "指定されたサフィックスで終わる単語を検索します";
    }
}
