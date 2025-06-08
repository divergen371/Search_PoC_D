module search.substring_search;

import std.stdio;
import std.algorithm;
import std.array;
import search.interfaces;
import core.structures : WordEntry;
import core.index_types : GramIndexType;

/**
 * 部分一致検索エンジン
 * 
 * n-gramインデックスを使用して部分一致検索を行う
 */
class SubstringSearchEngine : ISearchEngine
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
     * 部分一致検索を実行する
     * 
     * Params:
     *      query = 検索クエリ（部分文字列）
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

        // n-gramインデックスにキャスト
        auto gramIndex = cast(GramIndexType[string]*) context.gramIndex;
        auto lengthIndex = cast(bool[size_t][size_t]*) context.lengthIndex;

        if (gramIndex is null || lengthIndex is null)
        {
            long elapsedTime = timer.stop();
            return SearchResult(matchedIDs, elapsedTime, "部分一致検索", 0, false);
        }

        if (query.length < 2)
        {
            // キー長1の場合は線形スキャン
            // 長さインデックスを活用する - 1文字の検索は特定の長さの単語にのみ検索
            foreach (len; (*lengthIndex).keys)
            {
                foreach (id; (*lengthIndex)[len].keys)
                {
                    if (id in *context.idDict)
                    {
                        auto entry = (*context.idDict)[id];
                        if ((options.showDeleted || !entry.isDeleted) && entry.word.canFind(query))
                        {
                            matchedIDs ~= id;
                        }
                    }
                }
            }
        }
        else
        {
            // 2文字以上の場合はn-gramインデックスを使用
            bool[size_t] candidateIDs; // 重複を排除するためのセット
            bool hasCandidate = false;

            // 初期gram
            string firstGram = query[0 .. 2];
            if (auto gramSetPtr = firstGram in *gramIndex)
            {
                // 最初のgramに含まれるIDをすべて候補に入れる
                foreach (id; gramSetPtr.keys())
                {
                    candidateIDs[id] = true;
                }
                hasCandidate = true;
            }

            // 残りのgramでフィルタリング
            if (hasCandidate)
            {
                for (size_t i = 1; i + 1 < query.length && candidateIDs.length > 0;
                    ++i)
                {
                    string gram = query[i .. i + 2];
                    if (auto gramSetPtr = gram in *gramIndex)
                    {
                        // 候補を絞り込む
                        foreach (id; candidateIDs.keys.dup)
                        {
                            if (!gramSetPtr.contains(id))
                            {
                                candidateIDs.remove(id);
                            }
                        }
                    }
                    else
                    {
                        // このgramがインデックスに存在しない場合、候補はゼロになる
                        candidateIDs.clear();
                        break;
                    }
                }
            }

            // 最終的な候補を確認（実際にsubstringが含まれるか）
            foreach (id; candidateIDs.keys)
            {
                if (id in *context.idDict)
                {
                    auto entry = (*context.idDict)[id];
                    if ((options.showDeleted || !entry.isDeleted) && entry.word.canFind(query))
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
            "部分一致検索",
            matchedIDs.length,
            false
        );
    }

    /**
     * 検索エンジンの名前を取得する
     */
    override string getName() const
    {
        return "SubstringSearch";
    }

    /**
     * 検索の説明を取得する
     */
    override string getDescription() const
    {
        return "n-gramインデックスを使用して部分一致検索を行います";
    }
}
