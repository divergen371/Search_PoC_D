module utils.system_utils;

import std.stdio;
import core.stdc.signal;
import core.stdc.stdlib : exit, atexit;

/**
 * システム関連のユーティリティ関数群
 * 
 * プログラムの終了処理、シグナルハンドリング、リソース管理などの
 * システムレベルの機能を提供します。
 */

// グローバル変数（シグナルハンドラから参照するため）
private File outputFile;
private string csvFilePath;
private bool needsCleanup = false;

/**
 * クリーンアップが必要なリソースを登録する
 * 
 * Params:
 *      file = 管理するファイル
 *      filePath = ファイルパス
 */
void registerCleanupResource(File file, string filePath)
{
    outputFile = file;
    csvFilePath = filePath;
    needsCleanup = true;
}

/**
 * プログラム終了時のクリーンアップ処理を実行する
 *
 * この関数は、プログラム終了時に必要なリソースの解放とファイルのクローズを行います。
 * 開いているCSVファイルがある場合は安全にクローズし、フラッシュを実行します。
 * 複数回呼び出されても安全になるよう、フラグによる制御を行っています。
 */
void cleanup()
{
    if (!needsCleanup)
        return;

    try
    {
        // ファイルのクローズ
        if (outputFile.isOpen())
        {
            outputFile.flush();
            outputFile.close();
            writeln("\nファイルを安全に閉じました: ", csvFilePath);
        }
    }
    catch (Exception e)
    {
        writeln("\nクリーンアップ中にエラーが発生しました: ", e.msg);
    }

    needsCleanup = false;
}

/**
 * シグナルハンドラ（非常にシンプルに保つ）
 *
 * SIGINT（Ctrl+C）やSIGTERMなどのシグナルを受信した際に呼び出されるハンドラです。
 * @nogc制約があるため、ここでは単純にプログラムを終了するだけで、
 * 実際のクリーンアップ処理はatexitで登録された関数が行います。
 *
 * Params:
 *      signal = 受信したシグナル番号
 */
extern (C) void signalHandler(int signal) nothrow @nogc
{
    // NOGCの制約があるため、ここでは単純にプログラムを終了するだけ
    // 実際のクリーンアップはatexitで登録された関数が行う
    exit(1);
}

/**
 * 終了時にクリーンアップを実行するコールバック
 *
 * atexit()で登録され、プログラム終了時に自動的に呼び出される関数です。
 * 開いているファイルがある場合は安全にクローズします。
 * nothrow制約があるため、例外が発生した場合は適切にキャッチして処理します。
 */
extern (C) void exitCallback() nothrow
{
    try
    {
        // ここでクリーンアップ処理を呼び出す
        if (needsCleanup && outputFile.isOpen())
        {
            outputFile.flush();
            outputFile.close();
            stderr.writeln("\nプログラム終了時にファイルを安全に閉じました: ", csvFilePath);
        }
    }
    catch (Exception)
    {
        // nothrow内では例外をキャッチする必要がある
    }
}

/**
 * システムの初期化を行う
 * 
 * シグナルハンドラの登録と終了時コールバックの設定を行います。
 */
void initializeSystem()
{
    // 終了時のコールバックを登録
    atexit(&exitCallback);

    // シグナルハンドラを設定
    signal(SIGINT, &signalHandler);
    signal(SIGTERM, &signalHandler);
    
    version (Posix)
    {
        // Unix系システムではSIGHUPとSIGQUITも処理
        import core.sys.posix.signal : SIGHUP, SIGQUIT;
        signal(SIGHUP, &signalHandler);
        signal(SIGQUIT, &signalHandler);
    }
}

/**
 * 安全にプログラムを終了する
 * 
 * Params:
 *      exitCode = 終了コード（デフォルト: 0）
 */
void safeExit(int exitCode = 0)
{
    cleanup();
    exit(exitCode);
}

/**
 * プログラムの実行時間測定クラス
 */
struct ExecutionTimer
{
    import std.datetime.stopwatch : StopWatch;
    
    private StopWatch stopwatch;
    private string timerName;
    private bool isRunning;
    
    /**
     * タイマーを開始する
     * 
     * Params:
     *      name = タイマー名
     */
    void start(string name = "Timer")
    {
        timerName = name;
        stopwatch.reset();
        stopwatch.start();
        isRunning = true;
        writefln("%s を開始しました", name);
    }
    
    /**
     * タイマーを停止し、結果を表示する
     */
    void stop()
    {
        if (!isRunning) return;
        
        stopwatch.stop();
        isRunning = false;
        
        auto elapsed = stopwatch.peek();
        writefln("%s が完了しました: %.3f秒", timerName, elapsed.total!"msecs" / 1000.0);
    }
    
    /**
     * 中間時間を表示する（タイマーは継続）
     */
    void lap(string message = "中間時間")
    {
        if (!isRunning) return;
        
        auto elapsed = stopwatch.peek();
        writefln("%s - %s: %.3f秒", timerName, message, elapsed.total!"msecs" / 1000.0);
    }
    
    /**
     * 経過時間を秒で取得する
     * 
     * Returns:
     *      経過時間（秒）
     */
    double getElapsedSeconds()
    {
        if (!isRunning) return 0.0;
        return stopwatch.peek().total!"msecs" / 1000.0;
    }
}

/**
 * プロセス情報を表す構造体
 */
struct ProcessInfo
{
    int processId; /// プロセスID
    string executablePath; /// 実行ファイルパス
    string[] commandLineArgs; /// コマンドライン引数
    ulong memoryUsage; /// メモリ使用量（バイト）
    double cpuUsage; /// CPU使用率（パーセント）
    
    /**
     * プロセス情報を表示する
     */
    void display() const
    {
        writeln("=== プロセス情報 ===");
        writefln("プロセスID: %d", processId);
        writefln("実行ファイル: %s", executablePath);
        writeln("コマンドライン引数:");
        foreach (i, arg; commandLineArgs)
        {
            writefln("  [%d] %s", i, arg);
        }
        writefln("メモリ使用量: %.2f MB", memoryUsage / (1024.0 * 1024.0));
        writefln("CPU使用率: %.2f%%", cpuUsage);
        writeln("==================");
    }
}

/**
 * 現在のプロセス情報を取得する
 * 
 * Returns:
 *      プロセス情報
 */
ProcessInfo getCurrentProcessInfo()
{
    import std.process : thisProcessID;
    import std.file : thisExePath;
    import std.process : environment;
    
    ProcessInfo info;
    info.processId = thisProcessID();
    
    try
    {
        info.executablePath = thisExePath();
    }
    catch (Exception)
    {
        info.executablePath = "Unknown";
    }
    
    // コマンドライン引数（簡易版）
    import std.process;
    info.commandLineArgs = ["Unknown"]; // 簡素化
    
    // メモリ使用量（GCからの情報）
    import core.memory : GC;
    auto stats = GC.stats();
    info.memoryUsage = stats.usedSize;
    
    // CPU使用率（ダミー値）
    info.cpuUsage = 0.0;
    
    return info;
}

/**
 * 環境変数の管理クラス
 */
class EnvironmentManager
{
    /**
     * 環境変数を取得する
     * 
     * Params:
     *      name = 環境変数名
     *      defaultValue = デフォルト値
     * 
     * Returns:
     *      環境変数の値
     */
    static string get(string name, string defaultValue = "")
    {
        import std.process : environment;
        return environment.get(name, defaultValue);
    }
    
    /**
     * 環境変数を設定する
     * 
     * Params:
     *      name = 環境変数名
     *      value = 値
     */
    static void set(string name, string value)
    {
        import std.process : environment;
        environment[name] = value;
    }
    
    /**
     * 環境変数が存在するかチェックする
     * 
     * Params:
     *      name = 環境変数名
     * 
     * Returns:
     *      存在する場合はtrue
     */
    static bool exists(string name)
    {
        import std.process : environment;
        return environment.get(name, null) !is null;
    }
    
    /**
     * すべての環境変数を表示する
     */
    static void displayAll()
    {
        import std.process : environment;
        writeln("=== 環境変数一覧 ===");
        foreach (name, value; environment.toAA())
        {
            writefln("%s = %s", name, value);
        }
        writeln("=================");
    }
}

/**
 * 一時的な作業ディレクトリを管理するクラス
 */
class TemporaryDirectory
{
    private string tempPath;
    private bool isCreated;
    
    /**
     * コンストラクタ
     * 
     * Params:
     *      prefix = ディレクトリ名のプレフィックス
     */
    this(string prefix = "temp_dir")
    {
        import std.random : uniform;
        import std.conv : to;
        import std.path : buildPath;
        import std.file : mkdirRecurse, tempDir;
        
        auto randomNum = uniform(10_000, 99_999);
        auto dirName = prefix ~ "_" ~ randomNum.to!string;
        tempPath = buildPath(tempDir(), dirName);
        
        try
        {
            mkdirRecurse(tempPath);
            isCreated = true;
            writefln("一時ディレクトリを作成しました: %s", tempPath);
        }
        catch (Exception e)
        {
            writefln("一時ディレクトリの作成に失敗しました: %s", e.msg);
            isCreated = false;
        }
    }
    
    /**
     * デストラクタ
     */
    ~this()
    {
        cleanup();
    }
    
    /**
     * 一時ディレクトリのパスを取得する
     * 
     * Returns:
     *      一時ディレクトリのパス
     */
    string getPath() const
    {
        return tempPath;
    }
    
    /**
     * 一時ディレクトリを削除する
     */
    void cleanup()
    {
        if (isCreated)
        {
            try
            {
                import std.file : rmdirRecurse, exists;
                if (exists(tempPath))
                {
                    rmdirRecurse(tempPath);
                    writefln("一時ディレクトリを削除しました: %s", tempPath);
                }
                isCreated = false;
            }
            catch (Exception e)
            {
                writefln("一時ディレクトリの削除に失敗しました: %s", e.msg);
            }
        }
    }
} 

 