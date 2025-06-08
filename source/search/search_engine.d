module search.search_engine;

import std.stdio;
import std.string;
import std.algorithm;
import search.interfaces;
import search.exact_search;
import search.prefix_search;
import search.suffix_search;
import search.substring_search;
import search.similarity_search;
import search.result_display;
import core.structures : WordEntry;
import algorithms.bktree : BKTree;

/**
 * 統合検索エンジン
 * 
 * 複数の検索エンジンを管理し、統一的なインターフェースを提供する
 */
class SearchEngine
{
    private SearchContext context;
    private ResultDisplay resultDisplay;

    // 各検索エンジン
    private ExactSearchEngine exactSearch;
    private PrefixSearchEngine prefixSearch;
    private SuffixSearchEngine suffixSearch;
    private SubstringSearchEngine substringSearch;
    private SimilaritySearchEngine similaritySearch;

    /**
     * コンストラクタ
     * 
     * Params:
     *      context = 検索コンテキスト
     */
    this(SearchContext context)
    {
        this.context = context;
        this.resultDisplay = new ResultDisplay(context.idDict);

        // 各検索エンジンを初期化
        this.exactSearch = new ExactSearchEngine(context);
        this.prefixSearch = new PrefixSearchEngine(context);
        this.suffixSearch = new SuffixSearchEngine(context);
        this.substringSearch = new SubstringSearchEngine(context);
        this.similaritySearch = new SimilaritySearchEngine(context);
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
    SearchResult searchExact(string query, SearchOptions options = SearchOptions.init)
    {
        return exactSearch.search(query, options);
    }

    /**
     * 前方一致検索を実行する
     * 
     * Params:
     *      query = 検索クエリ
     *      options = 検索オプション
     * 
     * Returns:
     *      検索結果
     */
    SearchResult searchPrefix(string query, SearchOptions options = SearchOptions.init)
    {
        return prefixSearch.search(query, options);
    }

    /**
     * 後方一致検索を実行する
     * 
     * Params:
     *      query = 検索クエリ
     *      options = 検索オプション
     * 
     * Returns:
     *      検索結果
     */
    SearchResult searchSuffix(string query, SearchOptions options = SearchOptions.init)
    {
        return suffixSearch.search(query, options);
    }

    /**
     * 部分一致検索を実行する
     * 
     * Params:
     *      query = 検索クエリ
     *      options = 検索オプション
     * 
     * Returns:
     *      検索結果
     */
    SearchResult searchSubstring(string query, SearchOptions options = SearchOptions.init)
    {
        return substringSearch.search(query, options);
    }

    /**
     * 類似検索を実行する
     * 
     * Params:
     *      query = 検索クエリ
     *      options = 検索オプション
     * 
     * Returns:
     *      検索結果
     */
    SearchResult searchSimilar(string query, SearchOptions options = SearchOptions.init)
    {
        return similaritySearch.search(query, options);
    }

    /**
     * 拡張類似検索を実行する
     * 
     * Params:
     *      query = 検索クエリ
     *      options = 検索オプション
     * 
     * Returns:
     *      検索結果
     */
    SearchResult searchSimilarExtended(string query, SearchOptions options = SearchOptions.init)
    {
        return similaritySearch.searchExtended(query, options);
    }

    /**
     * AND検索を実行する
     * 
     * Params:
     *      keywords = 検索キーワードの配列
     *      options = 検索オプション
     * 
     * Returns:
     *      検索結果
     */
    SearchResult searchAND(string[] keywords, SearchOptions options = SearchOptions.init)
    {
        SearchTimer timer;
        timer.start();

        size_t[] matchedIDs;

        if (keywords.length < 2)
        {
            long elapsedTime = timer.stop();
            return SearchResult(matchedIDs, elapsedTime, "AND検索", 0, false);
        }

        // 全単語を検索
        foreach (id, entry; *context.idDict)
        {
            if (!options.showDeleted && entry.isDeleted)
                continue;

            bool allMatched = true;
            foreach (keyword; keywords)
            {
                if (!entry.word.canFind(keyword))
                {
                    allMatched = false;
                    break;
                }
            }

            if (allMatched)
            {
                matchedIDs ~= id;
            }
        }

        long elapsedTime = timer.stop();

        // 結果をフィルタリングしてソート
        matchedIDs = filterResults(matchedIDs, context.idDict, options);
        matchedIDs.sort();

        return SearchResult(
            matchedIDs,
            elapsedTime,
            "AND検索",
            matchedIDs.length,
            false
        );
    }

    /**
     * OR検索を実行する
     * 
     * Params:
     *      keywords = 検索キーワードの配列
     *      options = 検索オプション
     * 
     * Returns:
     *      検索結果
     */
    SearchResult searchOR(string[] keywords, SearchOptions options = SearchOptions.init)
    {
        SearchTimer timer;
        timer.start();

        size_t[] matchedIDs;

        if (keywords.length < 2)
        {
            long elapsedTime = timer.stop();
            return SearchResult(matchedIDs, elapsedTime, "OR検索", 0, false);
        }

        // 全単語を検索
        foreach (id, entry; *context.idDict)
        {
            if (!options.showDeleted && entry.isDeleted)
                continue;

            bool anyMatched = false;
            foreach (keyword; keywords)
            {
                if (entry.word.canFind(keyword))
                {
                    anyMatched = true;
                    break;
                }
            }

            if (anyMatched)
            {
                matchedIDs ~= id;
            }
        }

        long elapsedTime = timer.stop();

        // 結果をフィルタリングしてソート
        matchedIDs = filterResults(matchedIDs, context.idDict, options);
        matchedIDs.sort();

        return SearchResult(
            matchedIDs,
            elapsedTime,
            "OR検索",
            matchedIDs.length,
            false
        );
    }

    /**
     * NOT検索を実行する
     * 
     * Params:
     *      keyword = 除外するキーワード
     *      options = 検索オプション
     * 
     * Returns:
     *      検索結果
     */
    SearchResult searchNOT(string keyword, SearchOptions options = SearchOptions.init)
    {
        SearchTimer timer;
        timer.start();

        size_t[] matchedIDs;

        // 全単語を検索
        foreach (id, entry; *context.idDict)
        {
            if (!options.showDeleted && entry.isDeleted)
                continue;

            if (!entry.word.canFind(keyword))
            {
                matchedIDs ~= id;
            }
        }

        long elapsedTime = timer.stop();

        // 結果をフィルタリングしてソート
        matchedIDs = filterResults(matchedIDs, context.idDict, options);
        matchedIDs.sort();

        return SearchResult(
            matchedIDs,
            elapsedTime,
            "NOT検索",
            matchedIDs.length,
            false
        );
    }

    /**
     * 長さ検索を実行する
     * 
     * Params:
     *      length = 検索する長さ
     *      options = 検索オプション
     * 
     * Returns:
     *      検索結果
     */
    SearchResult searchByLength(size_t length, SearchOptions options = SearchOptions.init)
    {
        SearchTimer timer;
        timer.start();

        size_t[] matchedIDs;

        auto lengthIndex = cast(bool[size_t][size_t]*) context.lengthIndex;
        if (lengthIndex !is null && length in *lengthIndex)
        {
            foreach (id; (*lengthIndex)[length].keys)
            {
                if (id in *context.idDict)
                {
                    auto entry = (*context.idDict)[id];
                    if (options.showDeleted || !entry.isDeleted)
                    {
                        matchedIDs ~= id;
                    }
                }
            }
        }

        long elapsedTime = timer.stop();

        // 結果をフィルタリングしてソート
        matchedIDs = filterResults(matchedIDs, context.idDict, options);
        matchedIDs.sort();

        return SearchResult(
            matchedIDs,
            elapsedTime,
            "長さ検索",
            matchedIDs.length,
            false
        );
    }

    /**
     * 長さ範囲検索を実行する
     * 
     * Params:
     *      minLength = 最小長さ
     *      maxLength = 最大長さ
     *      options = 検索オプション
     * 
     * Returns:
     *      検索結果
     */
    SearchResult searchByLengthRange(size_t minLength, size_t maxLength, SearchOptions options = SearchOptions
            .init)
    {
        SearchTimer timer;
        timer.start();

        size_t[] matchedIDs;

        auto lengthIndex = cast(bool[size_t][size_t]*) context.lengthIndex;
        if (lengthIndex !is null)
        {
            for (size_t len = minLength; len <= maxLength; len++)
            {
                if (len in *lengthIndex)
                {
                    foreach (id; (*lengthIndex)[len].keys)
                    {
                        if (id in *context.idDict)
                        {
                            auto entry = (*context.idDict)[id];
                            if (options.showDeleted || !entry.isDeleted)
                            {
                                matchedIDs ~= id;
                            }
                        }
                    }
                }
            }
        }

        long elapsedTime = timer.stop();

        // 結果をフィルタリングしてソート
        matchedIDs = filterResults(matchedIDs, context.idDict, options);
        matchedIDs.sort();

        return SearchResult(
            matchedIDs,
            elapsedTime,
            "長さ範囲検索",
            matchedIDs.length,
            false
        );
    }

    /**
     * ID範囲検索を実行する
     * 
     * Params:
     *      minID = 最小ID
     *      maxID = 最大ID
     *      options = 検索オプション
     * 
     * Returns:
     *      検索結果
     */
    SearchResult searchByIDRange(size_t minID, size_t maxID, SearchOptions options = SearchOptions
            .init)
    {
        SearchTimer timer;
        timer.start();

        size_t[] matchedIDs;

        // ID範囲で検索
        for (size_t id = minID; id <= maxID; id++)
        {
            if (id in *context.idDict)
            {
                auto entry = (*context.idDict)[id];
                if (options.showDeleted || !entry.isDeleted)
                {
                    matchedIDs ~= id;
                }
            }
        }

        long elapsedTime = timer.stop();

        // 結果をフィルタリングしてソート
        matchedIDs = filterResults(matchedIDs, context.idDict, options);
        matchedIDs.sort();

        return SearchResult(
            matchedIDs,
            elapsedTime,
            "ID範囲検索",
            matchedIDs.length,
            false
        );
    }

    /**
     * 結果表示オブジェクトを取得する
     * 
     * Returns:
     *      結果表示オブジェクト
     */
    ResultDisplay getResultDisplay()
    {
        return resultDisplay;
    }

    /**
     * 類似検索エンジンを取得する
     * 
     * Returns:
     *      類似検索エンジン
     */
    SimilaritySearchEngine getSimilaritySearch()
    {
        return similaritySearch;
    }

    /**
     * 利用可能な検索エンジンの一覧を取得する
     * 
     * Returns:
     *      検索エンジンの配列
     */
    Object[] getAvailableEngines()
    {
        return [
            cast(Object) exactSearch,
            cast(Object) prefixSearch,
            cast(Object) suffixSearch,
            cast(Object) substringSearch,
            cast(Object) similaritySearch
        ];
    }
}
