module core.data_manager;

import std.stdio;
import std.algorithm;
import std.parallelism;
import std.datetime.stopwatch : StopWatch;
import std.array;
import std.range : chunks;
import std.container : RedBlackTree;
import core.memory : GC;

import core.structures;
import core.index_types;
import utils.string_utils;
import utils.search_utils;
import utils.memory_utils;
import utils.progress;
import algorithms.bktree;
import algorithms.distance;

/**
 * データ管理クラス
 * 
 * 辞書とインデックスの構築・管理を担当します。
 * 並列処理を活用した高速なインデックス構築を提供します。
 */
class DataManager
{
    /**
     * エントリ配列から辞書とインデックスを構築する
     * 
     * WordEntryの配列から各種辞書とインデックスを効率的に構築します。
     * 並列処理を活用して処理を高速化します。
     * 
     * Params:
     *      entries = WordEntry構造体の配列
     *      wordDict = 単語から単語エントリへのマッピング（出力）
     *      idDict = IDから単語エントリへのマッピング（出力）
     *      prefixTree = 前方一致検索用のインデックス（出力）
     *      suffixTree = 後方一致検索用のインデックス（出力）
     *      gramIndex = n-gram検索用のインデックス（出力）
     *      lengthIndex = 長さ検索用のインデックス（出力）
     *      bkTree = 類似検索用のBK-Tree（出力）
     */
    void buildFromEntries(
        WordEntry[] entries,
        ref WordEntry[string] wordDict,
        ref WordEntry[size_t] idDict,
        ref RedBlackTree!string prefixTree,
        ref RedBlackTree!string suffixTree,
        ref GramIndexType[string] gramIndex,
        ref bool[size_t][size_t] lengthIndex,
        ref BKTree bkTree)
    {
        StopWatch sw;
        sw.start();
        writeln("インデックス構築中...");

        // タスクプールの作成
        auto taskPool = new TaskPool(std.parallelism.totalCPUs);
        scope (exit)
            taskPool.finish();

        // メモリ使用量を減らすために予め容量を確保
        wordDict.clear();
        idDict.clear();
        lengthIndex.clear();
        
        // BK-Treeは新しく作成
        bkTree = new BKTree(&damerauDistanceLimited, 10);

        // 辞書への追加（これはスレッドセーフでないので単一スレッドで）
        foreach (entry; entries)
        {
            wordDict[entry.word] = entry;
            idDict[entry.id] = entry;
        }

        // 進捗トラッカー
        ProgressTracker progress;
        progress.initialize(entries.length);

        // インデックス構築を最適化（非削除エントリのみ）
        // まず非削除エントリを抽出
        WordEntry[] activeEntries = entries.filter!(e => !e.isDeleted).array;
        writefln("有効エントリ: %d/%d", activeEntries.length, entries.length);

        // 先に長さインデックスを確保（競合回避）
        foreach (entry; activeEntries)
        {
            size_t len = entry.word.length;
            if (len !in lengthIndex)
                lengthIndex[len] = null;
        }

        // 並列処理を減らし、安全性を高める
        immutable size_t itemsPerTask = max(1, activeEntries.length / (taskPool.size * 2));

        // 同期用のデータ構造
        size_t progressCounter = 0;
        auto mutex = new Object(); // 同期用のロック

        // 1. プレフィックスとサフィックスインデックスの構築（並列化可能）
        buildPrefixSuffixIndices(activeEntries, prefixTree, suffixTree, taskPool, mutex, itemsPerTask);

        // 2. n-gramインデックスの構築（並列化）
        buildGramIndex(activeEntries, gramIndex, lengthIndex, taskPool, mutex);

        // 3. BK-Treeを安全に構築（並列処理の外で実行）
        buildBKTreeIndex(activeEntries, bkTree);

        // 構築したインデックス数を格納
        size_t totalLoadedEntries = entries.length;
        // 中間データの解放を促進
        entries = null;
        GC.collect();

        sw.stop();

        // 有効なエントリー数
        size_t activeCount = activeEntries.length;
        writefln("%d件の単語のインデックスを構築しました（うち有効：%d件）。インデックス構築時間: %.2f秒",
            totalLoadedEntries, activeCount, sw.peek.total!"msecs" / 1000.0);

        // BK-Tree統計
        bkTree.printStats();

        // インデックス構築後のメモリ使用状況を報告
        reportMemoryUsage("インデックス構築後");
    }

    /**
     * プレフィックス・サフィックスインデックスの構築
     */
    private void buildPrefixSuffixIndices(
        WordEntry[] activeEntries,
        ref RedBlackTree!string prefixTree,
        ref RedBlackTree!string suffixTree,
        TaskPool taskPool,
        Object mutex,
        size_t itemsPerTask)
    {
        writeln("プレフィックス・サフィックスインデックスを構築中...");

        // ワーカーIDごとにローカルツリーを管理するためのハッシュマップを用意
        RedBlackTree!string[size_t] localPrefixTrees;
        RedBlackTree!string[size_t] localSuffixTrees;
        size_t[size_t] processCounts;

        // 分割して並列処理
        auto chunks = activeEntries.chunks(itemsPerTask).array;
        if (chunks.length > 0)
        {
            foreach (i, chunk; taskPool.parallel(chunks, 1))
            {
                size_t workerId = taskPool.workerIndex;

                // 必要に応じて初期化
                synchronized (mutex)
                {
                    if (workerId !in localPrefixTrees)
                    {
                        localPrefixTrees[workerId] = new RedBlackTree!string();
                        localSuffixTrees[workerId] = new RedBlackTree!string();
                        processCounts[workerId] = 0;
                    }
                }

                if (chunk.length > 0)
                {
                    foreach (entry; chunk)
                    {
                        // 同期なしでツリーを更新（ローカルツリーなので安全）
                        localPrefixTrees[workerId].insert(entry.word);
                        string revWord = revStr(entry.word);
                        localSuffixTrees[workerId].insert(revWord);

                        processCounts[workerId]++;
                    }
                }
            }
        }

        // 結果をマージ
        foreach (workerId, localTree; localPrefixTrees)
        {
            foreach (w; localTree)
                prefixTree.insert(w);
            foreach (w; localSuffixTrees[workerId])
                suffixTree.insert(w);
        }

        writefln("プレフィックス・サフィックスインデックス構築完了: %d + %d エントリ",
                prefixTree.length, suffixTree.length);
    }

    /**
     * N-gramインデックスの構築
     */
    private void buildGramIndex(
        WordEntry[] activeEntries,
        ref GramIndexType[string] gramIndex,
        ref bool[size_t][size_t] lengthIndex,
        TaskPool taskPool,
        Object mutex)
    {
        writeln("N-gramインデックスを構築中...");

        // ワーカーIDごとにローカルインデックスを管理するハッシュマップ
        GramIndexType[string][size_t] localGramIndices;

        // 分割サイズを計算
        size_t chunkSize = max(1, activeEntries.length / taskPool.size);
        auto entryChunks = activeEntries.chunks(chunkSize).array;

        // 並列処理
        if (entryChunks.length > 0)
        {
            foreach (chunkIdx, chunk; taskPool.parallel(entryChunks, 1))
            {
                size_t workerId = taskPool.workerIndex;

                // 必要に応じて初期化
                synchronized (mutex)
                {
                    if (workerId !in localGramIndices)
                    {
                        localGramIndices[workerId] = null;
                    }
                }

                if (chunk.length > 0)
                {
                    foreach (entry; chunk)
                    {
                        // グラム生成（ローカル）
                        if (entry.word.length >= 2)
                        {
                            registerNGrams(entry.word, entry.id, localGramIndices[workerId]);
                        }

                        // 長さインデックスに追加（ロックを使用）
                        synchronized (mutex)
                        {
                            lengthIndex[entry.word.length][entry.id] = true;
                        }
                    }
                }
            }
        }

        // ローカルn-gramインデックスをマージ
        foreach (workerId, localIndex; localGramIndices)
        {
            if (localIndex is null)
                continue;

            foreach (gram, idSet; localIndex)
            {
                if (gram !in gramIndex)
                {
                    // 新規作成前に存在しないことを再確認
                    synchronized (mutex)
                    {
                        if (gram !in gramIndex)
                        {
                            gramIndex[gram] = idSet;
                        }
                        else
                        {
                            // 競合した場合はマージ
                            foreach (id; idSet.keys())
                            {
                                gramIndex[gram].add(id);
                            }
                        }
                    }
                }
                else
                {
                    // IDセットをマージ（競合の可能性は低いので細かな同期は不要）
                    foreach (id; idSet.keys())
                    {
                        gramIndex[gram].add(id);
                    }
                }
            }
        }

        writefln("N-gramインデックス構築完了: %d グラム, %d 長さカテゴリ",
                gramIndex.length, lengthIndex.length);
    }

    /**
     * BK-Treeインデックスの構築
     */
    private void buildBKTreeIndex(WordEntry[] activeEntries, ref BKTree bkTree)
    {
        writeln("BK-Tree構築を開始...");

        // 少しずつBK-Treeに追加して、メモリ使用量を制御
        immutable size_t batchSize = 1000;
        size_t processedCount = 0;
        size_t batchTotalEntries = activeEntries.length;

        for (size_t i = 0; i < batchTotalEntries; i += batchSize)
        {
            size_t endIdx = min(i + batchSize, batchTotalEntries);

            // バッチ用の配列を作成
            string[] batchWords;
            size_t[] batchIDs;
            batchWords.reserve(endIdx - i);
            batchIDs.reserve(endIdx - i);

            for (size_t j = i; j < endIdx; j++)
            {
                batchWords ~= activeEntries[j].word;
                batchIDs ~= activeEntries[j].id;
            }

            // バッチ処理
            bkTree.batchInsert(batchWords, batchIDs, false);

            // 進捗表示
            processedCount += (endIdx - i);
            writef("\rBK-Tree構築: %d%% (%d/%d)",
                processedCount * 100 / batchTotalEntries,
                processedCount, batchTotalEntries);
            stdout.flush();

            // バッチごとにGCを呼び出してメモリを解放
            batchWords = null;
            batchIDs = null;
            GC.collect();
        }

        writeln("\nBK-Tree構築完了");
        GC.collect();
    }

    /**
     * インデックスを最適化する
     * 
     * 使用されなくなったエントリを削除し、インデックスのサイズを最適化します。
     */
    void optimizeIndices(
        ref WordEntry[string] wordDict,
        ref WordEntry[size_t] idDict,
        ref RedBlackTree!string prefixTree,
        ref RedBlackTree!string suffixTree,
        ref GramIndexType[string] gramIndex,
        ref bool[size_t][size_t] lengthIndex)
    {
        writeln("インデックスを最適化中...");
        StopWatch sw;
        sw.start();

        size_t removedEntries = 0;
        size_t optimizedGrams = 0;

        // 削除されたエントリをクリーンアップ
        string[] wordsToRemove;
        foreach (word, entry; wordDict)
        {
            if (entry.isDeleted)
            {
                wordsToRemove ~= word;
            }
        }

        foreach (word; wordsToRemove)
        {
            auto entry = wordDict[word];
            
            // プレフィックス木から削除
            prefixTree.removeKey(word);
            
            // サフィックス木から削除
            string revWord = revStr(word);
            suffixTree.removeKey(revWord);
            
            // 長さインデックスから削除
            size_t len = word.length;
            if (len in lengthIndex && entry.id in lengthIndex[len])
            {
                lengthIndex[len].remove(entry.id);
                // 空になった長さカテゴリを削除
                if (lengthIndex[len].length == 0)
                {
                    lengthIndex.remove(len);
                }
            }
            
            // 辞書から削除
            wordDict.remove(word);
            idDict.remove(entry.id);
            
            removedEntries++;
        }

        // N-gramインデックスの最適化
        string[] gramsToRemove;
        foreach (gram, ref idSet; gramIndex)
        {
            // 削除されたIDをクリーンアップ
            size_t[] idsToRemove;
            foreach (id; idSet.keys())
            {
                if (id !in idDict || idDict[id].isDeleted)
                {
                    idsToRemove ~= id;
                }
            }
            
            foreach (id; idsToRemove)
            {
                idSet.remove(id);
            }
            
            // 空になったgramを削除対象に追加
            if (idSet.length() == 0)
            {
                gramsToRemove ~= gram;
            }
        }

        foreach (gram; gramsToRemove)
        {
            gramIndex.remove(gram);
            optimizedGrams++;
        }

        sw.stop();
        writefln("インデックス最適化完了: %.2f秒", sw.peek.total!"msecs" / 1000.0);
        writefln("  削除されたエントリ: %d", removedEntries);
        writefln("  最適化されたN-gram: %d", optimizedGrams);
        
        // メモリ使用量をレポート
        reportMemoryUsage("インデックス最適化後");
    }

    /**
     * インデックスの統計情報を表示する
     */
    void displayIndexStatistics(
        WordEntry[string] wordDict,
        WordEntry[size_t] idDict,
        RedBlackTree!string prefixTree,
        RedBlackTree!string suffixTree,
        GramIndexType[string] gramIndex,
        bool[size_t][size_t] lengthIndex,
        BKTree bkTree)
    {
        writeln("\n=== インデックス統計情報 ===");
        
        // 基本統計
        size_t activeWords = 0;
        size_t deletedWords = 0;
        foreach (entry; wordDict.values)
        {
            if (entry.isDeleted)
                deletedWords++;
            else
                activeWords++;
        }
        
        writefln("単語辞書サイズ: %d (アクティブ: %d, 削除済み: %d)",
                wordDict.length, activeWords, deletedWords);
        writefln("ID辞書サイズ: %d", idDict.length);
        writefln("プレフィックス木サイズ: %d", prefixTree.length);
        writefln("サフィックス木サイズ: %d", suffixTree.length);
        writefln("N-gramインデックス数: %d", gramIndex.length);
        writefln("長さインデックス数: %d", lengthIndex.length);
        
        // N-gramインデックスの詳細統計
        size_t totalGramEntries = 0;
        size_t maxGramSize = 0;
        size_t minGramSize = size_t.max;
        
        foreach (idSet; gramIndex.values)
        {
            size_t gramSize = idSet.length();
            totalGramEntries += gramSize;
            if (gramSize > maxGramSize) maxGramSize = gramSize;
            if (gramSize < minGramSize) minGramSize = gramSize;
        }
        
        double avgGramSize = gramIndex.length > 0 ? 
            cast(double)totalGramEntries / gramIndex.length : 0.0;
        
        writefln("N-gram統計:");
        writefln("  総エントリ数: %d", totalGramEntries);
        writefln("  平均サイズ: %.2f", avgGramSize);
        writefln("  最大サイズ: %d", maxGramSize);
        writefln("  最小サイズ: %d", minGramSize == size_t.max ? 0 : minGramSize);
        
        // 長さインデックスの統計
        writeln("長さ別単語数:");
        auto sortedLengths = lengthIndex.keys.sort();
        foreach (len; sortedLengths[0 .. min(10, sortedLengths.length)]) // 最初の10個のみ表示
        {
            writefln("  %d文字: %d語", len, lengthIndex[len].length);
        }
        if (sortedLengths.length > 10)
        {
            writefln("  ... その他 %d カテゴリ", sortedLengths.length - 10);
        }
        
        // BK-Tree統計
        if (bkTree !is null)
        {
            bkTree.printStats();
        }
        
        writeln("==========================\n");
    }
    
    /**
     * インデックスの整合性をチェックする
     */
    bool validateIndexIntegrity(
        WordEntry[string] wordDict,
        WordEntry[size_t] idDict,
        RedBlackTree!string prefixTree,
        RedBlackTree!string suffixTree,
        GramIndexType[string] gramIndex,
        bool[size_t][size_t] lengthIndex)
    {
        writeln("インデックスの整合性をチェック中...");
        bool isValid = true;
        size_t errorCount = 0;
        
        // 1. 辞書の整合性チェック
        foreach (word, entry; wordDict)
        {
            if (entry.id !in idDict)
            {
                writefln("エラー: 単語 '%s' (ID: %d) がID辞書に存在しません", word, entry.id);
                isValid = false;
                errorCount++;
            }
            else if (idDict[entry.id].word != word)
            {
                writefln("エラー: ID %d の単語が不一致: '%s' vs '%s'", 
                        entry.id, word, idDict[entry.id].word);
                isValid = false;
                errorCount++;
            }
        }
        
        // 2. プレフィックス木の整合性チェック
        foreach (word; prefixTree)
        {
            if (word !in wordDict)
            {
                writefln("エラー: プレフィックス木の単語 '%s' が辞書に存在しません", word);
                isValid = false;
                errorCount++;
            }
            else if (wordDict[word].isDeleted)
            {
                writefln("警告: プレフィックス木に削除済み単語 '%s' が含まれています", word);
                // これは警告のみ（エラーカウントは増やさない）
            }
        }
        
        // 3. 長さインデックスの整合性チェック
        foreach (length, idSet; lengthIndex)
        {
            foreach (id; idSet.keys)
            {
                if (id !in idDict)
                {
                    writefln("エラー: 長さインデックスのID %d が辞書に存在しません", id);
                    isValid = false;
                    errorCount++;
                }
                else if (idDict[id].word.length != length)
                {
                    writefln("エラー: ID %d の単語長が不一致: 期待 %d, 実際 %d",
                            id, length, idDict[id].word.length);
                    isValid = false;
                    errorCount++;
                }
            }
        }
        
        if (isValid)
        {
            writeln("インデックスの整合性チェック: 正常");
        }
        else
        {
            writefln("インデックスの整合性チェック: %d個のエラーが見つかりました", errorCount);
        }
        
        return isValid;
    }
} 

 