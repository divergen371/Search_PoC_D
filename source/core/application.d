module core.application;

import std.stdio;
import std.file;
import std.path;
import std.datetime.stopwatch : StopWatch;

import core.structures;
import core.index_types;
import utils.system_utils;
import utils.memory_utils;
import utils.progress;
import algorithms.bktree;
import cache.index_cache;
import std.container : RedBlackTree;

/**
 * メインアプリケーションクラス
 * 
 * アプリケーション全体のライフサイクルを管理し、
 * 各コンポーネント間の調整を行います。
 */
class LanguageTableApplication
{
    private string csvFilePath;
    private WordEntry[string] wordDict;
    private WordEntry[size_t] idDict;
    private size_t nextID;
    
    // インデックス構造
    private RedBlackTree!string prefixTree;
    private RedBlackTree!string suffixTree;
    private GramIndexType[string] gramIndex;
    private bool[size_t][size_t] lengthIndex;
    private BKTree bkTree;
    
    // キャッシュ
    private IndexCache cache;
    private bool cacheLoaded;
    
    // 統計
    private StopWatch totalTimer;
    
    /**
     * コンストラクタ
     */
    this()
    {
        // システム初期化
        initializeSystem();
        
        // CSVファイルパスの設定
        csvFilePath = absolutePath("language_data.csv");
        
        // 初期化
        nextID = 0;
        cacheLoaded = false;
        
        // キャッシュの初期化
        string cachePath = csvFilePath ~ ".cache";
        cache = IndexCache(cachePath);
        
        // インデックスの初期化
        prefixTree = new RedBlackTree!string;
        suffixTree = new RedBlackTree!string;
        
        writeln("Language Table Application を初期化しました");
        writeln("CSVファイルの出力先: ", csvFilePath);
    }
    
    /**
     * アプリケーションを開始する
     */
    void run()
    {
        totalTimer.start();
        
        try
        {
            // データの読み込み
            loadData();
            
            // インタラクティブモードの開始
            startInteractiveMode();
        }
        catch (Exception e)
        {
            writefln("アプリケーション実行中にエラーが発生しました: %s", e.msg);
            safeExit(1);
        }
        finally
        {
            cleanup();
        }
    }
    
    /**
     * データの読み込みを行う
     */
    private void loadData()
    {
        // キャッシュの確認と読み込み
        if (cache.isValid(csvFilePath))
        {
            writeln("キャッシュを読み込んでいます...");
            if (loadFromCache())
            {
                writeln("キャッシュからのデータ読み込みが完了しました");
                return;
            }
        }
        
        // CSVファイルからの読み込み
        if (exists(csvFilePath))
        {
            loadFromCSV();
        }
        else
        {
            writeln("新しいデータベースを作成します");
            initializeEmptyDatabase();
        }
    }
    
    /**
     * キャッシュからデータを読み込む
     */
    private bool loadFromCache()
    {
        try
        {
            if (cache.loadFull(prefixTree, suffixTree, gramIndex, lengthIndex))
            {
                cacheLoaded = true;
                writeln("prefix/suffix/gram/length インデックスをキャッシュから復元");
                return true;
            }
            else if (cache.load(prefixTree, suffixTree))
            {
                cacheLoaded = true;
                writeln("prefix/suffix インデックスをキャッシュから復元（旧形式）");
                return true;
            }
        }
        catch (Exception e)
        {
            writefln("キャッシュ読み込みエラー: %s", e.msg);
        }
        
        return false;
    }
    
    /**
     * CSVファイルからデータを読み込む
     */
    private void loadFromCSV()
    {
        import io.csv_processor;
        
        writeln("既存のCSVファイルを読み込んでいます...");
        
        auto processor = new CSVProcessor();
        auto entries = processor.loadEntries(csvFilePath);
        
        if (entries.length > 0)
        {
            buildDatabaseFromEntries(entries);
            
            // キャッシュ保存
            if (!cacheLoaded)
            {
                saveToCache();
            }
        }
    }
    
    /**
     * エントリからデータベースを構築する
     */
    private void buildDatabaseFromEntries(WordEntry[] entries)
    {
        import core.data_manager;
        
        auto dataManager = new DataManager();
        dataManager.buildFromEntries(
            entries,
            wordDict,
            idDict, 
            prefixTree,
            suffixTree,
            gramIndex,
            lengthIndex,
            bkTree
        );
        
        // 次のIDを設定
        foreach (entry; entries)
        {
            if (entry.id >= nextID)
                nextID = entry.id + 1;
        }
        
        reportMemoryUsage("データベース構築後");
    }
    
    /**
     * 空のデータベースを初期化する
     */
    private void initializeEmptyDatabase()
    {
        import algorithms.distance : damerauDistanceLimited;
        
        bkTree = new BKTree(&damerauDistanceLimited, 3);
        nextID = 0;
        
        writeln("空のデータベースを初期化しました");
    }
    
    /**
     * キャッシュにデータを保存する
     */
    private void saveToCache()
    {
        try
        {
            writeln("キャッシュを保存しています...");
            cache.saveFull(prefixTree, suffixTree, gramIndex, lengthIndex);
            writeln("キャッシュ保存が完了しました");
        }
        catch (Exception e)
        {
            writefln("キャッシュ保存エラー: %s", e.msg);
        }
    }
    
    /**
     * インタラクティブモードを開始する
     */
    private void startInteractiveMode()
    {
        import ui.command_interface;
        
        auto commandInterface = new CommandInterface(
            wordDict,
            idDict,
            nextID,
            prefixTree,
            suffixTree,
            gramIndex,
            lengthIndex,
            bkTree,
            csvFilePath
        );
        
        commandInterface.run();
    }
    
    /**
     * インデックスを再構築する
     */
    void rebuildIndexes()
    {
        writeln("インデックスを再構築しています...");
        
        // インデックスをクリア
        prefixTree.clear();
        suffixTree.clear();
        gramIndex.clear();
        lengthIndex.clear();
        
        // CSVファイルから再読み込み
        if (exists(csvFilePath))
        {
            loadFromCSV();
            writeln("インデックスの再構築が完了しました！");
        }
        else
        {
            writeln("エラー: CSVファイルが見つかりません。");
        }
    }
    
    /**
     * 統計情報を表示する
     */
    void displayStatistics()
    {
        writeln("\n=== アプリケーション統計 ===");
        writefln("総単語数: %d", wordDict.length);
        writefln("有効単語数: %d", countActiveWords());
        writefln("削除済み単語数: %d", wordDict.length - countActiveWords());
        writefln("次のID: %d", nextID);
        writefln("プレフィックス木サイズ: %d", prefixTree.length);
        writefln("サフィックス木サイズ: %d", suffixTree.length);
        writefln("N-gramインデックス数: %d", gramIndex.length);
        writefln("長さインデックス数: %d", lengthIndex.length);
        
        if (bkTree !is null)
        {
            bkTree.printStats();
        }
        
        if (totalTimer.running)
        {
            auto elapsed = totalTimer.peek();
            writefln("総実行時間: %.3f秒", elapsed.total!"msecs" / 1000.0);
        }
        
        reportGCStats();
        writeln("=========================\n");
    }
    
    /**
     * 有効な単語数をカウントする
     */
    private size_t countActiveWords()
    {
        size_t count = 0;
        foreach (entry; wordDict.values)
        {
            if (!entry.isDeleted)
                count++;
        }
        return count;
    }
    
    /**
     * アプリケーションを終了する
     */
    void shutdown()
    {
        if (totalTimer.running)
            totalTimer.stop();
        
        displayStatistics();
        cleanup();
        writeln("Language Table Application を終了しました");
    }
    
    /**
     * getter メソッド群
     */
    
    string getCSVFilePath() const { return csvFilePath; }
    WordEntry[string] getWordDict() { return wordDict; }
    WordEntry[size_t] getIdDict() { return idDict; }
    size_t getNextID() const { return nextID; }
    RedBlackTree!string getPrefixTree() { return prefixTree; }
    RedBlackTree!string getSuffixTree() { return suffixTree; }
    GramIndexType[string] getGramIndex() { return gramIndex; }
    bool[size_t][size_t] getLengthIndex() { return lengthIndex; }
    BKTree getBKTree() { return bkTree; }
} 

 