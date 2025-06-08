module ui.command_interface;

import std.stdio;
import std.string;
import std.conv;
import std.regex;
import std.algorithm;
import std.container : RedBlackTree;
import std.datetime.stopwatch : StopWatch;

import core.structures;
import core.index_types;
import search.interfaces;
import search.result_display;
import search.search_engine;
import algorithms.bktree;
import io.csv_processor;
import utils.string_utils;
import utils.memory_utils;

/**
 * コマンドインターフェースクラス
 * 
 * ユーザーとの対話処理、コマンド解析、検索実行を管理します。
 * 様々な検索コマンドとデータ操作コマンドを提供します。
 */
class CommandInterface
{
    // データ参照（読み取り専用）
    private WordEntry[string] wordDict;
    private WordEntry[size_t] idDict;
    private size_t nextID;
    private RedBlackTree!string prefixTree;
    private RedBlackTree!string suffixTree;
    private GramIndexType[string] gramIndex;
    private bool[size_t][size_t] lengthIndex;
    private BKTree bkTree;
    private string csvFilePath;
    
    // コンポーネント
    private SearchEngine searchEngine;
    private ResultDisplay resultDisplay;
    private CSVProcessor csvProcessor;
    
    // 正規表現パターン
    private static immutable auto helpRegex = regex(r"^:(help|h|\?)$");
    private static immutable auto exitRegex = regex(r"^:(exit|quit|q)$");
    private static immutable auto exactRegex = regex(r"^:(exact|ex)\s+(.+)$");
    private static immutable auto preRegex = regex(r"^:(pre|prefix)\s+(.+)$");
    private static immutable auto sufRegex = regex(r"^:(suf|suffix)\s+(.+)$");
    private static immutable auto subRegex = regex(r"^:(sub|substring)\s+(.+)$");
    private static immutable auto andRegex = regex(r"^:(and)\s+(.+)$");
    private static immutable auto orRegex = regex(r"^:(or)\s+(.+)$");
    private static immutable auto notRegex = regex(r"^:(not)\s+(.+)$");
    private static immutable auto lengthExactRegex = regex(r"^:(length|len)\s+(\d+)$");
    private static immutable auto lengthRangeRegex = regex(r"^:(length|len)\s+(\d+)-(\d+)$");
    private static immutable auto idRangeRegex = regex(r"^:(id|ids)\s+(\d+)-(\d+)$");
    private static immutable auto simRegex = regex(r"^:(sim)\s+(\S+)(?:\s+(\d+))?$");
    private static immutable auto simExtendedRegex = regex(r"^:(sim\+)\s+(\S+)(?:\s+(\d+))?$");
    private static immutable auto complexRegex = regex(r"^:(complex|comp)\s+(.+)$");
    private static immutable auto rebuildRegex = regex(r"^:(rebuild|reindex)$");
    private static immutable auto statsRegex = regex(r"^:(stats|statistics)$");
    private static immutable auto deleteRegex = regex(r"^:(delete|del)\s+(.+)$");
    private static immutable auto undeleteRegex = regex(r"^:(undelete|undel)\s+(.+)$");
    
    /**
     * コンストラクタ
     */
    this(ref WordEntry[string] wordDict,
         ref WordEntry[size_t] idDict,
         ref size_t nextID,
         ref RedBlackTree!string prefixTree,
         ref RedBlackTree!string suffixTree,
         ref GramIndexType[string] gramIndex,
         ref bool[size_t][size_t] lengthIndex,
         ref BKTree bkTree,
         string csvFilePath)
    {
        this.wordDict = wordDict;
        this.idDict = idDict;
        this.nextID = nextID;
        this.prefixTree = prefixTree;
        this.suffixTree = suffixTree;
        this.gramIndex = gramIndex;
        this.lengthIndex = lengthIndex;
        this.bkTree = bkTree;
        this.csvFilePath = csvFilePath;
        
        // SearchContextを作成
        SearchContext context;
        context.wordDict = &wordDict;
        context.idDict = &idDict;
        context.prefixTree = cast(void*)prefixTree;
        context.suffixTree = cast(void*)suffixTree;
        context.gramIndex = cast(void*)&gramIndex;
        context.lengthIndex = cast(void*)&lengthIndex;
        context.bkTree = cast(void*)bkTree;
        
        // コンポーネントの初期化
        this.searchEngine = new SearchEngine(context);
        this.resultDisplay = new ResultDisplay(&idDict);
        this.csvProcessor = new CSVProcessor();
        
        writeln("コマンドインターフェースを初期化しました");
    }
    
    /**
     * インタラクティブモードを開始する
     */
    void run()
    {
        showWelcomeMessage();
        
        string line;
        while (true)
        {
            // プロンプトを表示
            write("> ");
            stdout.flush();
            
            // 入力を読み込む
            line = readln();
            if (line is null) // EOF（Ctrl+D）で終了
            {
                writeln("\nEOF（Ctrl+D）を検出しました。終了します...");
                break;
            }
            
            // 入力を整形
            line = strip(line);
            
            // 空行はスキップ
            if (line.empty)
                continue;
            
            // コマンドを処理
            if (!processCommand(line))
                break; // 終了コマンドが実行された
        }
    }
    
    /**
     * 単一のコマンドを処理する
     * 
     * Returns:
     *      続行する場合はtrue、終了する場合はfalse
     */
    bool processCommand(string line)
    {
        try
        {
            // ヘルプ表示
            if (matchFirst(line, helpRegex))
            {
                showHelp();
                return true;
            }
            
            // 終了コマンド
            if (matchFirst(line, exitRegex))
            {
                writeln("プログラムを終了します...");
                return false;
            }
            
            // 統計情報表示
            if (matchFirst(line, statsRegex))
            {
                showStatistics();
                return true;
            }
            
            // インデックス再構築
            if (matchFirst(line, rebuildRegex))
            {
                rebuildIndices();
                return true;
            }
            
            // 検索コマンド群
            if (processSearchCommands(line))
                return true;
            
            // データ操作コマンド群
            if (processDataCommands(line))
                return true;
            
            // 通常の単語追加処理
            processWordAddition(line);
            return true;
        }
        catch (Exception e)
        {
            writefln("コマンド処理中にエラーが発生しました: %s", e.msg);
            return true;
        }
    }
    
    /**
     * 検索コマンドを処理する
     */
    private bool processSearchCommands(string line)
    {
        StopWatch sw;
        
        // 完全一致検索
        auto exactMatch = matchFirst(line, exactRegex);
        if (!exactMatch.empty)
        {
            string key = exactMatch[2];
            writeln("完全一致結果:");
            
            sw.start();
            auto results = searchEngine.searchExact(key);
            sw.stop();
            
            resultDisplay.displaySearchResult(results);
            return true;
        }
        
        // 前方一致検索
        auto preMatch = matchFirst(line, preRegex);
        if (!preMatch.empty)
        {
            string key = preMatch[2];
            writeln("前方一致結果:");
            
            sw.start();
            auto results = searchEngine.searchPrefix(key);
            sw.stop();
            
            resultDisplay.displaySearchResult(results);
            return true;
        }
        
        // 後方一致検索
        auto sufMatch = matchFirst(line, sufRegex);
        if (!sufMatch.empty)
        {
            string key = sufMatch[2];
            writeln("後方一致結果:");
            
            sw.start();
            auto results = searchEngine.searchSuffix(key);
            sw.stop();
            
            resultDisplay.displaySearchResult(results);
            return true;
        }
        
        // 部分一致検索
        auto subMatch = matchFirst(line, subRegex);
        if (!subMatch.empty)
        {
            string key = subMatch[2];
            writeln("部分一致結果:");
            
            sw.start();
            auto results = searchEngine.searchSubstring(key);
            sw.stop();
            
            resultDisplay.displaySearchResult(results);
            return true;
        }
        
        // 類似検索
        auto simMatch = matchFirst(line, simRegex);
        if (!simMatch.empty)
        {
            string query = simMatch[2];
            size_t maxDist = simMatch[3].empty ? 2 : to!size_t(simMatch[3]);
            writefln("類似検索結果（最大距離: %d）:", maxDist);
            
            sw.start();
            auto results = searchEngine.searchSimilar(query);
            sw.stop();
            
            resultDisplay.displaySearchResult(results);
            return true;
        }
        
        // 拡張類似検索
        auto simExtMatch = matchFirst(line, simExtendedRegex);
        if (!simExtMatch.empty)
        {
            string query = simExtMatch[2];
            size_t maxDist = simExtMatch[3].empty ? 2 : to!size_t(simExtMatch[3]);
            writefln("拡張類似検索結果（最大距離: %d）:", maxDist);
            
            sw.start();
            auto results = searchEngine.searchSimilarExtended(query);
            sw.stop();
            
            resultDisplay.displaySearchResult(results);
            return true;
        }
        
        // 長さ検索（固定）
        auto lengthExactMatch = matchFirst(line, lengthExactRegex);
        if (!lengthExactMatch.empty)
        {
            size_t targetLength = to!size_t(lengthExactMatch[2]);
            writefln("長さ検索結果（%d文字の単語）:", targetLength);
            
            sw.start();
            auto results = searchEngine.searchByLength(targetLength);
            sw.stop();
            
            resultDisplay.displaySearchResult(results);
            return true;
        }
        
        // 長さ検索（範囲）
        auto lengthRangeMatch = matchFirst(line, lengthRangeRegex);
        if (!lengthRangeMatch.empty)
        {
            size_t minLength = to!size_t(lengthRangeMatch[2]);
            size_t maxLength = to!size_t(lengthRangeMatch[3]);
            
            if (minLength > maxLength)
            {
                writeln("エラー: 長さの範囲指定が不正です（最小値 > 最大値）");
                return true;
            }
            
            writefln("長さ検索結果（%d-%d文字の単語）:", minLength, maxLength);
            
            sw.start();
            auto results = searchEngine.searchByLengthRange(minLength, maxLength);
            sw.stop();
            
            resultDisplay.displaySearchResult(results);
            return true;
        }
        
        return false; // 検索コマンドではない
    }
    
    /**
     * データ操作コマンドを処理する
     */
    private bool processDataCommands(string line)
    {
        // 削除コマンド
        auto deleteMatch = matchFirst(line, deleteRegex);
        if (!deleteMatch.empty)
        {
            string word = deleteMatch[2];
            deleteWord(word);
            return true;
        }
        
        // 復元コマンド
        auto undeleteMatch = matchFirst(line, undeleteRegex);
        if (!undeleteMatch.empty)
        {
            string word = undeleteMatch[2];
            undeleteWord(word);
            return true;
        }
        
        return false; // データ操作コマンドではない
    }
    
    /**
     * 単語追加処理
     */
    private void processWordAddition(string line)
    {
        // 複数の単語をスペースで区切って入力可能
        auto words = line.split();
        
        foreach (word; words)
        {
            word = strip(word);
            if (word.empty) continue;
            
            // 文字列をインターン化
            string internedWord = internString(word);
            
            if (internedWord in wordDict)
            {
                auto entry = wordDict[internedWord];
                if (entry.isDeleted)
                {
                    // 削除済みの単語を復元
                    entry.isDeleted = false;
                    wordDict[internedWord] = entry;
                    idDict[entry.id] = entry;
                    
                    // CSVファイルを更新
                    csvProcessor.appendEntry(entry, csvFilePath);
                    
                    writefln("単語 '%s' (ID: %d) を復元しました", internedWord, entry.id);
                }
                else
                {
                    writefln("単語 '%s' は既に存在します (ID: %d)", internedWord, entry.id);
                }
            }
            else
            {
                // 新しい単語を追加
                auto newEntry = WordEntry(internedWord, nextID, false);
                
                wordDict[internedWord] = newEntry;
                idDict[nextID] = newEntry;
                
                // インデックスを更新
                updateIndicesForNewWord(internedWord, nextID);
                
                // CSVファイルに追記
                csvProcessor.appendEntry(newEntry, csvFilePath);
                
                writefln("新しい単語 '%s' (ID: %d) を追加しました", internedWord, nextID);
                nextID++;
            }
        }
    }
    
    /**
     * 新しい単語のためにインデックスを更新する
     */
    private void updateIndicesForNewWord(string word, size_t id)
    {
        // プレフィックス木に追加
        prefixTree.insert(word);
        
        // サフィックス木に追加
        string revWord = revStr(word);
        suffixTree.insert(revWord);
        
        // N-gramインデックスに追加
        import utils.search_utils : registerNGrams;
        registerNGrams(word, id, gramIndex);
        
        // 長さインデックスに追加
        size_t len = word.length;
        if (len !in lengthIndex)
        {
            lengthIndex[len] = null;
        }
        lengthIndex[len][id] = true;
        
        // BK-Treeに追加
        bkTree.insert(word, id);
    }
    
    /**
     * 単語を削除する
     */
    private void deleteWord(string word)
    {
        string internedWord = internString(word);
        
        if (internedWord !in wordDict)
        {
            writefln("単語 '%s' が見つかりません", word);
            return;
        }
        
        auto entry = wordDict[internedWord];
        
        if (entry.isDeleted)
        {
            writefln("単語 '%s' (ID: %d) は既に削除されています", word, entry.id);
            return;
        }
        
        // 論理削除を実行
        entry.isDeleted = true;
        wordDict[internedWord] = entry;
        idDict[entry.id] = entry;
        
        // CSVファイルを更新
        csvProcessor.appendEntry(entry, csvFilePath);
        
        writefln("単語 '%s' (ID: %d) を削除しました", word, entry.id);
    }
    
    /**
     * 削除された単語を復元する
     */
    private void undeleteWord(string word)
    {
        string internedWord = internString(word);
        
        if (internedWord !in wordDict)
        {
            writefln("単語 '%s' が見つかりません", word);
            return;
        }
        
        auto entry = wordDict[internedWord];
        
        if (!entry.isDeleted)
        {
            writefln("単語 '%s' (ID: %d) は削除されていません", word, entry.id);
            return;
        }
        
        // 復元を実行
        entry.isDeleted = false;
        wordDict[internedWord] = entry;
        idDict[entry.id] = entry;
        
        // CSVファイルを更新
        csvProcessor.appendEntry(entry, csvFilePath);
        
        writefln("単語 '%s' (ID: %d) を復元しました", word, entry.id);
    }
    
    /**
     * インデックスを再構築する
     */
    private void rebuildIndices()
    {
        writeln("インデックスを再構築しています...");
        
        // 確認を求める
        write("この操作にはしばらく時間がかかります。続行しますか？ (y/n): ");
        stdout.flush();
        string confirm = strip(readln());
        if (confirm != "y" && confirm != "Y")
        {
            writeln("インデックス再構築をキャンセルしました。");
            return;
        }
        
        import core.data_manager;
        auto dataManager = new DataManager();
        
        // 現在のデータからエントリ配列を作成
        WordEntry[] entries;
        entries.reserve(idDict.length);
        foreach (entry; idDict.values)
        {
            entries ~= entry;
        }
        
        // インデックスをクリア
        prefixTree.clear();
        suffixTree.clear();
        gramIndex.clear();
        lengthIndex.clear();
        
        // インデックス再構築
        dataManager.buildFromEntries(
            entries, wordDict, idDict, prefixTree, suffixTree, gramIndex, lengthIndex, bkTree
        );
        
        // SearchContextを再作成
        SearchContext newContext;
        newContext.wordDict = &wordDict;
        newContext.idDict = &idDict;
        newContext.prefixTree = cast(void*)prefixTree;
        newContext.suffixTree = cast(void*)suffixTree;
        newContext.gramIndex = cast(void*)&gramIndex;
        newContext.lengthIndex = cast(void*)&lengthIndex;
        newContext.bkTree = cast(void*)bkTree;
        
        // 検索エンジンを更新
        searchEngine = new SearchEngine(newContext);
        
        writeln("インデックスの再構築が完了しました！");
    }
    
    /**
     * 統計情報を表示する
     */
    private void showStatistics()
    {
        import core.data_manager;
        auto dataManager = new DataManager();
        
        dataManager.displayIndexStatistics(
            wordDict, idDict, prefixTree, suffixTree, gramIndex, lengthIndex, bkTree
        );
        
        // CSV統計も表示
        auto csvStats = csvProcessor.getStatistics(csvFilePath);
        csvStats.display();
        
        // メモリ統計
        reportGCStats();
    }
    
    /**
     * ウェルカムメッセージを表示する
     */
    private void showWelcomeMessage()
    {
        writeln("\n===== Language Table - 対話モード =====");
        writeln("単語を入力してデータベースに追加するか、:");
        writeln("検索コマンド（:help で詳細表示）を使用してください。");
        writeln("終了するには :exit を入力してください。");
        writeln("=====================================\n");
    }
    
    /**
     * ヘルプメッセージを表示する
     */
    private void showHelp()
    {
        writeln("\n=====================================================");
        writeln("Language Table - コマンドヘルプ");
        writeln("=====================================================");
        writeln("基本的な検索コマンド:");
        writeln("  :exact WORD, :ex WORD        完全一致検索");
        writeln("  :pre WORD, :prefix WORD      前方一致検索（WORD で始まる）");
        writeln("  :suf WORD, :suffix WORD      後方一致検索（WORD で終わる）");
        writeln("  :sub WORD, :substring WORD   部分一致検索（WORD を含む）");
        writeln("");
        writeln("論理演算検索:");
        writeln("  :and KEY1 KEY2...            AND検索（すべてのキーワードを含む）");
        writeln("  :or KEY1 KEY2...             OR検索（いずれかのキーワードを含む）");
        writeln("  :not KEY                     NOT検索（キーワードを含まない）");
        writeln("");
        writeln("属性検索:");
        writeln("  :length N, :len N            特定の長さ(N文字)の単語を検索");
        writeln("  :length N-M, :len N-M        特定の長さ範囲(N～M文字)の単語を検索");
        writeln("  :id N-M, :ids N-M            ID範囲(N～M)の単語を検索");
        writeln("");
        writeln("類似検索:");
        writeln("  :sim WORD [d]                類似検索 (デフォルト距離d=2)");
        writeln("  :sim+ WORD [d]               拡張類似検索 - より多くの結果を表示");
        writeln("");
        writeln("データ管理:");
        writeln("  :delete WORD, :del WORD      単語を削除（論理削除）");
        writeln("  :undelete WORD, :undel WORD  削除された単語を復元");
        writeln("  :rebuild, :reindex           インデックスを再構築");
        writeln("  :stats, :statistics          統計情報を表示");
        writeln("");
        writeln("その他:");
        writeln("  :help, :h, :?                このヘルプを表示");
        writeln("  :exit, :quit, :q             プログラムを終了");
        writeln("");
        writeln("使い方:");
        writeln("  単語を入力すると、CSVファイルに追加されます");
        writeln("  複数の単語はスペースで区切って入力できます");
        writeln("  例: apple banana orange");
        writeln("");
        writeln("終了方法:");
        writeln("  :exit コマンド、Ctrl+D、または Ctrl+C で終了できます");
        writeln("=====================================================\n");
    }
} 

 