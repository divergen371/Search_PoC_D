module utils.memory_utils;

import std.stdio;
import core.memory : GC;

/**
 * メモリ・パフォーマンス監視に関するユーティリティ関数群
 * 
 * ガベージコレクターの統計情報、メモリ使用量の監視、
 * パフォーマンス測定などの機能を提供します。
 */

/**
 * メモリ使用状況を報告する関数
 *
 * ガベージコレクターの統計情報を取得し、現在のメモリ使用量を
 * 分かりやすい形式で表示します。処理の各段階でのメモリ使用量を
 * 追跡するのに便利です。
 *
 * Params:
 *      phase = 処理段階を示す文字列（レポートに含まれる）
 */
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
 * GC統計情報を報告
 *
 * ガベージコレクターの詳細な統計情報を表示します。
 * 総容量、使用中メモリ、空きメモリ、コレクション回数などの
 * 情報をMB単位で分かりやすく表示します。
 */
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
 * メモリ使用統計情報を表す構造体
 */
struct MemoryStatistics
{
    ulong totalSize; /// 総メモリサイズ（バイト）
    ulong usedSize; /// 使用中メモリサイズ（バイト）
    ulong freeSize; /// 空きメモリサイズ（バイト）
    size_t collectionsTotal; /// 総コレクション回数
    size_t collectionsFullTotal; /// フルコレクション回数
    ulong allocationStatsTypeName; /// 割り当て統計

    /**
     * 統計情報を表示する
     */
    void display() const
    {
        writeln("=== メモリ統計情報 ===");
        writefln("総容量: %.2f MB", totalSize / (1024.0 * 1024.0));
        writefln("使用中: %.2f MB (%.1f%%)",
            usedSize / (1024.0 * 1024.0),
            (usedSize * 100.0) / totalSize);
        writefln("空き: %.2f MB (%.1f%%)",
            freeSize / (1024.0 * 1024.0),
            (freeSize * 100.0) / totalSize);
        writefln("コレクション回数: %d", collectionsTotal);
        writefln("フルコレクション回数: %d", collectionsFullTotal);
        writeln("==================");
    }

    /**
     * 使用率を取得する（パーセント）
     */
    double getUsagePercentage() const
    {
        return totalSize > 0 ? (usedSize * 100.0) / totalSize : 0.0;
    }
}

/**
 * 現在のメモリ統計情報を取得する
 *
 * Returns:
 *      メモリ統計情報
 */
MemoryStatistics getMemoryStatistics()
{
    GC.collect(); // 正確な統計のためにGCを実行

    auto stats = GC.stats();
    auto profileStats = GC.profileStats();

    MemoryStatistics memStats;
    memStats.totalSize = stats.usedSize + stats.freeSize;
    memStats.usedSize = stats.usedSize;
    memStats.freeSize = stats.freeSize;
    memStats.collectionsTotal = profileStats.numCollections;
    memStats.collectionsFullTotal = profileStats.totalCollectionTime.total!"msecs";

    return memStats;
}

/**
 * メモリ使用量の監視クラス
 * 
 * 定期的にメモリ使用量を監視し、閾値を超えた場合に警告を表示します。
 */
class MemoryMonitor
{
    private double warningThreshold; /// 警告閾値（パーセント）
    private double criticalThreshold; /// 危険閾値（パーセント）
    private bool lastWasWarning; /// 前回警告を発したか
    private bool lastWasCritical; /// 前回危険警告を発したか

    /**
     * コンストラクタ
     * 
     * Params:
     *      warningThreshold = 警告閾値（デフォルト: 80%）
     *      criticalThreshold = 危険閾値（デフォルト: 95%）
     */
    this(double warningThreshold = 80.0, double criticalThreshold = 95.0)
    {
        this.warningThreshold = warningThreshold;
        this.criticalThreshold = criticalThreshold;
        this.lastWasWarning = false;
        this.lastWasCritical = false;
    }

    /**
     * メモリ使用量をチェックし、必要に応じて警告を表示する
     */
    void checkMemoryUsage()
    {
        auto stats = getMemoryStatistics();
        double usage = stats.getUsagePercentage();

        if (usage >= criticalThreshold && !lastWasCritical)
        {
            writefln("⚠️ 危険: メモリ使用量が%.1f%%に達しました！", usage);
            lastWasCritical = true;
            lastWasWarning = true;
        }
        else if (usage >= warningThreshold && !lastWasWarning)
        {
            writefln("⚠️ 警告: メモリ使用量が%.1f%%に達しました", usage);
            lastWasWarning = true;
            lastWasCritical = false;
        }
        else if (usage < warningThreshold)
        {
            // 使用量が閾値を下回った場合、フラグをリセット
            lastWasWarning = false;
            lastWasCritical = false;
        }
    }

    /**
     * 強制的にガベージコレクションを実行する
     */
    void forceGC()
    {
        writeln("ガベージコレクションを強制実行中...");
        auto beforeStats = getMemoryStatistics();
        GC.collect();
        auto afterStats = getMemoryStatistics();

        auto freedMemory = beforeStats.usedSize - afterStats.usedSize;
        writefln("%.2f MB のメモリが解放されました", freedMemory / (1024.0 * 1024.0));
    }
}

/**
 * メモリ使用量のベンチマーク機能
 */
struct MemoryBenchmark
{
    private MemoryStatistics startStats;
    private string benchmarkName;

    /**
     * ベンチマークを開始する
     * 
     * Params:
     *      name = ベンチマーク名
     */
    void start(string name)
    {
        benchmarkName = name;
        GC.collect(); // 開始前にGCを実行
        startStats = getMemoryStatistics();
        writefln("メモリベンチマーク開始: %s", name);
    }

    /**
     * ベンチマークを終了し、結果を表示する
     */
    void finish()
    {
        GC.collect(); // 終了前にGCを実行
        auto endStats = getMemoryStatistics();

        auto memoryDiff = cast(long) endStats.usedSize - cast(long) startStats.usedSize;
        auto gcDiff = endStats.collectionsTotal - startStats.collectionsTotal;

        writefln("メモリベンチマーク終了: %s", benchmarkName);
        writefln("  メモリ変化: %+.2f MB", memoryDiff / (1024.0 * 1024.0));
        writefln("  GC実行回数: %d回", gcDiff);
        writefln("  最終使用率: %.1f%%", endStats.getUsagePercentage());
    }
}

/**
 * メモリプールの統計情報
 */
struct MemoryPoolStats
{
    size_t poolSize; /// プールサイズ
    size_t usedEntries; /// 使用済みエントリ数
    size_t freeEntries; /// 空きエントリ数
    double utilizationRate; /// 使用率

    /**
     * 統計情報を表示する
     */
    void display() const
    {
        writeln("=== メモリプール統計 ===");
        writefln("プールサイズ: %d", poolSize);
        writefln("使用済み: %d", usedEntries);
        writefln("空き: %d", freeEntries);
        writefln("使用率: %.2f%%", utilizationRate);
        writeln("====================");
    }
}

/**
 * システム全体のメモリ情報を取得する（プラットフォーム依存）
 */
struct SystemMemoryInfo
{
    ulong totalPhysicalMemory; /// 総物理メモリ
    ulong availablePhysicalMemory; /// 利用可能物理メモリ
    ulong totalVirtualMemory; /// 総仮想メモリ
    ulong availableVirtualMemory; /// 利用可能仮想メモリ

    /**
     * システムメモリ情報を表示する
     */
    void display() const
    {
        writeln("=== システムメモリ情報 ===");
        writefln("総物理メモリ: %.2f GB", totalPhysicalMemory / (1024.0 * 1024.0 * 1024.0));
        writefln("利用可能物理メモリ: %.2f GB", availablePhysicalMemory / (
                1024.0 * 1024.0 * 1024.0));
        writefln("総仮想メモリ: %.2f GB", totalVirtualMemory / (1024.0 * 1024.0 * 1024.0));
        writefln("利用可能仮想メモリ: %.2f GB", availableVirtualMemory / (
                1024.0 * 1024.0 * 1024.0));
        writeln("========================");
    }
}

/**
 * システムメモリ情報を取得する
 * 
 * Returns:
 *      システムメモリ情報（プラットフォーム依存）
 */
SystemMemoryInfo getSystemMemoryInfo()
{
    SystemMemoryInfo info;

    version (Windows)
    {
        // Windows specific implementation would go here
        // For now, return dummy values
        info.totalPhysicalMemory = 8UL * 1024 * 1024 * 1024; // 8GB dummy
        info.availablePhysicalMemory = 4UL * 1024 * 1024 * 1024; // 4GB dummy
        info.totalVirtualMemory = 16UL * 1024 * 1024 * 1024; // 16GB dummy
        info.availableVirtualMemory = 8UL * 1024 * 1024 * 1024; // 8GB dummy
    }
    else version (Posix)
    {
        // Linux/Unix specific implementation would go here
        import std.process : executeShell;
        import std.conv : to;
        import std.string : strip;

        try
        {
            // 簡易実装（/proc/meminfoを読む）
            auto result = executeShell("cat /proc/meminfo | grep MemTotal | awk '{print $2}'");
            if (result.status == 0)
            {
                auto totalKB = result.output.strip().to!ulong;
                info.totalPhysicalMemory = totalKB * 1024;
            }

            result = executeShell("cat /proc/meminfo | grep MemAvailable | awk '{print $2}'");
            if (result.status == 0)
            {
                auto availableKB = result.output.strip().to!ulong;
                info.availablePhysicalMemory = availableKB * 1024;
            }
        }
        catch (Exception e)
        {
            // エラーの場合はダミー値を設定
            info.totalPhysicalMemory = 8UL * 1024 * 1024 * 1024;
            info.availablePhysicalMemory = 4UL * 1024 * 1024 * 1024;
        }

        // 仮想メモリ情報（簡易版）
        info.totalVirtualMemory = info.totalPhysicalMemory * 2;
        info.availableVirtualMemory = info.availablePhysicalMemory * 2;
    }
    else
    {
        // その他のプラットフォーム用ダミー値
        info.totalPhysicalMemory = 8UL * 1024 * 1024 * 1024;
        info.availablePhysicalMemory = 4UL * 1024 * 1024 * 1024;
        info.totalVirtualMemory = 16UL * 1024 * 1024 * 1024;
        info.availableVirtualMemory = 8UL * 1024 * 1024 * 1024;
    }

    return info;
}
