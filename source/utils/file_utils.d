module utils.file_utils;

import std.stdio;
import std.file;
import std.algorithm : min, max;
import std.array : split;

/**
 * ファイル処理に関するユーティリティ関数群
 * 
 * ファイルの読み込み、解析、統計情報取得などの機能を提供します。
 * 大容量ファイルの効率的な処理に重点を置いた実装です。
 */

/**
 * ファイルの行数を推定する
 * 
 * 大きなファイルの行数を効率的に推定します。
 * ファイルの先頭部分をサンプリングして平均行長を計算し、
 * 全体のファイルサイズから推定行数を算出します。
 * 
 * Params:
 *      filePath = 行数を推定するファイルのパス
 *
 * Returns:
 *      推定された行数
 */
size_t estimateLineCount(string filePath)
{
    auto file = File(filePath, "r");

    // ファイルサイズを取得
    auto fileSize = getSize(filePath);

    // サンプリングサイズ（先頭部分10KB）
    immutable size_t sampleSize = 10 * 1024;

    // サンプルを読み込む
    char[] buffer;
    buffer.length = min(sampleSize, fileSize);
    auto bytesRead = file.rawRead(buffer).length;

    // サンプル内の改行数をカウント
    size_t newlines = 0;
    foreach (char c; buffer[0 .. bytesRead])
    {
        if (c == '\n')
            newlines++;
    }

    // 平均行長を計算
    double avgLineLength = bytesRead / cast(double) max(1, newlines);

    // ファイル全体の行数を推定
    size_t estimatedLines = cast(size_t)(fileSize / avgLineLength);

    return estimatedLines;
}

/**
 * ファイルの正確な行数をカウントする
 * 
 * ファイル全体を走査して正確な行数を取得します。
 * 大きなファイルの場合は時間がかかる可能性があります。
 * 
 * Params:
 *      filePath = 行数をカウントするファイルのパス
 *
 * Returns:
 *      正確な行数
 */
size_t countLines(string filePath)
{
    auto file = File(filePath, "r");
    size_t lineCount = 0;
    
    foreach (line; file.byLine())
    {
        lineCount++;
    }
    
    return lineCount;
}

/**
 * ファイルの詳細統計情報を取得する
 */
struct FileStatistics
{
    string filePath; /// ファイルパス
    ulong fileSize; /// ファイルサイズ（バイト）
    size_t lineCount; /// 行数
    size_t characterCount; /// 文字数
    size_t wordCount; /// 単語数
    double averageLineLength; /// 平均行長
    size_t maxLineLength; /// 最大行長
    size_t minLineLength; /// 最小行長
    
    /**
     * 統計情報を表示する
     */
    void display() const
    {
        writeln("=== ファイル統計情報 ===");
        writefln("ファイル: %s", filePath);
        writefln("サイズ: %.2f MB (%d bytes)", fileSize / (1024.0 * 1024.0), fileSize);
        writefln("行数: %d", lineCount);
        writefln("文字数: %d", characterCount);
        writefln("単語数: %d", wordCount);
        writefln("平均行長: %.2f文字", averageLineLength);
        writefln("最大行長: %d文字", maxLineLength);
        writefln("最小行長: %d文字", minLineLength);
        writeln("=====================");
    }
}

/**
 * ファイルの詳細統計情報を計算する
 * 
 * Params:
 *      filePath = 統計を計算するファイルのパス
 *
 * Returns:
 *      ファイル統計情報
 */
FileStatistics analyzeFile(string filePath)
{
    FileStatistics stats;
    stats.filePath = filePath;
    stats.fileSize = getSize(filePath);
    stats.minLineLength = size_t.max;
    
    auto file = File(filePath, "r");
    
    foreach (line; file.byLine())
    {
        stats.lineCount++;
        size_t lineLength = line.length;
        stats.characterCount += lineLength;
        
        // 単語数をカウント（簡易版：空白で区切られた要素数）
        import std.algorithm : splitter;
        import std.ascii : isWhite;
        auto words = line.splitter!(c => isWhite(c));
        foreach (word; words)
        {
            if (word.length > 0)
                stats.wordCount++;
        }
        
        // 行長の統計
        if (lineLength > stats.maxLineLength)
            stats.maxLineLength = lineLength;
        if (lineLength < stats.minLineLength)
            stats.minLineLength = lineLength;
    }
    
    // 平均行長を計算
    if (stats.lineCount > 0)
        stats.averageLineLength = cast(double)stats.characterCount / stats.lineCount;
    
    // 最小行長の調整（空ファイルの場合）
    if (stats.minLineLength == size_t.max)
        stats.minLineLength = 0;
    
    return stats;
}

/**
 * CSVファイルの形式を検証する
 * 
 * Params:
 *      filePath = 検証するCSVファイルのパス
 *      expectedColumns = 期待する列数（0の場合は最初の行から判定）
 *
 * Returns:
 *      ファイルが有効なCSV形式の場合はtrue
 */
bool validateCSVFormat(string filePath, size_t expectedColumns = 0)
{
    try
    {
        auto file = File(filePath, "r");
        bool firstLine = true;
        size_t detectedColumns = 0;
        size_t lineNumber = 0;
        
        foreach (line; file.byLine())
        {
            lineNumber++;
            auto parts = line.split(",");
            
            if (firstLine)
            {
                detectedColumns = parts.length;
                if (expectedColumns == 0)
                    expectedColumns = detectedColumns;
                firstLine = false;
            }
            
            if (parts.length != expectedColumns)
            {
                writefln("CSV形式エラー: 行 %d で列数が不正です（期待: %d, 実際: %d）", 
                         lineNumber, expectedColumns, parts.length);
                return false;
            }
            
            // 最初の数行だけチェック（大きなファイルの場合）
            if (lineNumber > 100)
                break;
        }
        
        return true;
    }
    catch (Exception e)
    {
        writefln("CSV検証エラー: %s", e.msg);
        return false;
    }
}

/**
 * ファイルの文字エンコーディングを推定する
 * 
 * Params:
 *      filePath = 推定するファイルのパス
 *
 * Returns:
 *      推定されたエンコーディング名
 */
string detectEncoding(string filePath)
{
    auto file = File(filePath, "rb");
    ubyte[4] bom;
    auto bytesRead = file.rawRead(bom).length;
    
    // BOMによる判定
    if (bytesRead >= 3 && bom[0] == 0xEF && bom[1] == 0xBB && bom[2] == 0xBF)
        return "UTF-8 with BOM";
    if (bytesRead >= 4 && bom[0] == 0xFF && bom[1] == 0xFE && bom[2] == 0x00 && bom[3] == 0x00)
        return "UTF-32 LE";
    if (bytesRead >= 4 && bom[0] == 0x00 && bom[1] == 0x00 && bom[2] == 0xFE && bom[3] == 0xFF)
        return "UTF-32 BE";
    if (bytesRead >= 2 && bom[0] == 0xFF && bom[1] == 0xFE)
        return "UTF-16 LE";
    if (bytesRead >= 2 && bom[0] == 0xFE && bom[1] == 0xFF)
        return "UTF-16 BE";
    
    // 内容による簡易判定（ASCII/UTF-8）
    file.rewind();
    ubyte[1024] buffer;
    auto readBytes = file.rawRead(buffer).length;
    
    bool hasNonASCII = false;
    foreach (b; buffer[0 .. readBytes])
    {
        if (b > 127)
        {
            hasNonASCII = true;
            break;
        }
    }
    
    return hasNonASCII ? "UTF-8" : "ASCII";
}

/**
 * 一時ファイルのパスを生成する
 * 
 * Params:
 *      prefix = ファイル名のプレフィックス
 *      suffix = ファイル名のサフィックス（拡張子）
 *
 * Returns:
 *      一時ファイルのパス
 */
string generateTempFilePath(string prefix = "temp", string suffix = ".tmp")
{
    import std.random : uniform;
    import std.conv : to;
    import std.path : buildPath;
    
    auto randomNum = uniform(10_000, 99_999);
    auto tempFileName = prefix ~ "_" ~ randomNum.to!string ~ suffix;
    
    version (Windows)
    {
        import std.process : environment;
        auto tempDir = environment.get("TEMP", "C:\\Windows\\Temp");
    }
    else
    {
        auto tempDir = "/tmp";
    }
    
    return buildPath(tempDir, tempFileName);
}

/**
 * ファイルのバックアップを作成する
 * 
 * Params:
 *      originalPath = 元のファイルパス
 *      backupSuffix = バックアップファイルのサフィックス
 *
 * Returns:
 *      作成されたバックアップファイルのパス
 */
string createBackup(string originalPath, string backupSuffix = ".bak")
{
    import std.path : setExtension;
    import std.datetime : Clock;
    import std.format : format;
    
    auto timestamp = Clock.currTime();
    auto backupPath = format("%s_%04d%02d%02d_%02d%02d%02d%s",
                           originalPath,
                           timestamp.year, timestamp.month, timestamp.day,
                           timestamp.hour, timestamp.minute, timestamp.second,
                           backupSuffix);
    
    copy(originalPath, backupPath);
    return backupPath;
}

/**
 * ディレクトリのサイズを計算する
 * 
 * Params:
 *      dirPath = ディレクトリのパス
 *
 * Returns:
 *      ディレクトリ内のすべてのファイルの合計サイズ（バイト）
 */
ulong calculateDirectorySize(string dirPath)
{
    ulong totalSize = 0;
    
    if (!exists(dirPath) || !isDir(dirPath))
        return 0;
    
    try
    {
        foreach (DirEntry entry; dirEntries(dirPath, SpanMode.depth))
        {
            if (entry.isFile)
                totalSize += entry.size;
        }
    }
    catch (Exception e)
    {
        writefln("ディレクトリサイズ計算エラー: %s", e.msg);
    }
    
    return totalSize;
}

/**
 * ファイルが存在し、読み取り可能かチェックする
 * 
 * Params:
 *      filePath = チェックするファイルのパス
 *
 * Returns:
 *      ファイルが存在し読み取り可能な場合はtrue
 */
bool isFileReadable(string filePath)
{
    try
    {
        if (!exists(filePath) || !isFile(filePath))
            return false;
        
        auto file = File(filePath, "r");
        file.close();
        return true;
    }
    catch (Exception)
    {
        return false;
    }
}

/**
 * ファイルが書き込み可能かチェックする
 * 
 * Params:
 *      filePath = チェックするファイルのパス
 *
 * Returns:
 *      ファイルが書き込み可能な場合はtrue
 */
bool isFileWritable(string filePath)
{
    try
    {
        // ファイルが存在しない場合は、親ディレクトリの書き込み権限をチェック
        if (!exists(filePath))
        {
            import std.path : dirName;
            auto parentDir = dirName(filePath);
            return exists(parentDir) && isDir(parentDir);
        }
        
        auto file = File(filePath, "a");
        file.close();
        return true;
    }
    catch (Exception)
    {
        return false;
    }
} 

 