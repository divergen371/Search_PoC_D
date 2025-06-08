module search.result_display;

import std.stdio;
import std.conv;
import std.algorithm;
import core.structures : WordEntry;
import algorithms.bktree : BKTree;
import search.interfaces;

/**
 * 検索結果表示クラス
 * 
 * 様々な種類の検索結果を統一的に表示するためのクラス
 */
class ResultDisplay
{
    private WordEntry[size_t]* idDict;

    /**
     * コンストラクタ
     * 
     * Params:
     *      idDict = ID -> WordEntry のマッピング
     */
    this(WordEntry[size_t]* idDict)
    {
        this.idDict = idDict;
    }

    /**
     * 標準的な検索結果を表示する
     * 
     * Params:
     *      result = 検索結果
     */
    void displaySearchResult(SearchResult result)
    {
        displaySearchResults(result.matchedIDs, result.elapsedTime,
            result.searchType, true, false);
    }

    /**
     * 類似検索の結果を表示する
     * 
     * Params:
     *      results = 類似検索結果の配列
     *      elapsedTime = 検索にかかった時間（マイクロ秒）
     *      searchType = 検索の種類
     */
    void displaySimilarityResults(SimilarityResult[] results, long elapsedTime, string searchType)
    {
        if (results.length == 0)
        {
            writeln("該当なし");
            displaySearchTime(elapsedTime);
            return;
        }

        size_t activeCount = 0;

        foreach (r; results)
        {
            // 削除済みの単語はスキップ
            if (r.id in *idDict && !(*idDict)[r.id].isDeleted)
            {
                writefln("ID:%d  距離:%d  %s", r.id, r.distance, (*idDict)[r.id].word);
                activeCount++;
            }
        }

        writefln("合計: %d件 (%s)", activeCount, searchType);
        displaySearchTime(elapsedTime);
    }

    /**
     * BK-Tree検索結果を表示する
     * 
     * Params:
     *      results = BK-Tree検索結果
     *      elapsedTime = 検索にかかった時間
     *      searchType = 検索の種類
     */
    void displayBKTreeResults(BKTree.Result[] results, long elapsedTime, string searchType)
    {
        if (results.length == 0)
        {
            writeln("該当なし");
            displaySearchTime(elapsedTime);
            return;
        }

        size_t activeCount = 0;

        foreach (r; results)
        {
            // 削除済みの単語はスキップ
            if (r.id in *idDict && !(*idDict)[r.id].isDeleted)
            {
                writefln("ID:%d  距離:%d  %s", r.id, r.dist, (*idDict)[r.id].word);
                activeCount++;
            }
        }

        writefln("合計: %d件 (%s)", activeCount, searchType);
        displaySearchTime(elapsedTime);
    }

    /**
     * 削除済みエントリを含む検索結果を表示する
     * 
     * Params:
     *      matchedIDs = マッチしたIDの配列
     *      elapsedTime = 検索にかかった時間
     *      searchType = 検索の種類
     */
    void displayResultsWithDeleted(size_t[] matchedIDs, long elapsedTime, string searchType)
    {
        if (matchedIDs.length == 0)
        {
            writeln("該当なし");
            displaySearchTime(elapsedTime);
            return;
        }

        foreach (id; matchedIDs)
        {
            if (id in *idDict)
            {
                string status = (*idDict)[id].isDeleted ? "[削除済]" : "[有効]";
                writefln("ID:%d  %s %s", id, status, (*idDict)[id].word);
            }
        }

        writefln("合計: %d件 (%s)", matchedIDs.length, searchType);
        displaySearchTime(elapsedTime);
    }

    /**
     * アルファベット順の単語一覧を表示する
     * 
     * Params:
     *      wordDict = 単語辞書
     */
    void displayAlphabeticalList(WordEntry[string]* wordDict)
    {
        writeln("登録単語一覧（アルファベット順）:");

        // 有効な単語のみを抽出
        WordEntry[] activeEntries;
        foreach (entry; (*wordDict).values)
        {
            if (!entry.isDeleted)
            {
                activeEntries ~= entry;
            }
        }

        // 単語でソート
        sort!((a, b) => a.word < b.word)(activeEntries);

        // 表示
        if (activeEntries.length > 0)
        {
            foreach (i, entry; activeEntries)
            {
                writefln("NO.%d: ID: %-5d %s", i + 1, entry.id, entry.word);
            }
        }
        else
        {
            writeln("有効な単語はありません");
        }
    }

    /**
     * ID順の単語一覧を表示する（有効な単語のみ）
     */
    void displayIDList()
    {
        writeln("登録単語一覧（有効な単語のみ）:");
        size_t[] sortedIDs = (*idDict).keys;
        sort(sortedIDs);
        bool foundAny = false;

        foreach (id; sortedIDs)
        {
            if (!(*idDict)[id].isDeleted)
            {
                writefln("%5d: %s", id, (*idDict)[id].word);
                foundAny = true;
            }
        }

        if (!foundAny)
        {
            writeln("有効な単語はありません");
        }
    }

    /**
     * 削除済みを含む全単語一覧を表示する
     */
    void displayAllIDList()
    {
        writeln("登録単語一覧（削除済みを含む）:");
        size_t[] sortedIDs = (*idDict).keys;
        sort(sortedIDs);

        foreach (id; sortedIDs)
        {
            string status = (*idDict)[id].isDeleted ? "[削除済]" : "[有効]";
            writefln("%5d: %s %s", id, status, (*idDict)[id].word);
        }
    }

private:

    /**
     * 標準的な検索結果を表示する（内部実装）
     * 
     * Params:
     *      results = 検索結果（任意の型の配列）
     *      elapsedTime = 検索に要した時間（マイクロ秒単位）
     *      searchType = 検索の種類を示す文字列
     *      showDetails = 各結果の詳細を表示するかどうか
     *      showDistance = 距離情報を表示するかどうか（類似検索用）
     */
    void displaySearchResults(T)(T[] results, long elapsedTime, string searchType,
        bool showDetails = true, bool showDistance = false)
    {
        if (results.length == 0)
        {
            writeln("該当なし");
            displaySearchTime(elapsedTime);
            return;
        }

        size_t activeCount = 0;

        // 結果表示（型に応じた処理）
        static if (is(T == BKTree.Result))
        {
            if (showDetails)
            {
                foreach (r; results)
                {
                    // 削除済みの単語はスキップ
                    if (r.id in *idDict && !(*idDict)[r.id].isDeleted)
                    {
                        if (showDistance)
                            writefln("ID:%d  距離:%d  %s", r.id, r.dist, (*idDict)[r.id].word);
                        else
                            writefln("ID:%d  %s", r.id, (*idDict)[r.id].word);
                        activeCount++;
                    }
                }
            }
            else
            {
                // 詳細を表示しない場合は件数だけカウント
                foreach (r; results)
                    if (r.id in *idDict && !(*idDict)[r.id].isDeleted)
                        activeCount++;
            }
        }
        else static if (is(T == size_t))
        {
            if (showDetails)
            {
                foreach (id; results)
                {
                    // 削除済みの単語はスキップ
                    if (id in *idDict && !(*idDict)[id].isDeleted)
                    {
                        writefln("ID:%d  %s", id, (*idDict)[id].word);
                        activeCount++;
                    }
                }
            }
            else
            {
                // 詳細を表示しない場合は件数だけカウント
                foreach (id; results)
                    if (id in *idDict && !(*idDict)[id].isDeleted)
                        activeCount++;
            }
        }
        else
        {
            // その他の型はとりあえず件数だけカウント
            activeCount = results.length;
        }

        // 検索時間と件数の表示
        writefln("合計: %d件 (%s)", activeCount, searchType);
        displaySearchTime(elapsedTime);
    }

    /**
     * 検索時間を詳細に表示する
     * 
     * Params:
     *      elapsedTime = 検索にかかった時間（マイクロ秒単位）
     */
    void displaySearchTime(long elapsedTime)
    {
        // マイクロ秒から各単位に変換
        long msec = elapsedTime / 1_000; // ミリ秒
        long usec = elapsedTime % 1_000; // マイクロ秒（余り）

        // 明確に区分けして表示
        writefln("検索時間: %.6f秒 (%d.%03dミリ秒 = %dマイクロ秒)",
            elapsedTime / 1_000_000.0, // 秒（小数点表示）
            msec / 1_000, // 秒（整数部）
            msec % 1_000, // ミリ秒（小数部）
            elapsedTime); // 全マイクロ秒
    }
}
