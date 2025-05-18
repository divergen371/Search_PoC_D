module language_table;

import std.stdio, std.string, std.algorithm;
import std.path, std.file, std.conv;
import std.regex;
import std.array;
import core.sys.posix.signal;
import core.stdc.signal;
import core.stdc.stdlib : exit, atexit;
import std.range;
import std.algorithm.mutation : reverse;
import std.container.array;
import std.container : RedBlackTree;
import std.datetime.stopwatch : StopWatch;
import std.parallelism;
import core.memory;
import std.mmfile;
import std.math : abs; // 追加
import std.container.dlist : DList;
import std.bitmanip : BitArray;
import std.datetime : Clock, SysTime;

// 単語エントリの構造体
struct WordEntry
{
    string word; // 単語
    size_t id; // ID
    bool isDeleted; // 削除フラグ
}

// メモリ効率の良いストリングインターニングのためのプール
private string[string] stringPool;

/**
 * 文字列をインターン化する関数
 *
 * 同じ内容の文字列の複数コピーをメモリに保持することを避け、
 * 重複する文字列は同じメモリ領域を参照するようにする。
 *
 * Params:
 *      s = インターン化する文字列
 *
 * Returns:
 *      インターン化された文字列（同じ内容の文字列が既にプールにある場合はその参照）
 */
string internString(string s)
{
    if (auto p = s in stringPool)
        return *p;

    // 新しい文字列をプールに追加
    stringPool[s.idup] = s.idup;
    return stringPool[s];
}

// グローバル変数（シグナルハンドラから参照するため）
private File outputFile;
private string csvFilePath;
private bool needsCleanup = false;

/**
 * n-gram検索用のインデックス構造の最適化
 * ビット配列を使ったIDセット管理クラス
 *
 * この構造体は、単語IDのセットを効率的に管理するためのビットベースの実装です。
 * 検索処理の高速化とメモリ使用量の最適化を目的としています。
 */
struct GramIndexType
{
    private BitArray bits;
    private size_t maxID;

    /**
     * ビット配列を指定サイズで初期化する
     *
     * Params:
     *      maxSize = 初期化するビットアレイの最大サイズ（デフォルト1024）
     */
    void initialize(size_t maxSize = 1024)
    {
        // BitArrayの初期化
        auto storage = new size_t[(maxSize + 63) / 64 + 1];
        bits = BitArray(storage, maxSize);
        maxID = maxSize;
    }

    /**
     * IDをセットに追加する
     *
     * 必要に応じてビット配列のサイズを自動的に拡張します。
     *
     * Params:
     *      id = 追加するID
     */
    void add(size_t id)
    {
        // 必要に応じてサイズを拡張
        if (id >= maxID)
        {
            // 拡張時はより大きなビットアレイを作成
            size_t newSize = id + 1024;
            auto newStorage = new size_t[(newSize + 63) / 64 + 1];
            auto newBits = BitArray(newStorage, newSize);

            // 既存の値をコピー
            for (size_t i = 0; i < min(bits.length, newSize); i++)
            {
                if (i < bits.length && bits[i])
                    newBits[i] = true;
            }

            // 入れ替え
            bits = newBits;
            maxID = newSize;
        }

        if (id < bits.length)
            bits[id] = true;
    }

    /**
     * IDをセットから削除する
     *
     * Params:
     *      id = 削除するID
     */
    void remove(size_t id)
    {
        if (id < bits.length)
            bits[id] = false;
    }

    /**
     * 指定したIDがセットに含まれているか確認する
     *
     * Params:
     *      id = 確認するID
     *
     * Returns:
     *      IDが含まれている場合はtrue、そうでなければfalse
     */
    bool contains(size_t id) const
    {
        return id < bits.length && bits[id];
    }

    /**
     * セットに含まれるすべてのIDを配列として取得する
     *
     * Returns:
     *      セットに含まれるすべてのIDの配列
     */
    size_t[] keys() const
    {
        size_t[] result;
        for (size_t i = 0; i < bits.length; i++)
        {
            if (bits[i])
                result ~= i;
        }
        return result;
    }

    /**
     * セットに含まれるIDの数を取得する
     *
     * Returns:
     *      含まれるIDの数
     */
    size_t length() const
    {
        size_t count = 0;
        foreach (i; 0 .. bits.length)
        {
            if (bits[i])
                count++;
        }
        return count;
    }

    /**
     * セットからすべてのIDを削除する
     */
    void clear()
    {
        foreach (i; 0 .. bits.length)
            bits[i] = false;
    }

    /**
     * 指定されたIDセットとの論理積をとる
     *
     * 現在のセットと引数で指定されたセットの両方に存在するIDのみを残す
     *
     * Params:
     *      other = 交差するIDセット
     */
    void intersectWith(const ref GramIndexType other)
    {
        size_t minLength = min(bits.length, other.bits.length);
        for (size_t i = 0; i < minLength; i++)
        {
            bits[i] = bits[i] && other.bits[i];
        }

        // other より長い部分はfalseにする
        for (size_t i = minLength; i < bits.length; i++)
        {
            bits[i] = false;
        }
    }

    /**
     * in演算子のオーバーロード
     *
     * IDがセット内に存在するかを `id in set` の構文で確認できるようにする
     *
     * Params:
     *      id = 確認するID
     *
     * Returns:
     *      IDが含まれている場合はtrue、そうでなければfalse
     */
    auto opBinaryRight(string op : "in")(size_t id) const
    {
        return contains(id);
    }
}

/**
 * 進捗状況の追跡と表示を行う構造体
 *
 * 長時間かかる処理の進捗状況を追跡し、コンソールに表示するための機能を提供します。
 * 残り時間の推定や完了のレポート機能も含みます。
 */
struct ProgressTracker
{
    size_t total;
    size_t current;
    size_t lastPercent;
    StopWatch sw;

    /**
     * 進捗トラッカーを初期化する
     *
     * Params:
     *      total = 処理する合計アイテム数
     */
    void initialize(size_t total)
    {
        this.total = total;
        this.current = 0;
        this.lastPercent = 0;
        sw.reset();
        sw.start();
    }

    /**
     * 進捗を1つインクリメントし、必要に応じて進捗状況を表示する
     *
     * 5%単位で進捗状況がコンソールに表示されます。
     * 残り時間の推定も行います。
     */
    void increment()
    {
        current++;
        size_t percent = current * 100 / total;

        if (percent > lastPercent && percent % 5 == 0)
        {
            lastPercent = percent;

            // 残り時間の推定
            auto elapsed = sw.peek.total!"msecs";
            auto estimatedTotal = elapsed * total / current;
            auto remaining = estimatedTotal - elapsed;

            writef("\r進捗: %d%% (%d/%d) 残り約 %d秒    ",
                percent, current, total, remaining / 1000);
            stdout.flush();
        }
    }

    /**
     * 進捗追跡を完了し、最終的な結果を表示する
     *
     * 処理が完了した際に呼び出し、合計処理時間を表示します。
     */
    void finish()
    {
        sw.stop();
        writef("\r進捗: 100%% (%d/%d) 完了 (所要時間: %d秒)    \n",
            total, total, sw.peek.total!"seconds");
    }
}

// クリーンアップ処理
private void cleanup()
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

// シグナルハンドラ（非常にシンプルに保つ）
extern (C) void signalHandler(int signal) nothrow @nogc
{
    // NOGCの制約があるため、ここでは単純にプログラムを終了するだけ
    // 実際のクリーンアップはatexitで登録された関数が行う
    exit(1);
}

// 終了時にクリーンアップを実行するコールバック
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

// 自前のlowerBound（二分探索）
size_t lowerBound(T)(T[] arr, T value)
{
    size_t l = 0, r = arr.length;
    while (l < r)
    {
        size_t m = (l + r) / 2;
        if (arr[m] < value)
            l = m + 1;
        else
            r = m;
    }
    return l;
}

// 改善したcontains
// bool contains(ref GramIndexType set, size_t id)
// {
//     return (id in set) !is null;
// }

/**
 * 文字列を逆順にする
 *
 * Params:
 *      s = 逆順にする文字列
 *
 * Returns:
 *      逆順にした文字列
 */
string revStr(string s)
{
    if (s.length <= 1)
        return s;
    char[] result = new char[s.length];
    size_t j = s.length;
    foreach (i, char c; s)
    {
        result[--j] = c;
    }
    return cast(string) result;
}

/**
 * 単語からn-gramを生成し、インデックスに登録する
 *
 * 単語から2-gramを抽出し、グラムインデックスに単語IDを関連付けて登録します。
 * 同じ単語内で重複するgramは一度だけ登録されます。
 *
 * Params:
 *      word = 登録する単語
 *      id = 単語のID
 *      gramIndex = gramとIDのマッピングを保持するインデックス
 */
void registerNGrams(string word, size_t id, ref GramIndexType[string] gramIndex)
{
    if (word.length < 2)
        return;

    // 単語内の一意な2-gramだけを収集
    bool[string] uniqueGrams;
    for (size_t i = 0; i + 1 < word.length; i++)
    {
        auto gram = word[i .. i + 2 > word.length ? word.length: i + 2];
        uniqueGrams[gram] = true;
    }

    // 一意な2-gramだけをインデックスに追加
    foreach (gram; uniqueGrams.keys)
    {
        if (gram !in gramIndex)
        {
            gramIndex[gram] = GramIndexType();
            gramIndex[gram].initialize(id + 1024); // IDより少し大きめに初期化
        }
        gramIndex[gram].add(id);
    }
}

/**
 * 言語テーブルのメインエントリポイント
 * 
 * このプログラムは単語データベースとして機能し、様々な検索機能を提供します。
 * CSVファイルに単語を保存し、前方一致・後方一致・部分一致・類似度などによる検索が可能です。
 * インデックスを構築することで高速な検索を実現しています。
 */
void language_table()
{
    try
    {
        // GC はデフォルトで自動収集されるため明示的に無効化しない。
        // 大量データ読み込み時に GC を停止すると一時オブジェクトが解放されず
        // メモリを逼迫しやすくなるため、本バージョンでは disable() を撤去。
        // 必要に応じてパフォーマンス計測の際に手動で GC.collect を呼び出す運用とする。

        // 終了時のコールバックを登録
        atexit(&exitCallback);

        // シグナルハンドラを設定
        signal(SIGINT, &signalHandler);
        signal(SIGTERM, &signalHandler);

        // 計測用ストップウォッチ
        StopWatch totalSw;
        totalSw.start();

        // 絶対パスでCSVファイルを作成
        csvFilePath = absolutePath("language_data.csv");
        writeln("CSVファイルの出力先: ", csvFilePath);

        // 辞書の初期化（構造体ベース）
        WordEntry[string] wordDict; // 単語 -> エントリ
        WordEntry[size_t] idDict; // ID -> エントリ
        size_t nextID = 0;

        // 追加インデックス
        RedBlackTree!string prefixTree; // 単語そのままソート（木構造）
        RedBlackTree!string suffixTree; // 逆順文字列ソート（木構造）
        GramIndexType[string] gramIndex; // 2-gram -> ID集合
        bool[size_t][size_t] lengthIndex; // 長さ -> ID集合（長さによる検索の高速化）
        BKTree bkTree; // 類似単語検索用BK-Tree

        // キャッシュファイルパス
        string cachePath = csvFilePath ~ ".cache";
        IndexCache cache = IndexCache(cachePath);

        bool cacheLoaded = false;

        // 初期化
        // キャッシュが有効なら読み込み
        if (cache.isValid(csvFilePath))
        {
            writeln("キャッシュを読み込んでいます...");
            if (cache.loadFull(prefixTree, suffixTree, gramIndex, lengthIndex))
            {
                cacheLoaded = true;
                writeln(
                    "prefix/suffix/gram/length インデックスをキャッシュから復元");
            }
            else if (cache.load(prefixTree, suffixTree))
            {
                cacheLoaded = true;
                writeln(
                    "prefix/suffix インデックスをキャッシュから復元（旧形式）");
            }
        }

        if (!cacheLoaded)
        {
            prefixTree = new RedBlackTree!string;
            suffixTree = new RedBlackTree!string;
        }
        bkTree = new BKTree(&damerauDistanceLimited, 3); // 最大距離3でBK-Tree初期化

        // インデックス更新関数
        void insertPrefix(string word)
        {
            prefixTree.insert(word);
        }

        void insertSuffix(string word)
        {
            string r = revStr(word);
            suffixTree.insert(r);
        }

        void registerNGramsLocal(string word, size_t id)
        {
            registerNGrams(word, id, gramIndex);
        }

        void registerLength(string word, size_t id)
        {
            size_t len = word.length;
            if (len !in lengthIndex)
            {
                lengthIndex[len] = null;
            }
            lengthIndex[len][id] = true;
        }

        void registerBKTree(string word, size_t id)
        {
            bkTree.insert(word, id);
        }

        void removeFromLengthIndex(string word, size_t id)
        {
            size_t len = word.length;
            if (len in lengthIndex && id in lengthIndex[len])
            {
                lengthIndex[len].remove(id);
            }
        }

        // 既存のファイルが存在する場合は読み込む
        if (exists(csvFilePath))
        {
            writeln("既存のCSVファイルを読み込んでいます...");

            // ファイルサイズを取得して処理方法を決定
            auto fileSize = getSize(csvFilePath);
            writefln("ファイルサイズ: %.2f MB", fileSize / (1024.0 * 1024.0));

            // 進捗トラッカー
            ProgressTracker progress;

            // 大きなファイルならメモリマップ方式を使用
            if (fileSize > 50 * 1024 * 1024) // 50MB以上
            {
                writeln(
                    "大規模ファイルのため、メモリマップ方式で読み込みます...");

                // ファイル内の行数を概算（サンプリング方式）
                size_t estimatedLines = estimateLineCount(csvFilePath);
                writefln("推定行数: 約%d行", estimatedLines);

                // 進捗トラッカー初期化
                progress.initialize(estimatedLines);

                // メモリマップファイルを作成
                auto mmfile = new MmFile(csvFilePath);
                size_t lineStart = 0;
                size_t lineCount = 0;
                bool skipHeader = true;

                // エントリ配列を確保
                WordEntry[] entries;
                entries.reserve(estimatedLines);

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
                            auto parts = line.split(",");

                            if (parts.length >= 2)
                            {
                                size_t id = to!size_t(parts[0]);
                                string word = internString(parts[1].idup);
                                bool isDeleted = (parts.length >= 3 && parts[2] == "1");

                                // エントリを作成
                                WordEntry entry = WordEntry(word, id, isDeleted);
                                entries ~= entry;

                                // 最大IDを更新
                                if (id >= nextID)
                                {
                                    nextID = id + 1;
                                }
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

                // メモリマップファイルを閉じる
                destroy(mmfile);

                // 進捗を完了表示
                progress.finish();

                // この時点でのメモリ使用状況を報告
                reportMemoryUsage("CSV読み込み後");

                // 辞書とインデックス構築を最適化
                buildIndicesFromEntries(
                    entries, wordDict, idDict, prefixTree, suffixTree, gramIndex, lengthIndex, bkTree
                );

                // 構築が終わったらキャッシュ保存（prefix/suffixのみ）
                if (!cacheLoaded)
                {
                    writeln("キャッシュを保存しています...");
                    cache.saveFull(prefixTree, suffixTree, gramIndex, lengthIndex);
                }
            }
            else
            {
                // 小さいファイルは通常方式で読み込み
                auto inputFile = File(csvFilePath, "r");
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
                progress.initialize(lineCount - 1); // ヘッダー行を除く

                // ヘッダー行をスキップ
                if (!inputFile.eof())
                {
                    inputFile.readln(); // ID,単語,削除フラグ の行をスキップ
                }

                // 全てのエントリを一旦配列に読み込む
                WordEntry[] entries;
                entries.reserve(lineCount > 1 ? lineCount - 1 : 0); // ヘッダー行を除いた容量

                size_t processedLines = 0;
                foreach (line; inputFile.byLine())
                {
                    // CSV行を解析
                    auto parts = line.split(",");
                    if (parts.length >= 2)
                    {
                        size_t id = to!size_t(parts[0]);
                        // 文字列をインターン化してメモリ使用量を削減
                        string word = internString(parts[1].idup);
                        bool isDeleted = false;

                        // 削除フラグがある場合（新形式）
                        if (parts.length >= 3 && parts[2] == "1")
                        {
                            isDeleted = true;
                        }

                        // エントリを作成
                        WordEntry entry = WordEntry(word, id, isDeleted);
                        entries ~= entry;

                        // 最大IDを更新
                        if (id >= nextID)
                        {
                            nextID = id + 1;
                        }
                    }

                    // 進捗更新
                    processedLines++;
                    if (processedLines % 1000 == 0)
                    {
                        progress.increment();
                    }
                }

                progress.finish();

                // この時点でのメモリ使用状況を報告
                reportMemoryUsage("CSV読み込み後");

                // 辞書とインデックス構築を最適化
                buildIndicesFromEntries(
                    entries, wordDict, idDict, prefixTree, suffixTree, gramIndex, lengthIndex, bkTree
                );

                // 構築が終わったらキャッシュ保存（prefix/suffixのみ）
                if (!cacheLoaded)
                {
                    writeln("キャッシュを保存しています...");
                    cache.saveFull(prefixTree, suffixTree, gramIndex, lengthIndex);
                }
            }

            // 処理時間の報告
            totalSw.stop();
            writefln("全処理時間: %.2f秒", totalSw.peek.total!"msecs" / 1000.0);

            // GC統計の表示
            reportGCStats();
        }

        // CSVファイルを追記モードで開く
        outputFile = File(csvFilePath, "a");
        needsCleanup = true; // クリーンアップが必要

        // ファイルが新規作成の場合はヘッダーを書き込む
        if (!exists(csvFilePath) || getSize(csvFilePath) == 0)
        {
            outputFile.writeln("ID,単語,削除フラグ");
            outputFile.flush();
        }

        // 簡単な使い方の説明
        writeln("単語を入力してください。ヘルプを表示するには :h または :help と入力してください。");
        writeln("終了するには :exit と入力してください。");

        string line;

        // コマンド用の正規表現
        auto helpRegex = regex(r"^:(h|help)$");
        auto exitRegex = regex(r"^:(exit|quit|q|e)$");
        auto deleteRegex = regex(r"^:(delete|remove|d|r)\s+(\d+)$");
        auto undeleteRegex = regex(r"^:(undelete|restore|u)\s+(\d+)$");
        auto alphaRegex = regex(r"^:(alpha|a)$");
        auto preRegex = regex(r"^:(pre|prefix)\s+(\S+)$");
        auto sufRegex = regex(r"^:(suf|suffix)\s+(\S+)$");
        auto subRegex = regex(r"^:(sub|substr)\s+(\S+)$");
        auto exactRegex = regex(r"^:(exact|eq)\s+(\S+)$"); // 完全一致検索の正規表現
        auto rebuildRegex = regex(r"^:(rebuild|reindex)$"); // インデックス再構築用の正規表現
        auto andRegex = regex(r"^:(and)\s+(.+)$"); // AND検索用の正規表現
        auto orRegex = regex(r"^:(or)\s+(.+)$"); // OR検索用の正規表現 
        auto notRegex = regex(r"^:(not)\s+(\S+)$"); // NOT検索用の正規表現
        auto lengthExactRegex = regex(r"^:(length|len)\s+(\d+)$"); // 特定の長さ検索用
        auto lengthRangeRegex = regex(r"^:(length|len)\s+(\d+)-(\d+)$"); // 長さ範囲検索用
        auto idRangeRegex = regex(r"^:(id|ids)\s+(\d+)-(\d+)$"); // ID範囲検索用
        auto complexRegex = regex(r"^:(complex|comp)\s+(.+)$"); // 複合検索用
        auto simRegex = regex(r"^:(sim|similar)\s+(\S+)(?:\s+(\d+))?$"); // 類似検索用
        auto simPlusRegex = regex(r"^:(sim\+|similar\+)\s+(\S+)(?:\s+(\d+))?$"); // 拡張類似検索用

        // ヘルプメッセージを表示する関数
        void displayHelp()
        {
            writeln("\n====================== ヘルプ ======================");
            writeln("コマンド:");
            writeln("  :h, :help                     ヘルプを表示");
            writeln("  :exit, :quit, :q, :e          プログラムを終了");
            writeln("  :delete ID, :d ID, :r ID      指定したIDの単語を削除");
            writeln("  :undelete ID, :u ID           削除した単語を復元");
            writeln("  :list, :l                     登録単語一覧を表示（ID順）");
            writeln(
                "  :list-all, :la                削除済みを含む全単語を表示（ID順）");
            writeln("  :alpha, :a                    単語をアルファベット順に表示");
            writeln("  :pre, :prefix KEY            前方一致検索");
            writeln("  :suf, :suffix KEY            後方一致検索");
            writeln("  :sub, :substr KEY            部分一致検索");
            writeln("  :exact, :eq KEY              完全一致検索");
            writeln(
                "  :and KEY1 KEY2...            AND検索（すべてのキーワードを含む）");
            writeln(
                "  :or KEY1 KEY2...             OR検索（いずれかのキーワードを含む）");
            writeln("  :not KEY                     NOT検索（キーワードを含まない）");
            writeln("  :length N, :len N            特定の長さ(N文字)の単語を検索");
            writeln(
                "  :length N-M, :len N-M        特定の長さ範囲(N～M文字)の単語を検索");
            writeln("  :id N-M, :ids N-M            ID範囲(N～M)の単語を検索");
            writeln(
                "  :complex CONDS, :comp CONDS  複合検索（複数条件の組み合わせ）");
            writeln("    例: :complex pre:a suf:z len:3-5");
            writeln(
                "    例: :complex sim:apple,1 len:5-7  (「apple」との距離が1以下で5-7文字の単語)");
            writeln("  :sim WORD [d]                類似検索 (デフォルト距離d=2)");
            writeln(
                "  :sim+ WORD [d]               拡張類似検索 - より多くの結果を表示");
            writeln("  :rebuild, :reindex           インデックスを再構築");
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

        while (true)
        {
            // プロンプトを表示
            write("> ");
            stdout.flush(); // 強制的に出力

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

            // インデックス再構築コマンド
            if (matchFirst(line, rebuildRegex))
            {
                writeln("インデックスを再構築しています...");

                // 確認を求める
                write(
                    "この操作にはしばらく時間がかかります。続行しますか？ (y/n): ");
                stdout.flush();
                string confirm = strip(readln());
                if (confirm != "y" && confirm != "Y")
                {
                    writeln("インデックス再構築をキャンセルしました。");
                    continue;
                }

                // インデックスをクリア
                prefixTree.clear();
                suffixTree.clear();
                gramIndex.clear();
                lengthIndex.clear();

                // 既存のCSVファイルからエントリを読み込む
                if (exists(csvFilePath))
                {
                    auto inputFile = File(csvFilePath, "r");
                    StopWatch sw;
                    sw.start();

                    // ヘッダー行をスキップ
                    if (!inputFile.eof())
                    {
                        inputFile.readln(); // ID,単語,削除フラグ の行をスキップ
                    }

                    // 全てのエントリを一旦配列に読み込む
                    WordEntry[] entries;
                    entries.reserve(5000); // 初期予測値

                    foreach (csvLine; inputFile.byLine())
                    {
                        // CSV行を解析
                        auto parts = csvLine.split(",");
                        if (parts.length >= 2)
                        {
                            size_t id = to!size_t(parts[0]);
                            string word = internString(parts[1].idup);
                            bool isDeleted = false;

                            // 削除フラグがある場合（新形式）
                            if (parts.length >= 3 && parts[2] == "1")
                            {
                                isDeleted = true;
                            }

                            // エントリを作成
                            WordEntry entry = WordEntry(word, id, isDeleted);
                            entries ~= entry;
                        }
                    }

                    // 辞書も一旦クリア
                    wordDict.clear();
                    idDict.clear();

                    // インデックス再構築
                    buildIndicesFromEntries(
                        entries, wordDict, idDict, prefixTree, suffixTree, gramIndex, lengthIndex, bkTree
                    );

                    writeln("インデックスの再構築が完了しました！");
                }
                else
                {
                    writeln("エラー: CSVファイルが見つかりません。");
                }
                continue;
            }

            // 完全一致検索
            auto exactMatch = matchFirst(line, exactRegex);
            if (!exactMatch.empty)
            {
                string key = exactMatch[2];
                writeln("完全一致結果:");

                // 辞書から直接検索（高速）
                if (key in wordDict)
                {
                    auto entry = wordDict[key];
                    if (!entry.isDeleted)
                    {
                        writefln("ID:%d  %s", entry.id, key);
                    }
                    else
                    {
                        writeln("該当する単語は削除されています");
                    }
                }
                else
                {
                    writeln("該当なし");
                }
                continue;
            }

            // 検索コマンド（前方一致）
            auto preMatch = matchFirst(line, preRegex);
            if (!preMatch.empty)
            {
                string key = preMatch[2];
                writeln("前方一致結果:");

                // 時間計測開始
                StopWatch sw;
                sw.start();

                // 結果収集用の配列
                size_t[] matchedIDs;

                // RedBlackTreeを使って効率的に検索
                foreach (w; prefixTree)
                {
                    if (w.startsWith(key))
                    {
                        auto ent = wordDict[w];
                        if (!ent.isDeleted)
                        {
                            matchedIDs ~= ent.id;
                        }
                    }
                    else if (w > key && !w.startsWith(key))
                    {
                        // キーより大きいけど前方一致しない場合は終了
                        break;
                    }
                }

                // 時間計測終了
                sw.stop();
                auto elapsed = sw.peek.total!"usecs";

                // 結果表示
                displaySearchResults(matchedIDs, elapsed, "前方一致検索", idDict);

                continue;
            }

            // 後方一致
            auto sufMatch = matchFirst(line, sufRegex);
            if (!sufMatch.empty)
            {
                string key = revStr(sufMatch[2]);
                writeln("後方一致結果:");

                // 時間計測開始
                StopWatch sw;
                sw.start();

                // 結果収集用の配列
                size_t[] matchedIDs;

                // RedBlackTreeを使って効率的に検索
                foreach (rev; suffixTree)
                {
                    if (rev.startsWith(key))
                    {
                        auto w = revStr(rev);
                        auto ent = wordDict[w];
                        if (!ent.isDeleted)
                        {
                            matchedIDs ~= ent.id;
                        }
                    }
                    else if (rev > key && !rev.startsWith(key))
                    {
                        // キーより大きいけど前方一致しない場合は終了
                        break;
                    }
                }

                // 時間計測終了
                sw.stop();
                auto elapsed = sw.peek.total!"usecs";

                // 結果表示
                displaySearchResults(matchedIDs, elapsed, "後方一致検索", idDict);

                continue;
            }

            // 部分一致
            auto subMatch = matchFirst(line, subRegex);
            if (!subMatch.empty)
            {
                string key = subMatch[2];
                writeln("部分一致結果:");

                // 時間計測開始
                StopWatch sw;
                sw.start();

                // 結果収集用の配列
                size_t[] matchedIDs;

                if (key.length < 2)
                {
                    // キー長1の場合は線形スキャン
                    // 長さインデックスを活用する - 1文字の検索は特定の長さの単語にのみ検索
                    foreach (len; lengthIndex.keys)
                    {
                        foreach (id; lengthIndex[len].keys)
                        {
                            auto ent = idDict[id];
                            if (!ent.isDeleted && ent.word.canFind(key))
                            {
                                matchedIDs ~= id;
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
                    string firstGram = key[0 .. 2];
                    if (auto gramSet = firstGram in gramIndex)
                    {
                        // 最初のgramに含まれるIDをすべて候補に入れる
                        foreach (id; gramSet.keys())
                        {
                            candidateIDs[id] = true;
                        }
                        hasCandidate = true;
                    }

                    // 残りのgramでフィルタリング
                    if (hasCandidate)
                    {
                        for (size_t i = 1; i + 1 < key.length && candidateIDs.length > 0;
                            ++i)
                        {
                            string gram = key[i .. i + 2];
                            if (auto gramSet = gram in gramIndex)
                            {
                                // 候補を絞り込む
                                foreach (id; candidateIDs.keys.dup)
                                {
                                    if (!gramSet.contains(id))
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
                        auto ent = idDict[id];
                        if (!ent.isDeleted && ent.word.canFind(key))
                        {
                            matchedIDs ~= id;
                        }
                    }
                }

                // 時間計測終了
                sw.stop();
                auto elapsed = sw.peek.total!"usecs";

                // IDでソートして表示
                import std.algorithm.sorting : sort;

                sort(matchedIDs);

                // 結果表示
                displaySearchResults(matchedIDs, elapsed, "部分一致検索", idDict);

                continue;
            }

            // AND検索
            auto andMatch = matchFirst(line, andRegex);
            if (!andMatch.empty)
            {
                string searchParams = andMatch[2];
                auto keywords = searchParams.split();
                if (keywords.length < 2)
                {
                    writeln("エラー: AND検索には2つ以上のキーワードが必要です");
                    continue;
                }

                writeln("AND検索結果 (すべてのキーワードを含む):");
                size_t count = 0;

                // 全単語を検索
                foreach (id, entry; idDict)
                {
                    if (entry.isDeleted)
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
                        writefln("ID:%d  %s", entry.id, entry.word);
                        count++;
                    }
                }

                if (count == 0)
                    writeln("該当なし");
                continue;
            }

            // OR検索
            auto orMatch = matchFirst(line, orRegex);
            if (!orMatch.empty)
            {
                string searchParams = orMatch[2];
                auto keywords = searchParams.split();
                if (keywords.length < 2)
                {
                    writeln("エラー: OR検索には2つ以上のキーワードが必要です");
                    continue;
                }

                writeln("OR検索結果 (いずれかのキーワードを含む):");
                size_t count = 0;

                // 全単語を検索
                foreach (id, entry; idDict)
                {
                    if (entry.isDeleted)
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
                        writefln("ID:%d  %s", entry.id, entry.word);
                        count++;
                    }
                }

                if (count == 0)
                    writeln("該当なし");
                continue;
            }

            // NOT検索
            auto notMatch = matchFirst(line, notRegex);
            if (!notMatch.empty)
            {
                string key = notMatch[2];
                writeln("NOT検索結果 (キーワードを含まない):");
                size_t count = 0;

                // 全単語を検索
                foreach (id, entry; idDict)
                {
                    if (entry.isDeleted)
                        continue;

                    if (!entry.word.canFind(key))
                    {
                        writefln("ID:%d  %s", entry.id, entry.word);
                        count++;
                    }
                }

                if (count == 0)
                    writeln("該当なし");
                continue;
            }

            // 特定の長さの単語を検索
            auto lengthExactMatch = matchFirst(line, lengthExactRegex);
            if (!lengthExactMatch.empty)
            {
                size_t targetLength = to!size_t(lengthExactMatch[2]);
                writefln("長さ検索結果 (%d文字の単語):", targetLength);
                size_t count = 0;

                // インデックスを使用して長さで検索
                if (targetLength in lengthIndex)
                {
                    foreach (id; lengthIndex[targetLength].keys)
                    {
                        if (!idDict[id].isDeleted)
                        {
                            writefln("ID:%d  %s", id, idDict[id].word);
                            count++;
                        }
                    }
                }

                if (count == 0)
                    writeln("該当なし");
                continue;
            }

            // 長さ範囲の単語を検索
            auto lengthRangeMatch = matchFirst(line, lengthRangeRegex);
            if (!lengthRangeMatch.empty)
            {
                size_t minLength = to!size_t(lengthRangeMatch[2]);
                size_t maxLength = to!size_t(lengthRangeMatch[3]);

                // 範囲の整合性をチェック
                if (minLength > maxLength)
                {
                    writeln(
                        "エラー: 長さの範囲指定が不正です（最小値 > 最大値）");
                    continue;
                }

                writefln("長さ検索結果 (%d-%d文字の単語):", minLength, maxLength);
                size_t count = 0;

                // インデックスを使用して長さ範囲で検索
                for (size_t len = minLength; len <= maxLength; len++)
                {
                    if (len in lengthIndex)
                    {
                        foreach (id; lengthIndex[len].keys)
                        {
                            if (!idDict[id].isDeleted)
                            {
                                writefln("ID:%d  %s", id, idDict[id].word);
                                count++;
                            }
                        }
                    }
                }

                if (count == 0)
                    writeln("該当なし");
                continue;
            }

            // ID範囲検索
            auto idRangeMatch = matchFirst(line, idRangeRegex);
            if (!idRangeMatch.empty)
            {
                size_t minID = to!size_t(idRangeMatch[2]);
                size_t maxID = to!size_t(idRangeMatch[3]);

                // 範囲の整合性をチェック
                if (minID > maxID)
                {
                    writeln("エラー: ID範囲指定が不正です（最小値 > 最大値）");
                    continue;
                }

                // 有効なIDの範囲を確認
                size_t dictMinID = size_t.max;
                size_t dictMaxID = 0;

                if (idDict.length == 0)
                {
                    writeln("エラー: 辞書内に単語が存在しません");
                    continue;
                }

                // 辞書内の最小/最大IDを検索
                foreach (id; idDict.keys)
                {
                    if (id < dictMinID)
                        dictMinID = id;
                    if (id > dictMaxID)
                        dictMaxID = id;
                }

                // 完全に範囲外かどうかをチェック
                if (maxID < dictMinID || minID > dictMaxID)
                {
                    writefln("エラー: 指定されたID範囲 %d-%d は有効なID範囲 %d-%d の外です",
                        minID, maxID, dictMinID, dictMaxID);
                    continue;
                }

                // 部分的に範囲外かどうかをチェック
                bool partiallyOutOfRange = (minID < dictMinID || maxID > dictMaxID);

                // 実際の検索範囲を調整
                size_t effectiveMinID = max(minID, dictMinID);
                size_t effectiveMaxID = min(maxID, dictMaxID);

                if (partiallyOutOfRange)
                {
                    writefln("警告: 指定されたID範囲 %d-%d の一部が有効範囲 %d-%d の外です",
                        minID, maxID, dictMinID, dictMaxID);
                    writefln("有効なID範囲 %d-%d で検索を行います", effectiveMinID, effectiveMaxID);
                }

                writefln("ID範囲検索結果 (ID %d-%d の単語):", effectiveMinID, effectiveMaxID);

                // 結果をID順に表示するためにIDをソート
                size_t[] matchedIDs;

                // ID範囲で検索（有効範囲内のみ）
                for (size_t id = effectiveMinID; id <= effectiveMaxID; id++)
                {
                    if (id in idDict && !idDict[id].isDeleted)
                    {
                        matchedIDs ~= id;
                    }
                }

                // 結果をソート（IDはすでに順番に見ているので不要かもしれないが、念のため）
                sort(matchedIDs);

                // 結果を表示
                if (matchedIDs.length > 0)
                {
                    foreach (id; matchedIDs)
                    {
                        writefln("ID:%d  %s", id, idDict[id].word);
                    }
                    writefln("合計: %d件", matchedIDs.length);
                }
                else
                {
                    writeln("該当なし");

                    // 削除されたエントリを含めて検索するかどうか尋ねる
                    write("削除されたエントリを含めて検索しますか？ (y/n): ");
                    stdout.flush();
                    string confirm = strip(readln());

                    if (confirm == "y" || confirm == "Y")
                    {
                        // 削除されたエントリも含めて検索
                        matchedIDs = [];
                        for (size_t id = effectiveMinID; id <= effectiveMaxID; id++)
                        {
                            if (id in idDict)
                            {
                                matchedIDs ~= id;
                            }
                        }

                        sort(matchedIDs);

                        if (matchedIDs.length > 0)
                        {
                            writeln("削除されたエントリを含む検索結果:");
                            foreach (id; matchedIDs)
                            {
                                string status = idDict[id].isDeleted ? "[削除済]" : "[有効]";
                                writefln("ID:%d  %s %s", id, status, idDict[id].word);
                            }
                            writefln("合計: %d件", matchedIDs.length);
                        }
                        else
                        {
                            writeln("それでも該当なし");
                        }
                    }
                }
                continue;
            }

            // 複合検索
            auto complexMatch = matchFirst(line, complexRegex);
            if (!complexMatch.empty)
            {
                string params = complexMatch[2];
                writeln("複合検索を実行します:");

                // 条件を解析
                bool[size_t] candidateIDs;
                bool isFirstCondition = true;

                // 最初はすべてのIDを候補に入れる代わりに、最初の条件でフィルタする戦略にする

                // 条件ごとに処理
                string[] conditions = params.split();
                if (conditions.length == 0)
                {
                    writeln("エラー: 検索条件が指定されていません");
                    continue;
                }

                foreach (cond; conditions)
                {
                    // 条件の構文: 種類:値 または 種類:値1-値2
                    auto parts = cond.split(":");
                    if (parts.length != 2)
                    {
                        writefln("警告: 無効な条件「%s」をスキップします", cond);
                        continue;
                    }

                    string condType = parts[0];
                    string condValue = parts[1];

                    // 前方一致条件
                    if (condType == "pre")
                    {
                        bool[size_t] matchedIDs;

                        // RedBlackTreeを使って効率的に検索
                        foreach (w; prefixTree)
                        {
                            if (w.startsWith(condValue))
                            {
                                auto ent = wordDict[w];
                                if (!ent.isDeleted)
                                {
                                    matchedIDs[ent.id] = true;
                                }
                            }
                            else if (w > condValue && !w.startsWith(condValue))
                            {
                                // キーより大きいけど前方一致しない場合は終了
                                break;
                            }
                        }

                        if (isFirstCondition)
                        {
                            candidateIDs = matchedIDs;
                            isFirstCondition = false;
                        }
                        else
                        {
                            // ANDで絞り込む
                            foreach (id; candidateIDs.keys.dup)
                            {
                                if (id !in matchedIDs)
                                {
                                    candidateIDs.remove(id);
                                }
                            }
                        }

                        writefln("条件 pre:%s で %d件にフィルタリングしました", condValue, candidateIDs
                                .length);
                    }
                    // 後方一致条件
            else if (condType == "suf")
                    {
                        bool[size_t] matchedIDs;
                        string revCondValue = revStr(condValue);

                        // RedBlackTreeを使って効率的に検索
                        foreach (rev; suffixTree)
                        {
                            if (rev.startsWith(revCondValue))
                            {
                                auto w = revStr(rev);
                                auto ent = wordDict[w];
                                if (!ent.isDeleted)
                                {
                                    matchedIDs[ent.id] = true;
                                }
                            }
                            else if (rev > revCondValue && !rev.startsWith(revCondValue))
                            {
                                // キーより大きいけど前方一致しない場合は終了
                                break;
                            }
                        }

                        if (isFirstCondition)
                        {
                            candidateIDs = matchedIDs;
                            isFirstCondition = false;
                        }
                        else
                        {
                            // ANDで絞り込む
                            foreach (id; candidateIDs.keys.dup)
                            {
                                if (id !in matchedIDs)
                                {
                                    candidateIDs.remove(id);
                                }
                            }
                        }

                        writefln("条件 suf:%s で %d件にフィルタリングしました", condValue, candidateIDs
                                .length);
                    }
                    // 部分一致条件
            else if (condType == "sub")
                    {
                        bool[size_t] matchedIDs;

                        if (condValue.length < 2)
                        {
                            // キー長1の場合は線形スキャン
                            foreach (len; lengthIndex.keys)
                            {
                                foreach (id; lengthIndex[len].keys)
                                {
                                    auto ent = idDict[id];
                                    if (!ent.isDeleted && ent.word.canFind(condValue))
                                    {
                                        matchedIDs[id] = true;
                                    }
                                }
                            }
                        }
                        else
                        {
                            // 2文字以上の場合はn-gramインデックスを使用
                            bool hasCandidate = false;

                            // 初期gram
                            string firstGram = condValue[0 .. 2];
                            if (auto gramSet = firstGram in gramIndex)
                            {
                                // 最初のgramに含まれるIDをすべて候補に入れる
                                foreach (id; gramSet.keys())
                                {
                                    if (!idDict[id].isDeleted)
                                    {
                                        matchedIDs[id] = true;
                                    }
                                }
                                hasCandidate = true;
                            }

                            // 残りのgramでフィルタリング
                            if (hasCandidate)
                            {
                                for (size_t i = 1; i + 1 < condValue.length && matchedIDs.length > 0;
                                    ++i)
                                {
                                    string gram = condValue[i .. i + 2];
                                    if (auto gramSet = gram in gramIndex)
                                    {
                                        // 候補を絞り込む
                                        foreach (id; matchedIDs.keys.dup)
                                        {
                                            if (!gramSet.contains(id))
                                            {
                                                matchedIDs.remove(id);
                                            }
                                        }
                                    }
                                    else
                                    {
                                        // このgramがインデックスに存在しない場合、候補はゼロになる
                                        matchedIDs.clear();
                                        break;
                                    }
                                }
                            }

                            // 最終的な候補を確認（実際にsubstringが含まれるか）
                            foreach (id; matchedIDs.keys.dup)
                            {
                                auto ent = idDict[id];
                                if (!(!ent.isDeleted && ent.word.canFind(condValue)))
                                {
                                    matchedIDs.remove(id);
                                }
                            }
                        }

                        if (isFirstCondition)
                        {
                            candidateIDs = matchedIDs;
                            isFirstCondition = false;
                        }
                        else
                        {
                            // ANDで絞り込む
                            foreach (id; candidateIDs.keys.dup)
                            {
                                if (id !in matchedIDs)
                                {
                                    candidateIDs.remove(id);
                                }
                            }
                        }

                        writefln("条件 sub:%s で %d件にフィルタリングしました", condValue, candidateIDs
                                .length);
                    }
                    // not条件（含まない）
            else if (condType == "not")
                    {
                        if (isFirstCondition)
                        {
                            // 最初の条件がnotの場合は、すべての有効なIDを候補に入れる
                            foreach (id; idDict.keys)
                            {
                                if (!idDict[id].isDeleted)
                                {
                                    candidateIDs[id] = true;
                                }
                            }
                            isFirstCondition = false;
                        }

                        // 単語が指定文字列を含むIDを除外
                        foreach (id; candidateIDs.keys.dup)
                        {
                            if (idDict[id].word.canFind(condValue))
                            {
                                candidateIDs.remove(id);
                            }
                        }

                        writefln("条件 not:%s で %d件にフィルタリングしました", condValue, candidateIDs
                                .length);
                    }
                    // 長さ条件
            else if (condType == "len")
                    {
                        bool[size_t] matchedIDs;

                        // 範囲指定かどうかをチェック
                        auto rangeParts = condValue.split("-");
                        if (rangeParts.length == 2)
                        {
                            // 長さ範囲
                            try
                            {
                                size_t minLen = to!size_t(rangeParts[0]);
                                size_t maxLen = to!size_t(rangeParts[1]);

                                if (minLen > maxLen)
                                {
                                    writeln(
                                        "警告: 長さ範囲の指定が不正です（最小値 > 最大値）");
                                    continue;
                                }

                                // 長さインデックスを使用
                                for (size_t len = minLen; len <= maxLen; len++)
                                {
                                    if (len in lengthIndex)
                                    {
                                        foreach (id; lengthIndex[len].keys)
                                        {
                                            if (!idDict[id].isDeleted)
                                            {
                                                matchedIDs[id] = true;
                                            }
                                        }
                                    }
                                }
                            }
                            catch (Exception e)
                            {
                                writefln("警告: 長さ条件「%s」の解析中にエラーが発生しました", condValue);
                                continue;
                            }
                        }
                        else
                        {
                            // 特定の長さ
                            try
                            {
                                size_t targetLen = to!size_t(condValue);

                                if (targetLen in lengthIndex)
                                {
                                    foreach (id; lengthIndex[targetLen].keys)
                                    {
                                        if (!idDict[id].isDeleted)
                                        {
                                            matchedIDs[id] = true;
                                        }
                                    }
                                }
                            }
                            catch (Exception e)
                            {
                                writefln("警告: 長さ条件「%s」の解析中にエラーが発生しました", condValue);
                                continue;
                            }
                        }

                        if (isFirstCondition)
                        {
                            candidateIDs = matchedIDs;
                            isFirstCondition = false;
                        }
                        else
                        {
                            // ANDで絞り込む
                            foreach (id; candidateIDs.keys.dup)
                            {
                                if (id !in matchedIDs)
                                {
                                    candidateIDs.remove(id);
                                }
                            }
                        }

                        writefln("条件 len:%s で %d件にフィルタリングしました", condValue, candidateIDs
                                .length);
                    }
                    // ID範囲条件
            else if (condType == "id")
                    {
                        bool[size_t] matchedIDs;

                        // 範囲指定をチェック
                        auto rangeParts = condValue.split("-");
                        if (rangeParts.length == 2)
                        {
                            try
                            {
                                size_t minID = to!size_t(rangeParts[0]);
                                size_t maxID = to!size_t(rangeParts[1]);

                                if (minID > maxID)
                                {
                                    writeln(
                                        "警告: ID範囲の指定が不正です（最小値 > 最大値）");
                                    continue;
                                }

                                // ID範囲で検索
                                for (size_t id = minID; id <= maxID; id++)
                                {
                                    if (id in idDict && !idDict[id].isDeleted)
                                    {
                                        matchedIDs[id] = true;
                                    }
                                }
                            }
                            catch (Exception e)
                            {
                                writefln("警告: ID条件「%s」の解析中にエラーが発生しました", condValue);
                                continue;
                            }
                        }
                        else
                        {
                            writefln(
                                "警告: ID条件は範囲指定が必要です (例: id:100-200)");
                            continue;
                        }

                        if (isFirstCondition)
                        {
                            candidateIDs = matchedIDs;
                            isFirstCondition = false;
                        }
                        else
                        {
                            // ANDで絞り込む
                            foreach (id; candidateIDs.keys.dup)
                            {
                                if (id !in matchedIDs)
                                {
                                    candidateIDs.remove(id);
                                }
                            }
                        }

                        writefln("条件 id:%s で %d件にフィルタリングしました", condValue, candidateIDs
                                .length);
                    }
                    // 類似度検索条件
            else if (condType == "sim")
                    {
                        bool[size_t] matchedIDs;

                        // パラメータ解析（単語[,最大距離]）
                        auto simParams = condValue.split(",");
                        string query = simParams[0];
                        size_t maxDist = 2; // デフォルト値

                        if (simParams.length >= 2)
                        {
                            try
                            {
                                maxDist = to!size_t(simParams[1]);
                            }
                            catch (Exception e)
                            {
                                writefln("警告: 類似度の距離パラメータが不正です、デフォルト値(2)を使用します");
                            }
                        }

                        // BK-Treeを使用して高速に類似検索
                        auto results = bkTree.search(query, maxDist, false); // 通常モード

                        // 結果を格納
                        foreach (r; results)
                        {
                            if (!idDict[r.id].isDeleted)
                            {
                                matchedIDs[r.id] = true;
                            }
                        }

                        if (isFirstCondition)
                        {
                            candidateIDs = matchedIDs;
                            isFirstCondition = false;
                        }
                        else
                        {
                            // ANDで絞り込む
                            foreach (id; candidateIDs.keys.dup)
                            {
                                if (id !in matchedIDs)
                                {
                                    candidateIDs.remove(id);
                                }
                            }
                        }

                        writefln("条件 sim:%s (距離<=%d) で %d件にフィルタリングしました",
                            query, maxDist, candidateIDs.length);
                    }
                    else
                    {
                        writefln("警告: 未知の条件タイプ「%s」です", condType);
                    }

                    // 候補が0になったらこれ以上処理しない
                    if (candidateIDs.length == 0)
                    {
                        break;
                    }
                }

                // 結果の表示
                if (candidateIDs.length > 0)
                {
                    writeln("検索結果:");

                    // IDでソートして表示
                    size_t[] sortedIDs = candidateIDs.keys;
                    sort(sortedIDs);

                    foreach (id; sortedIDs)
                    {
                        writefln("ID:%d  %s", id, idDict[id].word);
                    }
                    writefln("合計: %d件", sortedIDs.length);
                }
                else
                {
                    writeln("該当なし");
                }

                continue;
            }

            // ヘルプコマンドをチェック
            if (matchFirst(line, helpRegex))
            {
                displayHelp();
                continue;
            }

            // 終了コマンドをチェック
            if (matchFirst(line, exitRegex))
            {
                writeln("処理を終了します...");
                break;
            }

            // アルファベット順表示コマンド
            if (matchFirst(line, alphaRegex))
            {
                writeln("登録単語一覧（アルファベット順）:");

                // 有効な単語のみを抽出
                WordEntry[] activeEntries;
                foreach (entry; wordDict.values)
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
                continue;
            }

            // 一覧表示コマンド（アクティブな単語のみ）
            if (line == ":list" || line == ":l")
            {
                writeln("登録単語一覧（有効な単語のみ）:");
                size_t[] sortedIDs = idDict.keys;
                sort(sortedIDs);
                bool foundAny = false;

                foreach (id; sortedIDs)
                {
                    if (!idDict[id].isDeleted)
                    {
                        writefln("%5d: %s", id, idDict[id].word);
                        foundAny = true;
                    }
                }

                if (!foundAny)
                {
                    writeln("有効な単語はありません");
                }
                continue;
            }

            // 一覧表示コマンド（全単語、削除フラグ付き）
            if (line == ":list-all" || line == ":la")
            {
                writeln("登録単語一覧（削除済みを含む）:");
                size_t[] sortedIDs = idDict.keys;
                sort(sortedIDs);

                foreach (id; sortedIDs)
                {
                    string status = idDict[id].isDeleted ? "[削除済]" : "[有効]";
                    writefln("%5d: %s %s", id, status, idDict[id].word);
                }
                continue;
            }

            // 削除コマンドをチェック
            auto deleteMatch = matchFirst(line, deleteRegex);
            if (!deleteMatch.empty)
            {
                size_t idToDelete = to!size_t(deleteMatch[2]);
                if (idToDelete in idDict)
                {
                    if (idDict[idToDelete].isDeleted)
                    {
                        writefln("ID %dの単語「%s」は既に削除されています",
                            idToDelete, idDict[idToDelete].word);
                    }
                    else
                    {
                        // 削除フラグを立てる（論理削除）
                        string wordToDelete = idDict[idToDelete].word;
                        idDict[idToDelete].isDeleted = true;
                        wordDict[wordToDelete].isDeleted = true;

                        // 削除操作をCSVに直接追記
                        outputFile.writefln("%s,%s,1", idToDelete, wordToDelete);
                        outputFile.flush();

                        // プレフィックスとサフィックスインデックスから削除
                        prefixTree.removeKey(wordToDelete);
                        string revWord = revStr(wordToDelete);
                        suffixTree.removeKey(revWord);

                        writefln("ID %dの単語「%s」を削除しました", idToDelete, wordToDelete);
                    }
                }
                else
                {
                    writefln("ID %dの単語は見つかりませんでした", idToDelete);
                }
                continue;
            }

            // 削除復元コマンドをチェック
            auto undeleteMatch = matchFirst(line, undeleteRegex);
            if (!undeleteMatch.empty)
            {
                size_t idToRestore = to!size_t(undeleteMatch[2]);
                if (idToRestore in idDict)
                {
                    if (!idDict[idToRestore].isDeleted)
                    {
                        writefln("ID %dの単語「%s」は削除されていません",
                            idToRestore, idDict[idToRestore].word);
                    }
                    else
                    {
                        // 削除フラグを下ろす
                        string wordToRestore = idDict[idToRestore].word;
                        idDict[idToRestore].isDeleted = false;
                        wordDict[wordToRestore].isDeleted = false;

                        // 復元操作をCSVに直接追記
                        outputFile.writefln("%s,%s,0", idToRestore, wordToRestore);
                        outputFile.flush();

                        // インデックスに追加
                        insertPrefix(wordToRestore);
                        insertSuffix(wordToRestore);
                        registerLength(wordToRestore, idToRestore);
                        registerBKTree(wordToRestore, idToRestore); // BK-Treeに追加

                        writefln("ID %dの単語「%s」を復元しました", idToRestore, wordToRestore);
                    }
                }
                else
                {
                    writefln("ID %dの単語は見つかりませんでした", idToRestore);
                }
                continue;
            }

            // 類似検索 (BK-Tree使用)
            auto simMatch = matchFirst(line, simRegex);
            if (!simMatch.empty)
            {
                string query = simMatch[2];
                size_t maxDist = 2;
                if (simMatch.length >= 4 && simMatch[3].length > 0)
                    maxDist = to!size_t(simMatch[3]);

                writefln("類似検索: \"%s\" (距離<=%d)", query, maxDist);

                // BK-Treeを使用して高速に類似検索
                StopWatch sw;
                sw.start();

                auto results = bkTree.search(query, maxDist, false); // 通常モード

                sw.stop();
                auto elapsed = sw.peek.total!"usecs";

                // 検索結果表示関数を使用
                displaySearchResults(results, elapsed, "通常モード", idDict, true, true);

                continue;
            }

            // 拡張類似検索 (BK-Tree使用、より網羅的)
            auto simPlusMatch = matchFirst(line, simPlusRegex);
            if (!simPlusMatch.empty)
            {
                string query = simPlusMatch[2];
                size_t maxDist = 2;
                if (simPlusMatch.length >= 4 && simPlusMatch[3].length > 0)
                    maxDist = to!size_t(simPlusMatch[3]);

                writefln("拡張類似検索: \"%s\" (距離<=%d)", query, maxDist);

                // BK-Treeを使用して高速に類似検索（拡張モード）
                StopWatch sw;
                sw.start();

                auto results = bkTree.search(query, maxDist, true); // 拡張モード

                sw.stop();
                auto elapsed = sw.peek.total!"usecs";

                // 検索結果表示関数を使用
                displaySearchResults(results, elapsed, "拡張モード", idDict, true, true);

                continue;
            }

            // 通常の単語追加処理
            foreach (word; splitter(line))
            {
                // コマンド（":"で始まるトークン）は単語追加対象から除外
                if (word.length > 0 && word[0] == ':')
                    continue;

                if (word in wordDict)
                {
                    if (wordDict[word].isDeleted)
                    {
                        // 削除された単語が再度追加された場合は復元する
                        size_t existingID = wordDict[word].id;
                        idDict[existingID].isDeleted = false;
                        wordDict[word].isDeleted = false;

                        // ファイルを更新
                        updateCSVFile(csvFilePath, wordDict, idDict);

                        writefln("単語「%s」(ID %d)は削除されていましたが、復元しました",
                            word, existingID);
                    }
                    else
                    {
                        writefln("単語「%s」は既にID %dで登録されています",
                            word, wordDict[word].id);
                    }
                    continue;
                }

                auto newID = nextID++;
                // インターン化された文字列を使用
                string internedWord = internString(word.idup);
                WordEntry newEntry = WordEntry(internedWord, newID, false);

                // 辞書に追加
                wordDict[internedWord] = newEntry;
                idDict[newID] = newEntry;

                // インデックスに追加
                insertPrefix(internedWord);
                insertSuffix(internedWord);
                registerNGramsLocal(internedWord, newID);
                registerLength(internedWord, newID);
                registerBKTree(internedWord, newID); // BK-Treeに追加

                // CSVに書き込む
                outputFile.writefln("%s,%s,0", newID, word);
                outputFile.flush(); // 各行ごとにフラッシュ

                // 確認用に標準出力にも表示
                writefln("単語「%s」をIDは%sでCSVに追加しました", word, newID);
            }
        }

        // 正常終了時のクリーンアップ
        cleanup();

        // ファイルが本当に作成されたか確認
        if (exists(csvFilePath))
        {
            writeln("CSVファイルが正常に作成されました: ", csvFilePath);
            writeln("ファイルサイズ: ", getSize(csvFilePath), " バイト");

            // 有効な単語数を数える
            size_t activeCount = 0;
            foreach (entry; idDict.values)
            {
                if (!entry.isDeleted)
                {
                    activeCount++;
                }
            }

            writefln("合計%d件の単語が登録されています（うち有効：%d件）",
                idDict.length, activeCount);
        }
        else
        {
            writeln("エラー: ファイルが作成されませんでした");
        }
    }
    catch (Exception e)
    {
        writeln("ファイル操作中にエラーが発生しました: ", e.msg);
        // 例外発生時もクリーンアップを行う
        cleanup();
    }
}

// CSVファイルを辞書の内容で更新する
void updateCSVFile(string filePath, WordEntry[string] wordDict, WordEntry[size_t] idDict)
{
    // 開始時間計測
    StopWatch sw;
    sw.start();

    writeln("ファイル更新中です...");

    // 一時ファイルに書き込む
    string tempPath = filePath ~ ".tmp";
    auto tempFile = File(tempPath, "w");

    // ヘッダーを書き込む
    tempFile.writeln("ID,単語,削除フラグ");

    // 辞書の内容を書き込む - バッファリングを活用するためにバッチ処理
    size_t[] sortedIDs = idDict.keys;
    sort(sortedIDs);

    // 大規模ファイル向けバッファリング
    char[] buffer;
    buffer.reserve(8192); // 8KBのバッファを予約

    // 並列処理をやめて、シンプルな処理に変更（パフォーマンスは少し低下するが安全）
    foreach (id; sortedIDs)
    {
        auto entry = idDict[id];
        string line = to!string(entry.id) ~ "," ~ entry.word ~ "," ~ (entry.isDeleted ? "1" : "0") ~ "\n";
        tempFile.write(line);
    }

    tempFile.close();

    // 元のファイルを置き換える
    if (exists(filePath))
    {
        remove(filePath);
    }
    rename(tempPath, filePath);

    // 処理時間計測終了
    sw.stop();
    writefln("ファイル更新完了 (処理時間: %s ミリ秒)", sw.peek.total!"msecs");
}

// ファイル内の行数を推定する関数
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

// メモリ使用状況を報告する関数
void reportMemoryUsage(string phase)
{
    GC.collect();
    auto stats = GC.stats();
    writefln("[%s] メモリ使用量: %.2f MB (使用中: %.2f MB, 空き: %.2f MB)",
        phase,
        stats.usedSize / (1024.0 * 1024.0),
        stats.usedSize / (1024.0 * 1024.0),
        stats.freeSize / (1024.0 * 1024.0));
}

/**
 * 検索実行時間を詳細に表示する関数
 *
 * 検索結果とともに、検索にかかった時間を秒、ミリ秒、マイクロ秒の単位で表示します。
 * 様々な検索機能で共通して使用するための汎用関数です。
 *
 * Params:
 *      results = 検索結果（任意の型の配列）
 *      elapsedTime = 検索に要した時間（マイクロ秒単位）
 *      searchType = 検索の種類を示す文字列
 *      idDict = ID -> WordEntry のマッピング
 *      showDetails = 各結果の詳細を表示するかどうか
 *      showDistance = 距離情報を表示するかどうか（類似検索用）
 */
void displaySearchResults(T)(T[] results, long elapsedTime, string searchType,
    WordEntry[size_t] idDict, bool showDetails = true,
    bool showDistance = false)
{
    if (results.length == 0)
    {
        writeln("該当なし");
        writefln("検索時間: %.6f秒 (%d.%03d%03dミリ秒)",
            elapsedTime / 1_000_000.0,
            elapsedTime / 1_000_000,
            (elapsedTime % 1_000_000) / 1_000,
            elapsedTime % 1_000);
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
                if (!idDict[r.id].isDeleted)
                {
                    if (showDistance)
                        writefln("ID:%d  距離:%d  %s", r.id, r.dist, idDict[r.id].word);
                    else
                        writefln("ID:%d  %s", r.id, idDict[r.id].word);
                    activeCount++;
                }
            }
        }
        else
        {
            // 詳細を表示しない場合は件数だけカウント
            foreach (r; results)
                if (!idDict[r.id].isDeleted)
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
                if (!idDict[id].isDeleted)
                {
                    writefln("ID:%d  %s", id, idDict[id].word);
                    activeCount++;
                }
            }
        }
        else
        {
            // 詳細を表示しない場合は件数だけカウント
            foreach (id; results)
                if (!idDict[id].isDeleted)
                    activeCount++;
        }
    }
    else
    {
        // その他の型はとりあえず件数だけカウント
        activeCount = results.length;
    }

    // 検索時間と件数の表示
    // 秒単位・マイクロ秒単位の両方で表示
    writefln("合計: %d件 (%s)",
        activeCount, searchType);
    
    // マイクロ秒から各単位に変換
    long msec = elapsedTime / 1_000; // ミリ秒
    long usec = elapsedTime % 1_000; // マイクロ秒（余り）
    
    // 明確に区分けして表示
    writefln("検索時間: %.6f秒 (%d.%03dミリ秒 = %dマイクロ秒)",
        elapsedTime / 1_000_000.0,  // 秒（小数点表示）
        msec / 1_000,               // 秒（整数部）
        msec % 1_000,               // ミリ秒（小数部）
        elapsedTime);               // 全マイクロ秒
}

// GC統計情報を報告
void reportGCStats()
{
    auto stats = GC.stats();
    writeln("\nGC統計情報:");
    writefln("  総容量: %.2f MB", (stats.usedSize + stats.freeSize) / (1024.0 * 1024.0));
    writefln("  使用中: %.2f MB", stats.usedSize / (1024.0 * 1024.0));
    writefln("  空き: %.2f MB", stats.freeSize / (1024.0 * 1024.0));
    writefln("  コレクション回数: %d", GC.profileStats().numCollections);
}

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
void buildIndicesFromEntries(
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
    bkTree = new BKTree(&damerauDistanceLimited, 3);

    // rehashメソッドの代わりに、十分な容量を確保してから登録する

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

    // BK-Treeの構築は並列処理から分離し、単一スレッドで行う
    // これによりメモリアクセスの競合を避ける

    // 前処理: 長さインデックスの初期化は既に完了

    // 1. プレフィックスとサフィックスインデックスの構築（並列化可能）
    // 各チャンクを処理するタスクを作成
    // ワーカーIDごとにローカルツリーを管理するためのハッシュマップを用意
    RedBlackTree!string[size_t] localPrefixTrees;
    RedBlackTree!string[size_t] localSuffixTrees;
    size_t[size_t] processCounts;

    // 分割して並列処理
    auto chunks = activeEntries.chunks(itemsPerTask).array;
    if (chunks.length > 0)
    { // 空の配列チェック
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
            { // 空のチャンクをスキップ
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
    else
    {
        // 空の場合は何もしない
        writeln("警告: 有効なエントリがありません");
    }

    // 結果をマージ
    foreach (workerId, localTree; localPrefixTrees)
    {
        foreach (w; localTree)
            prefixTree.insert(w);
        foreach (w; localSuffixTrees[workerId])
            suffixTree.insert(w);

        progressCounter += processCounts[workerId];
    }

    // 進捗バーを更新
    progress.current = progressCounter;
    progress.increment();

    // 2. n-gramインデックスの構築（並列化）
    // ワーカーIDごとにローカルインデックスを管理するハッシュマップ
    GramIndexType[string][size_t] localGramIndices;

    // 分割サイズを計算
    size_t chunkSize = max(1, activeEntries.length / taskPool.size);
    auto entryChunks = activeEntries.chunks(chunkSize).array;

    // 並列処理
    if (entryChunks.length > 0)
    { // 空の配列チェック
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
            { // 空のチャンクをスキップ
                foreach (entry; chunk)
                {
                    // グラム生成（ローカル）
                    if (entry.word.length >= 2)
                    {
                        // 単語内の一意な2-gramだけを収集
                        bool[string] uniqueGrams;
                        for (size_t i = 0; i + 1 < entry.word.length; i++)
                        {
                            auto gram = entry.word[i .. i + 2 > entry.word.length ? entry.word.length: i + 2];
                            uniqueGrams[gram] = true;
                        }

                        // 一意な2-gramだけをローカルインデックスに追加
                        foreach (gram; uniqueGrams.keys)
                        {
                            if (gram !in localGramIndices[workerId])
                            {
                                synchronized (mutex)
                                { // 初期化時は同期
                                    if (gram !in localGramIndices[workerId])
                                    {
                                        localGramIndices[workerId][gram] = GramIndexType();
                                        localGramIndices[workerId][gram].initialize(entry.id + 1024);
                                    }
                                }
                            }
                            localGramIndices[workerId][gram].add(entry.id);
                        }
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
    else
    {
        writeln("警告: NGramインデックス構築用のエントリがありません");
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

    // BK-Treeを安全に構築（並列処理の外で実行）
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
 * 制限付きDamerau-Levenshtein距離を計算する
 *
 * 2つの文字列間の編集距離を計算します。挿入、削除、置換、隣接する2文字の入れ替えをカウントします。
 * 指定された最大距離を超えた場合は早期に計算を打ち切り、効率化を図ります。
 *
 * Params:
 *      s = 1つ目の文字列
 *      t = 2つ目の文字列
 *      maxDist = 計算を打ち切る最大距離（これより大きい場合はmaxDist+1を返す）
 *
 * Returns:
 *      2つの文字列間のDamerau-Levenshtein距離。maxDistを超える場合はmaxDist+1
 */
size_t damerauDistanceLimited(string s, string t, size_t maxDist)
{
    import std.algorithm : min, max;

    size_t m = s.length;
    size_t n = t.length;

    // デバッグ用表示
    debug (verbose)
        writefln("距離計算: s='%s'(%d) と t='%s'(%d), maxDist=%d", s, m, t, n, maxDist);

    // 自分自身との比較は常に距離0（最初にチェック）
    if (s == t)
    {
        debug (verbose)
            writeln("  同一文字列: 結果=0");
        return 0;
    }

    // 長さの差が最大距離を超えるなら早期リターン
    // 条件を統一：文字列長に関係なく同じ条件を適用
    if (abs(cast(int) m - cast(int) n) > maxDist)
    {
        debug (verbose)
            writeln("  早期リターン: 長さの差が制限を超えています");
        return maxDist + 1;
    }

    // 空文字列の処理
    if (m == 0)
        return n <= maxDist ? n : maxDist + 1;
    if (n == 0)
        return m <= maxDist ? m : maxDist + 1;

    // 以下、元のアルゴリズムを続ける
    size_t[] prevPrev;
    prevPrev.length = n + 1;
    size_t[] prev;
    prev.length = n + 1;
    size_t[] curr;
    curr.length = n + 1;

    foreach (j; 0 .. n + 1)
        prev[j] = j;

    foreach (i; 1 .. m + 1)
    {
        curr[0] = i;
        size_t minInRow = maxDist + 1;
        foreach (j; 1 .. n + 1)
        {
            size_t cost = (s[i - 1] == t[j - 1]) ? 0 : 1;
            size_t del = prev[j] + 1;
            size_t ins = curr[j - 1] + 1;
            size_t sub = prev[j - 1] + cost;
            size_t val = min(min(del, ins), sub);
            if (i > 1 && j > 1 && s[i - 1] == t[j - 2] && s[i - 2] == t[j - 1])
            {
                val = min(val, prevPrev[j - 2] + cost);
            }
            curr[j] = val;
            if (val < minInRow)
                minInRow = val;
        }
        if (minInRow > maxDist)
            return maxDist + 1; // 打ち切り
        prevPrev[] = prev[];
        prev[] = curr[];
    }

    debug (verbose)
        writefln("  計算結果: 距離=%d", prev[n]);
    return prev[n];
}

/**
 * BK-Tree (Burkhard-Keller Tree) クラス
 *
 * 類似文字列検索のための空間索引木を実装したクラスです。
 * 距離メトリックを用いて効率的に類似文字列を検索することができます。
 * 特に編集距離を用いた類似検索に適しています。
 */
class BKTree
{
private:
    // ノード構造体
    static struct Node
    {
        string word; // 単語
        size_t id; // 単語ID
        Node*[size_t] children; // 距離ごとの子ノード
    }

    Node* root; // ルートノード

    // 距離関数へのポインタ型
    alias DistanceFn = size_t function(string, string, size_t);

    // 使用する距離関数
    DistanceFn distanceFn;

    // 最大距離
    size_t maxDistance;

    // 統計情報
    size_t nodeCount;

public:
    /**
     * BK-Treeコンストラクタ
     *
     * Params:
     *      fn = 距離計算関数（2つの文字列と最大距離を受け取り、その距離を返す関数）
     *      maxDist = 検索で使用する最大距離（デフォルト3）
     */
    this(DistanceFn fn, size_t maxDist = 3)
    {
        this.distanceFn = fn;
        this.maxDistance = maxDist;
        this.root = null;
        this.nodeCount = 0;
    }

    /**
     * 複数の単語をバッチで挿入する
     *
     * メモリ効率と安全性を向上させるため、複数の単語を一度に挿入します。
     *
     * Params:
     *      words = 挿入する単語の配列
     *      ids = 単語に対応するIDの配列
     *      showProgress = 進捗状況を表示するかどうか
     */
    void batchInsert(string[] words, size_t[] ids, bool showProgress = false)
    {
        if (words.length == 0 || words.length != ids.length)
            return;

        size_t total = words.length;
        size_t processed = 0;
        size_t lastPercent = 0;
        StopWatch sw;

        if (showProgress)
        {
            writeln("BK-Tree構築中...");
            sw.start();
        }

        // より小さなバッチでメモリ問題を回避
        immutable size_t BATCH_SIZE = 500;

        try
        {
            for (size_t i = 0; i < total; i++)
            {
                // NULLチェックと範囲チェック
                if (i >= words.length || i >= ids.length)
                    break;

                // 単語が空でないかチェック
                if (words[i].length > 0)
                {
                    insert(words[i], ids[i]);
                }

                // 進捗表示
                if (showProgress && (i % 100 == 0 || i == total - 1))
                {
                    size_t percent = i * 100 / total;

                    if (percent > lastPercent && percent % 5 == 0)
                    {
                        lastPercent = percent;
                        auto elapsed = sw.peek.total!"msecs";
                        auto estimatedTotal = elapsed * total / max(i + 1, 1);
                        auto remaining = estimatedTotal - elapsed;

                        writef("\rBK-Tree: %d%% (%d/%d) 残り約 %d秒 ノード数:%d    ",
                            percent, i + 1, total, remaining / 1000, nodeCount);
                        stdout.flush();
                    }
                }

                // メモリ管理 - 一定間隔でGC実行
                if (i > 0 && i % BATCH_SIZE == 0)
                {
                    GC.collect();
                }
            }
        }
        catch (Exception e)
        {
            writeln("\nBK-Tree構築中に例外が発生しました: ", e.msg);
        }

        if (showProgress)
        {
            sw.stop();
            writef("\rBK-Tree: 100%% (%d/%d) 完了 (所要時間: %d秒) ノード数:%d    \n",
                total, total, sw.peek.total!"seconds", nodeCount);
        }
    }

    /**
     * 単語をBK-Treeに挿入する
     *
     * Params:
     *      word = 挿入する単語
     *      id = 単語のID
     */
    void insert(string word, size_t id)
    {
        // 引数チェック
        if (word.length == 0)
        {
            debug (verbose)
                writeln("警告: 空の単語は挿入できません");
            return;
        }

        // メモリ確保失敗に備えて try-catch で囲む
        try
        {
            // 単語およびIDを挿入
            if (root is null)
            {
                // 空のツリーならルートに設定
                root = new Node(word, id);
                nodeCount++;
                return;
            }

            // スタックを使用して非再帰的に実装（スタックオーバーフロー防止）
            Node* current = root;

            // 無限ループ防止（最大深度）
            size_t maxIterations = 100;
            size_t iterations = 0;

            while (current !is null && iterations < maxIterations)
            {
                iterations++;

                // 現在ノードとの距離を計算
                size_t dist = 0;
                try
                {
                    dist = distanceFn(word, current.word, maxDistance + 1);
                }
                catch (Exception e)
                {
                    debug (verbose)
                        writefln("距離計算中に例外: %s", e.msg);
                    return;
                }

                // 距離が0なら同じ単語なので上書き（IDのみ）
                if (dist == 0)
                {
                    current.id = id;
                    return;
                }

                // 計算された距離の子ノードを探す
                auto childPtr = dist in current.children;

                if (childPtr is null)
                {
                    // 該当する距離の子ノードが存在しなければ新規作成
                    current.children[dist] = new Node(word, id);
                    nodeCount++;
                    return;
                }

                // 子ノードに移動して検索継続
                current = *childPtr;
            }

            // 最大深度到達
            if (iterations >= maxIterations)
            {
                debug (verbose)
                    writeln("警告: BK-Tree挿入で最大深度に達しました");
            }
        }
        catch (Exception e)
        {
            debug (verbose)
                writefln("BK-Tree挿入中に例外: %s", e.msg);
        }
    }

    /**
     * BK-Treeの統計情報を表示する
     */
    void printStats()
    {
        writefln("BK-Tree統計: ノード数=%d", nodeCount);
    }

    /**
     * 検索結果を表す構造体
     */
    struct Result
    {
        size_t id; // 単語ID
        size_t dist; // 検索語との距離
    }

    /**
     * 類似単語を検索する
     *
     * 指定された単語に類似した単語をBK-Treeから検索します。
     * 三角不等式を利用して探索空間を効率的に絞り込みます。
     *
     * Params:
     *      query = 検索する単語
     *      maxDist = 許容する最大距離
     *      exhaustiveSearch = より網羅的な検索を行うかどうか（デフォルトはfalse）
     *
     * Returns:
     *      類似単語の結果配列（距離の昇順、同距離はID昇順）
     */
    Result[] search(string query, size_t maxDist, bool exhaustiveSearch = false)
    {
        Result[] results;

        if (root is null)
            return results;

        // 最大距離は設定された最大以下に制限
        if (maxDist > maxDistance)
            maxDist = maxDistance;

        // 自分自身（完全一致）を最初にチェック
        // 入力された単語と同じ単語が辞書にある場合、それが距離0で先頭に来るようにする
        bool selfAdded = false;

        // 辞書に存在するかを確認する（完全一致検索）
        // 非再帰的に検索（スタックオーバーフロー防止）
        // ノードとその距離のペアをキューに入れる
        struct QueueItem
        {
            Node* node;
        }

        DList!QueueItem queue;

        // ルートから開始
        queue.insertBack(QueueItem(root));

        while (!queue.empty)
        {
            // キューから取り出し
            auto item = queue.front;
            queue.removeFront();

            auto node = item.node;

            // 現在ノードとクエリとの距離を計算
            size_t dist = distanceFn(query, node.word, maxDist + 1);

            // 完全一致の場合は最優先で追加
            if (dist == 0 && !selfAdded)
            {
                // 距離0の結果を先頭に追加
                results = Result(node.id, 0) ~ results;
                selfAdded = true;
            }
            // それ以外の最大距離以内の結果も追加
            else if (dist <= maxDist)
            {
                results ~= Result(node.id, dist);
            }

            // 三角不等式を利用して探索範囲を絞り込み
            // exhaustiveSearchが有効な場合は探索範囲を拡大
            size_t lowerBound = dist > maxDist ? dist - maxDist : 1;
            size_t upperBound = dist + maxDist;

            if (exhaustiveSearch)
            {
                // 探索範囲を広げる（より多くのノードを訪問）
                lowerBound = dist > maxDist + 1 ? dist - maxDist - 1 : 1;
                upperBound = dist + maxDist + 1;
            }

            for (size_t d = lowerBound; d <= upperBound; d++)
            {
                if (auto childPtr = d in node.children)
                    queue.insertBack(QueueItem(*childPtr));
            }
        }

        // 距離昇順、同距離はID昇順でソート
        import std.algorithm.sorting : sort;

        // 既に距離0が追加されている場合は、それ以外の結果だけをソート
        if (selfAdded && results.length > 1)
        {
            sort!((a, b) => a.dist == b.dist ? a.id < b.id : a.dist < b.dist)(results[1 .. $]);
        }
        else
        {
            sort!((a, b) => a.dist == b.dist ? a.id < b.id : a.dist < b.dist)(results);
        }

        return results;
    }
}

// -----------------------------
// インデックスキャッシュ（ステージ1: prefix/suffix）
// -----------------------------
struct IndexCache
{
    string path; // キャッシュファイルの絶対パス

    // CSVより新しければ有効
    bool isValid(string csvPath)
    {
        if (!exists(path))
            return false;
        return timeLastModified(path) > timeLastModified(csvPath);
    }

    // バイナリ形式: magic(4byte) "LTC1", prefixCount(uint32), 各word(len16,data),
    //               suffixCount(uint32), 各word(len16,data)

    void save(RedBlackTree!string prefix, RedBlackTree!string suffix)
    {
        auto file = File(path, "wb");
        scope (exit)
            file.close();
        // magic
        file.rawWrite(cast(const(ubyte[])) "LTC1");
        // prefix
        writeValue!uint(file, cast(uint) prefix.length);
        foreach (word; prefix)
        {
            ushort len = cast(ushort) word.length;
            writeValue!ushort(file, len);
            file.rawWrite(cast(const(ubyte[])) word.representation);
        }
        // suffix
        writeValue!uint(file, cast(uint) suffix.length);
        foreach (word; suffix)
        {
            ushort len = cast(ushort) word.length;
            writeValue!ushort(file, len);
            file.rawWrite(cast(const(ubyte[])) word.representation);
        }
    }

    bool load(out RedBlackTree!string prefix, out RedBlackTree!string suffix)
    {
        if (!exists(path))
            return false;
        auto file = File(path, "rb");
        scope (exit)
            file.close();
        ubyte[4] magic;
        file.rawRead(magic[]);
        if (magic != cast(ubyte[4]) "LTC1")
            return false;
        uint preCount;
        readValue!uint(file, preCount);
        prefix = new RedBlackTree!string;
        foreach (i; 0 .. preCount)
        {
            ushort len;
            readValue!ushort(file, len);
            char[] buf;
            buf.length = len;
            file.rawRead(cast(ubyte[]) buf);
            prefix.insert(cast(string) buf.idup);
        }
        uint sufCount;
        readValue!uint(file, sufCount);
        suffix = new RedBlackTree!string;
        foreach (i; 0 .. sufCount)
        {
            ushort len;
            readValue!ushort(file, len);
            char[] buf;
            buf.length = len;
            file.rawRead(cast(ubyte[]) buf);
            suffix.insert(cast(string) buf.idup);
        }
        return true;
    }

    // ---------- 拡張版: prefix/suffix + gramIndex + lengthIndex ----------
    void saveFull(
        RedBlackTree!string prefix,
        RedBlackTree!string suffix,
        GramIndexType[string] gram,
        bool[size_t][size_t] lenIdx)
    {
        auto file = File(path, "wb");
        scope (exit)
            file.close();
        file.rawWrite(cast(ubyte[]) "LTC2"); // 新しいmagic

        // prefix / suffix 既存ロジック
        writeValue!uint(file, cast(uint) prefix.length);
        foreach (w; prefix)
        {
            ushort l = cast(ushort) w.length;
            writeValue!ushort(file, l);
            file.rawWrite(cast(const(ubyte[])) w.representation);
        }
        writeValue!uint(file, cast(uint) suffix.length);
        foreach (w; suffix)
        {
            ushort l = cast(ushort) w.length;
            writeValue!ushort(file, l);
            file.rawWrite(cast(const(ubyte[])) w.representation);
        }

        // gramIndex
        writeValue!uint(file, cast(uint) gram.length);
        foreach (g, idsSet; gram)
        {
            ushort l = cast(ushort) g.length;
            writeValue!ushort(file, l);
            file.rawWrite(cast(const(ubyte[])) g.representation);

            auto ids = idsSet.keys();
            writeValue!uint(file, cast(uint) ids.length);
            foreach (id; ids)
                writeValue!uint(file, cast(uint) id);
        }

        // lengthIndex
        writeValue!uint(file, cast(uint) lenIdx.length);
        foreach (len, idMap; lenIdx)
        {
            writeValue!ushort(file, cast(ushort) len);
            auto ids = idMap.keys;
            writeValue!uint(file, cast(uint) ids.length);
            foreach (id; ids)
                writeValue!uint(file, cast(uint) id);
        }
    }

    bool loadFull(out RedBlackTree!string prefix,
        out RedBlackTree!string suffix,
        ref GramIndexType[string] gram,
        ref bool[size_t][size_t] lenIdx)
    {
        if (!exists(path))
            return false;
        auto file = File(path, "rb");
        scope (exit)
            file.close();
        ubyte[4] mag;
        file.rawRead(mag[]);
        if (mag != cast(ubyte[4]) "LTC2")
            return false;

        uint preCnt;
        readValue!uint(file, preCnt);
        prefix = new RedBlackTree!string;
        foreach (i; 0 .. preCnt)
        {
            ushort l;
            readValue!ushort(file, l);
            char[] buf;
            buf.length = l;
            file.rawRead(cast(ubyte[]) buf);
            prefix.insert(cast(string) buf.idup);
        }

        uint sufCnt;
        readValue!uint(file, sufCnt);
        suffix = new RedBlackTree!string;
        foreach (i; 0 .. sufCnt)
        {
            ushort l;
            readValue!ushort(file, l);
            char[] buf;
            buf.length = l;
            file.rawRead(cast(ubyte[]) buf);
            suffix.insert(cast(string) buf.idup);
        }

        uint gramCnt;
        readValue!uint(file, gramCnt);
        gram.clear();
        foreach (i; 0 .. gramCnt)
        {
            ushort l;
            readValue!ushort(file, l);
            char[] buf;
            buf.length = l;
            file.rawRead(cast(ubyte[]) buf);
            string g = cast(string) buf.idup;
            uint idN;
            readValue!uint(file, idN);
            GramIndexType set;
            set.initialize(idN + 1);
            foreach (j; 0 .. idN)
            {
                uint id;
                readValue!uint(file, id);
                set.add(id);
            }
            gram[g] = set;
        }

        uint lenCnt;
        readValue!uint(file, lenCnt);
        lenIdx.clear();
        foreach (i; 0 .. lenCnt)
        {
            ushort ln;
            readValue!ushort(file, ln);
            uint idN;
            readValue!uint(file, idN);
            if (ln !in lenIdx)
                lenIdx[ln] = null;
            foreach (j; 0 .. idN)
            {
                uint id;
                readValue!uint(file, id);
                lenIdx[ln][id] = true;
            }
        }

        return true;
    }
}

// バイナリI/Oヘルパー
private void writeValue(T)(File f, T v)
{
    ubyte[T.sizeof] tmp;
    import core.stdc.string : memcpy;

    memcpy(tmp.ptr, &v, T.sizeof);
    f.rawWrite(tmp[]);
}

private void readValue(T)(File f, ref T v)
{
    ubyte[T.sizeof] tmp;
    f.rawRead(tmp[]);
    import core.stdc.string : memcpy;

    memcpy(&v, tmp.ptr, T.sizeof);
}
