module io.csv_processor;

import std.stdio;
import std.file;
import std.string;
import std.conv;
import std.algorithm;
import std.mmfile;
import std.datetime.stopwatch : StopWatch;

import core.structures;
import utils.file_utils;
import utils.string_utils;
import utils.memory_utils;
import utils.progress;

/**
 * CSV処理を管理するクラス
 * 
 * WordEntryの配列とCSVファイル間の変換、
 * 大容量ファイルの効率的な処理を提供します。
 */
class CSVProcessor
{
    private static immutable string CSV_HEADER = "ID,単語,削除フラグ";
    private static immutable size_t LARGE_FILE_THRESHOLD = 50 * 1024 * 1024; // 50MB
    
    /**
     * CSVファイルからWordEntryの配列を読み込む
     * 
     * Params:
     *      filePath = 読み込むCSVファイルのパス
     * 
     * Returns:
     *      WordEntryの配列
     */
    WordEntry[] loadEntries(string filePath)
    {
        if (!exists(filePath))
        {
            writefln("CSVファイルが存在しません: %s", filePath);
            return [];
        }
        
        // ファイルサイズを取得して処理方法を決定
        auto fileSize = getSize(filePath);
        writefln("ファイルサイズ: %.2f MB", fileSize / (1024.0 * 1024.0));
        
        if (fileSize > LARGE_FILE_THRESHOLD)
        {
            return loadEntriesLargeFile(filePath);
        }
        else
        {
            return loadEntriesSmallFile(filePath);
        }
    }
    
    /**
     * 大容量ファイル用の読み込み処理（メモリマップ使用）
     */
    private WordEntry[] loadEntriesLargeFile(string filePath)
    {
        writeln("大規模ファイルのため、メモリマップ方式で読み込みます...");
        
        // ファイル内の行数を概算
        size_t estimatedLines = estimateLineCount(filePath);
        writefln("推定行数: 約%d行", estimatedLines);
        
        // 進捗トラッカー初期化
        ProgressTracker progress;
        progress.initialize(estimatedLines);
        
        // メモリマップファイルを作成
        auto mmfile = new MmFile(filePath);
        scope(exit) destroy(mmfile);
        
        WordEntry[] entries;
        entries.reserve(estimatedLines);
        
        size_t lineStart = 0;
        size_t lineCount = 0;
        bool skipHeader = true;
        
        // メモリマップファイルをライン単位で処理
        for (size_t i = 0; i < mmfile.length; i++)
        {
            // 改行を探す
            if (mmfile[i] == '\n')
            {
                // ヘッダー行をスキップ
                if (skipHeader)
                {
                    skipHeader = false;
                }
                else
                {
                    // メモリマップ内のCSV行を処理
                    auto line = cast(string) mmfile[lineStart .. i];
                    auto entry = parseCSVLine(line);
                    
                    if (entry.word.length > 0) // 有効なエントリのみ追加
                    {
                        entries ~= entry;
                    }
                    
                    // 進捗更新
                    lineCount++;
                    if (lineCount % 1000 == 0)
                    {
                        progress.increment();
                    }
                }
                lineStart = i + 1;
            }
        }
        
        // 進捗を完了表示
        progress.finish();
        
        reportMemoryUsage("CSV読み込み後（大容量ファイル）");
        
        return entries;
    }
    
    /**
     * 小容量ファイル用の読み込み処理（通常方式）
     */
    private WordEntry[] loadEntriesSmallFile(string filePath)
    {
        auto inputFile = File(filePath, "r");
        StopWatch sw;
        sw.start();
        
        // 行数を数える
        size_t lineCount = 0;
        foreach (line; inputFile.byLine())
        {
            lineCount++;
        }
        inputFile.rewind();
        
        // 進捗トラッカー初期化
        ProgressTracker progress;
        progress.initialize(lineCount > 1 ? lineCount - 1 : 0); // ヘッダー行を除く
        
        // ヘッダー行をスキップ
        if (!inputFile.eof())
        {
            inputFile.readln(); // ヘッダー行をスキップ
        }
        
        // 全てのエントリを配列に読み込む
        WordEntry[] entries;
        entries.reserve(lineCount > 1 ? lineCount - 1 : 0);
        
        size_t processedLines = 0;
        foreach (line; inputFile.byLine())
        {
            auto entry = parseCSVLine(line.idup);
            
            if (entry.word.length > 0) // 有効なエントリのみ追加
            {
                entries ~= entry;
            }
            
            // 進捗更新
            processedLines++;
            if (processedLines % 1000 == 0)
            {
                progress.increment();
            }
        }
        
        progress.finish();
        sw.stop();
        
        writefln("CSV読み込み完了: %.2f秒", sw.peek.total!"msecs" / 1000.0);
        reportMemoryUsage("CSV読み込み後（小容量ファイル）");
        
        return entries;
    }
    
    /**
     * CSV行を解析してWordEntryを作成する
     */
    private WordEntry parseCSVLine(string line)
    {
        auto parts = line.split(",");
        
        if (parts.length >= 2)
        {
            try
            {
                size_t id = to!size_t(parts[0]);
                string word = internString(parts[1]);
                bool isDeleted = false;
                
                // 削除フラグがある場合（新形式）
                if (parts.length >= 3 && parts[2] == "1")
                {
                    isDeleted = true;
                }
                
                return WordEntry(word, id, isDeleted);
            }
            catch (Exception e)
            {
                writefln("CSV行の解析エラー: %s (行: %s)", e.msg, line);
            }
        }
        
        // 無効な行の場合は空のエントリを返す
        return WordEntry("", 0, false);
    }
    
    /**
     * WordEntryの配列をCSVファイルに保存する
     * 
     * Params:
     *      entries = 保存するWordEntryの配列
     *      filePath = 保存先のCSVファイルパス
     *      append = 追記モードかどうか（デフォルト: false）
     */
    void saveEntries(WordEntry[] entries, string filePath, bool append = false)
    {
        string mode = append ? "a" : "w";
        auto outputFile = File(filePath, mode);
        scope(exit) outputFile.close();
        
        // 新規作成の場合はヘッダーを書き込む
        if (!append || !exists(filePath) || getSize(filePath) == 0)
        {
            outputFile.writeln(CSV_HEADER);
        }
        
        // エントリを書き込む
        foreach (entry; entries)
        {
            outputFile.writefln("%d,%s,%d", 
                              entry.id, 
                              entry.word, 
                              entry.isDeleted ? 1 : 0);
        }
        
        outputFile.flush();
        writefln("CSVファイルに%d件のエントリを保存しました: %s", entries.length, filePath);
    }
    
    /**
     * 単一のWordEntryをCSVファイルに追記する
     * 
     * Params:
     *      entry = 追記するWordEntry
     *      filePath = CSVファイルパス
     */
    void appendEntry(WordEntry entry, string filePath)
    {
        // ファイルが存在しない場合は新規作成
        if (!exists(filePath))
        {
            saveEntries([entry], filePath, false);
            return;
        }
        
        auto outputFile = File(filePath, "a");
        scope(exit) outputFile.close();
        
        outputFile.writefln("%d,%s,%d", 
                          entry.id, 
                          entry.word, 
                          entry.isDeleted ? 1 : 0);
        outputFile.flush();
    }
    
    /**
     * CSVファイルの形式を検証する
     * 
     * Params:
     *      filePath = 検証するCSVファイルのパス
     * 
     * Returns:
     *      ファイルが有効な形式の場合はtrue
     */
    bool validateFormat(string filePath)
    {
        if (!exists(filePath))
        {
            writefln("ファイルが存在しません: %s", filePath);
            return false;
        }
        
        auto inputFile = File(filePath, "r");
        scope(exit) inputFile.close();
        
        // ヘッダー行をチェック
        if (inputFile.eof())
        {
            writeln("ファイルが空です");
            return false;
        }
        
        auto headerLine = inputFile.readln().strip();
        if (headerLine != CSV_HEADER)
        {
            writefln("ヘッダー形式が正しくありません。期待: '%s', 実際: '%s'", 
                     CSV_HEADER, headerLine);
            return false;
        }
        
        // データ行をサンプルチェック
        size_t lineNumber = 1;
        size_t errorCount = 0;
        size_t checkLimit = 100; // 最初の100行をチェック
        
        foreach (line; inputFile.byLine())
        {
            lineNumber++;
            if (lineNumber > checkLimit) break;
            
            auto parts = line.split(",");
            if (parts.length < 2 || parts.length > 3)
            {
                writefln("行 %d: 列数が正しくありません（%d列）", lineNumber, parts.length);
                errorCount++;
            }
            else
            {
                // ID列の数値チェック
                try
                {
                    to!size_t(parts[0]);
                }
                catch (Exception)
                {
                    writefln("行 %d: ID列が数値ではありません: %s", lineNumber, parts[0]);
                    errorCount++;
                }
                
                // 削除フラグのチェック（3列目がある場合）
                if (parts.length == 3 && parts[2] != "0" && parts[2] != "1")
                {
                    writefln("行 %d: 削除フラグが0または1ではありません: %s", lineNumber, parts[2]);
                    errorCount++;
                }
            }
        }
        
        if (errorCount > 0)
        {
            writefln("検証完了: %d行中%d行でエラーが見つかりました", lineNumber - 1, errorCount);
            return false;
        }
        
        writefln("検証完了: %d行すべて正常です", lineNumber - 1);
        return true;
    }
    
    /**
     * CSVファイルの統計情報を取得する
     * 
     * Params:
     *      filePath = 統計を取得するCSVファイルのパス
     * 
     * Returns:
     *      CSVファイルの統計情報
     */
    CSVStatistics getStatistics(string filePath)
    {
        CSVStatistics stats;
        stats.filePath = filePath;
        
        if (!exists(filePath))
        {
            return stats;
        }
        
        stats.fileSize = getSize(filePath);
        
        auto inputFile = File(filePath, "r");
        scope(exit) inputFile.close();
        
        // ヘッダー行をスキップ
        if (!inputFile.eof())
        {
            inputFile.readln();
            stats.totalLines++;
        }
        
        foreach (line; inputFile.byLine())
        {
            stats.totalLines++;
            auto entry = parseCSVLine(line.idup);
            
            if (entry.word.length > 0)
            {
                stats.validEntries++;
                if (entry.isDeleted)
                    stats.deletedEntries++;
                else
                    stats.activeEntries++;
                
                // 単語長の統計
                size_t wordLength = entry.word.length;
                if (wordLength > stats.maxWordLength)
                    stats.maxWordLength = wordLength;
                if (stats.minWordLength == 0 || wordLength < stats.minWordLength)
                    stats.minWordLength = wordLength;
                
                stats.totalCharacters += wordLength;
            }
            else
            {
                stats.invalidLines++;
            }
        }
        
        // 平均単語長を計算
        if (stats.validEntries > 0)
            stats.averageWordLength = cast(double)stats.totalCharacters / stats.validEntries;
        
        return stats;
    }
    
    /**
     * CSVファイルのバックアップを作成する
     * 
     * Params:
     *      filePath = バックアップするCSVファイルのパス
     *      backupSuffix = バックアップファイルのサフィックス
     * 
     * Returns:
     *      作成されたバックアップファイルのパス
     */
    string createBackup(string filePath, string backupSuffix = ".bak")
    {
        import utils.file_utils : createBackup;
        return createBackup(filePath, backupSuffix);
    }
}

/**
 * CSVファイルの統計情報を表す構造体
 */
struct CSVStatistics
{
    string filePath; /// ファイルパス
    ulong fileSize; /// ファイルサイズ（バイト）
    size_t totalLines; /// 総行数（ヘッダー含む）
    size_t validEntries; /// 有効エントリ数
    size_t activeEntries; /// アクティブエントリ数
    size_t deletedEntries; /// 削除済みエントリ数
    size_t invalidLines; /// 無効行数
    size_t maxWordLength; /// 最大単語長
    size_t minWordLength; /// 最小単語長
    double averageWordLength; /// 平均単語長
    size_t totalCharacters; /// 総文字数
    
    /**
     * 統計情報を表示する
     */
    void display() const
    {
        writeln("=== CSV統計情報 ===");
        writefln("ファイル: %s", filePath);
        writefln("サイズ: %.2f MB", fileSize / (1024.0 * 1024.0));
        writefln("総行数: %d", totalLines);
        writefln("有効エントリ: %d", validEntries);
        writefln("  アクティブ: %d", activeEntries);
        writefln("  削除済み: %d", deletedEntries);
        writefln("無効行数: %d", invalidLines);
        writefln("単語長統計:");
        writefln("  最小: %d文字", minWordLength);
        writefln("  最大: %d文字", maxWordLength);
        writefln("  平均: %.2f文字", averageWordLength);
        writefln("総文字数: %d", totalCharacters);
        writeln("=================");
    }
} 

 