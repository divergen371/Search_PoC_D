module utils.progress;

import std.stdio;
import std.datetime.stopwatch : StopWatch;

/**
 * 進捗状況の追跡と表示を行う構造体
 *
 * 長時間かかる処理の進捗状況を追跡し、コンソールに表示するための機能を提供します。
 * 残り時間の推定や完了のレポート機能も含みます。
 */
struct ProgressTracker
{
    private size_t total;
    private size_t current;
    private size_t lastPercent;
    private StopWatch sw;
    private string taskName;
    private size_t updateInterval;

    /**
     * 進捗トラッカーを初期化する
     *
     * Params:
     *      total = 処理する合計アイテム数
     *      taskName = タスク名（デフォルト: "処理"）
     *      updateInterval = 更新間隔（パーセント、デフォルト: 5）
     */
    void initialize(size_t total, string taskName = "処理", size_t updateInterval = 5)
    {
        this.total = total;
        this.current = 0;
        this.lastPercent = 0;
        this.taskName = taskName;
        this.updateInterval = updateInterval;
        sw.reset();
        sw.start();
    }

    /**
     * 進捗を1つインクリメントし、必要に応じて進捗状況を表示する
     *
     * updateInterval単位で進捗状況がコンソールに表示されます。
     * 残り時間の推定も行います。
     */
    void increment()
    {
        current++;
        size_t percent = (total > 0) ? (current * 100 / total) : 100;

        if (percent > lastPercent && percent % updateInterval == 0)
        {
            lastPercent = percent;
            displayProgress(percent);
        }
    }

    /**
     * 指定した数だけ進捗を進める
     *
     * Params:
     *      count = 進める数
     */
    void incrementBy(size_t count)
    {
        size_t oldCurrent = current;
        current += count;
        if (current > total)
            current = total;

        size_t oldPercent = (total > 0) ? (oldCurrent * 100 / total) : 100;
        size_t newPercent = (total > 0) ? (current * 100 / total) : 100;

        // 更新間隔を跨いだ場合は表示
        if ((newPercent / updateInterval) > (oldPercent / updateInterval))
        {
            lastPercent = (newPercent / updateInterval) * updateInterval;
            displayProgress(newPercent);
        }
    }

    /**
     * 現在の進捗を手動で設定する
     *
     * Params:
     *      value = 新しい進捗値
     */
    void setCurrent(size_t value)
    {
        size_t oldCurrent = current;
        current = (value <= total) ? value : total;

        size_t oldPercent = (total > 0) ? (oldCurrent * 100 / total) : 100;
        size_t newPercent = (total > 0) ? (current * 100 / total) : 100;

        if ((newPercent / updateInterval) > (oldPercent / updateInterval))
        {
            lastPercent = (newPercent / updateInterval) * updateInterval;
            displayProgress(newPercent);
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
        current = total;
        writef("\r%s: 100%% (%d/%d) 完了 (所要時間: %d秒)    \n",
            taskName, total, total, sw.peek.total!"seconds");
    }

    /**
     * 進捗をリセットする
     */
    void reset()
    {
        current = 0;
        lastPercent = 0;
        sw.reset();
        sw.start();
    }

    /**
     * 現在の進捗パーセンテージを取得する
     *
     * Returns:
     *      進捗パーセンテージ（0-100）
     */
    size_t getPercentage() const
    {
        return (total > 0) ? (current * 100 / total) : 100;
    }

    /**
     * 経過時間を取得する（ミリ秒）
     *
     * Returns:
     *      経過時間（ミリ秒）
     */
    long getElapsedTime() const
    {
        return sw.peek.total!"msecs";
    }

    /**
     * 推定残り時間を取得する（ミリ秒）
     *
     * Returns:
     *      推定残り時間（ミリ秒）
     */
    long getEstimatedRemainingTime() const
    {
        if (current == 0)
            return 0;

        auto elapsed = sw.peek.total!"msecs";
        auto estimatedTotal = elapsed * total / current;
        return estimatedTotal - elapsed;
    }

    /**
     * 処理速度を取得する（アイテム/秒）
     *
     * Returns:
     *      処理速度
     */
    double getProcessingRate() const
    {
        auto elapsedSecs = sw.peek.total!"seconds";
        return (elapsedSecs > 0) ? (cast(double) current / elapsedSecs) : 0.0;
    }

    private:

    /**
     * 進捗状況を表示する
     *
     * Params:
     *      percent = 進捗パーセンテージ
     */
    void displayProgress(size_t percent)
    {
        // 残り時間の推定
        auto elapsed = sw.peek.total!"msecs";
        auto estimated = getEstimatedRemainingTime();
        auto rate = getProcessingRate();

        writef("\r%s: %d%% (%d/%d) 残り約%d秒 (%.1f件/秒)    ",
            taskName, percent, current, total, estimated / 1000, rate);
        stdout.flush();
    }
}

/**
 * シンプルな進捗バー表示クラス
 */
struct SimpleProgressBar
{
    private size_t width;
    private dchar fillChar;
    private dchar emptyChar;

    /**
     * コンストラクタ
     *
     * Params:
     *      width = プログレスバーの幅（文字数）
     *      fillChar = 完了部分の文字
     *      emptyChar = 未完了部分の文字
     */
    void initialize(size_t width = 50, dchar fillChar = '█', dchar emptyChar = '░')
    {
        this.width = width;
        this.fillChar = fillChar;
        this.emptyChar = emptyChar;
    }

    /**
     * 進捗バーを表示する
     *
     * Params:
     *      percentage = 進捗パーセンテージ（0-100）
     *      label = ラベル文字列
     */
    void display(size_t percentage, string label = "")
    {
        if (percentage > 100)
            percentage = 100;

        size_t filled = (percentage * width) / 100;
        size_t empty = width - filled;

        write("\r");
        if (label.length > 0)
            writef("%s: ", label);

        write("[");
        foreach (i; 0 .. filled)
            write(fillChar);
        foreach (i; 0 .. empty)
            write(emptyChar);
        writef("] %d%%", percentage);

        stdout.flush();
    }

    /**
     * プログレスバーを完了状態で表示して改行する
     */
    void finish(string label = "完了")
    {
        display(100, label);
        writeln();
    }
}

/**
 * 複数の進捗を管理するマネージャー
 */
class ProgressManager
{
    private ProgressTracker[string] trackers;
    private string activeTracker;

    /**
     * 新しい進捗トラッカーを追加する
     *
     * Params:
     *      name = トラッカー名
     *      total = 総アイテム数
     *      taskName = タスク名
     */
    void addTracker(string name, size_t total, string taskName = "処理")
    {
        trackers[name].initialize(total, taskName);
    }

    /**
     * アクティブなトラッカーを設定する
     *
     * Params:
     *      name = トラッカー名
     */
    void setActive(string name)
    {
        if (name in trackers)
            activeTracker = name;
    }

    /**
     * アクティブなトラッカーの進捗を進める
     */
    void increment()
    {
        if (activeTracker in trackers)
            trackers[activeTracker].increment();
    }

    /**
     * 指定したトラッカーの進捗を進める
     *
     * Params:
     *      name = トラッカー名
     */
    void increment(string name)
    {
        if (name in trackers)
            trackers[name].increment();
    }

    /**
     * アクティブなトラッカーを完了する
     */
    void finish()
    {
        if (activeTracker in trackers)
            trackers[activeTracker].finish();
    }

    /**
     * 指定したトラッカーを完了する
     *
     * Params:
     *      name = トラッカー名
     */
    void finish(string name)
    {
        if (name in trackers)
            trackers[name].finish();
    }

    /**
     * 全体の進捗状況を表示する
     */
    void displaySummary()
    {
        writeln("\n=== 進捗サマリー ===");
        foreach (name, tracker; trackers)
        {
            writefln("%s: %d%% (%d秒)", name, tracker.getPercentage(),
                tracker.getElapsedTime() / 1000);
        }
        writeln("=================");
    }
} 

 