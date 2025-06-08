module algorithms.bktree;

import std.stdio;
import std.algorithm : max;
import std.datetime.stopwatch : StopWatch;
import std.container.dlist : DList;
import core.memory : GC;

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
        string word; /// 単語
        size_t id; /// 単語ID
        Node*[size_t] children; /// 距離ごとの子ノード

        /**
         * ノードの文字列表現を取得する
         */
        string toString() const
        {
            import std.format : format;

            return format("Node(id: %d, word: \"%s\", children: %d)",
                id, word, children.length);
        }
    }

    Node* root; /// ルートノード

    // 距離関数へのポインタ型
    alias DistanceFn = size_t function(string, string, size_t);

    DistanceFn distanceFn; /// 使用する距離関数
    size_t maxDistance; /// 最大距離
    size_t nodeCount; /// 統計情報：ノード数
    size_t maxDepth; /// 統計情報：最大深度
    size_t totalInsertions; /// 統計情報：総挿入回数

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
        this.maxDepth = 0;
        this.totalInsertions = 0;
    }

    /**
     * 複数の単語をバッチで挿入する
     *
     * メモリ効率と安全性を向上させるため、複数の単語を一度に挿入します。
     * 大量のデータを処理する際の進捗表示やメモリ管理も含まれています。
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

        totalInsertions++;

        // メモリ確保失敗に備えて try-catch で囲む
        try
        {
            // 単語およびIDを挿入
            if (root is null)
            {
                // 空のツリーならルートに設定
                root = new Node(word, id);
                nodeCount++;
                maxDepth = 1;
                return;
            }

            // スタックを使用して非再帰的に実装（スタックオーバーフロー防止）
            Node* current = root;
            size_t currentDepth = 1;

            while (current !is null)
            {
                // 現在ノードとの距離を計算
                size_t lim = max(word.length, current.word.length) + 1;
                size_t dist = distanceFn(word, current.word, lim);

                if (dist == 0)
                {
                    // 同じ単語が既に存在する場合はIDを更新
                    current.id = id;
                    return;
                }

                auto childPtr = dist in current.children;
                if (childPtr is null)
                {
                    // 新しい子ノードを作成
                    current.children[dist] = new Node(word, id);
                    nodeCount++;

                    // 最大深度を更新
                    if (currentDepth + 1 > maxDepth)
                        maxDepth = currentDepth + 1;

                    return;
                }
                current = *childPtr;
                currentDepth++;
            }

            if (current is null)
            {
                writeln("警告: BK-Tree挿入で予期しないエラー: ", word);
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
        writefln("BK-Tree統計:");
        writefln("  ノード数: %d", nodeCount);
        writefln("  最大深度: %d", maxDepth);
        writefln("  総挿入回数: %d", totalInsertions);
        writefln("  平均分岐数: %.2f", getAverageBranchingFactor());
    }

    /**
     * 検索結果を表す構造体
     */
    struct Result
    {
        size_t id; /// 単語ID
        size_t dist; /// 検索語との距離

        /**
         * 結果の比較用（距離、IDの順でソート）
         */
        int opCmp(const Result other) const
        {
            if (dist != other.dist)
                return dist < other.dist ? -1 : 1;
            if (id != other.id)
                return id < other.id ? -1 : 1;
            return 0;
        }

        /**
         * 文字列表現を取得する
         */
        string toString() const
        {
            import std.format : format;

            return format("Result(id: %d, distance: %d)", id, dist);
        }
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

        // 検索統計
        size_t nodesVisited = 0;
        size_t distanceCalculations = 0;

        // 自分自身（完全一致）を最初にチェック
        bool selfAdded = false;

        // 非再帰的に検索（スタックオーバーフロー防止）
        struct QueueItem
        {
            Node* node;
            size_t depth;
        }

        DList!QueueItem queue;

        // ルートから開始
        queue.insertBack(QueueItem(root, 0));

        while (!queue.empty)
        {
            // キューから取り出し
            auto item = queue.front;
            queue.removeFront();

            auto node = item.node;
            nodesVisited++;

            // 現在ノードとクエリとの距離を計算
            size_t limit = (query.length >= node.word.length ? query.length : node.word.length) + 1;
            size_t dist = distanceFn(query, node.word, limit);
            distanceCalculations++;

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
                    queue.insertBack(QueueItem(*childPtr, item.depth + 1));
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

        debug (verbose)
        {
            writefln("検索統計: 訪問ノード数=%d, 距離計算回数=%d", nodesVisited, distanceCalculations);
        }

        return results;
    }

    /**
     * ツリーをクリアする
     */
    void clear()
    {
        root = null;
        nodeCount = 0;
        maxDepth = 0;
        totalInsertions = 0;
    }

    /**
     * ツリーが空かどうかを確認する
     *
     * Returns:
     *      空の場合はtrue
     */
    bool empty() const
    {
        return root is null;
    }

    /**
     * ノード数を取得する
     *
     * Returns:
     *      ノード数
     */
    size_t size() const
    {
        return nodeCount;
    }

    /**
     * 最大深度を取得する
     *
     * Returns:
     *      最大深度
     */
    size_t depth() const
    {
        return maxDepth;
    }

    /**
     * 平均分岐数を計算する
     *
     * Returns:
     *      平均分岐数
     */
    double getAverageBranchingFactor() const
    {
        if (nodeCount <= 1)
            return 0.0;

        size_t totalChildren = getTotalChildrenCount(root);
        return cast(double) totalChildren / (nodeCount - 1); // リーフノードを除く
    }

    /**
     * メモリ使用量の推定を取得する（バイト）
     *
     * Returns:
     *      推定メモリ使用量
     */
    size_t getEstimatedMemoryUsage() const
    {
        // 各ノードのおおよそのサイズを計算
        size_t nodeSize = Node.sizeof + 50; // 文字列のおおよそのサイズ
        return nodeCount * nodeSize;
    }

private:

    /**
     * 指定したノード以下の総子ノード数を再帰的にカウントする
     */
    size_t getTotalChildrenCount(const Node* node) const
    {
        if (node is null)
            return 0;

        size_t count = node.children.length;
        foreach (child; node.children.values)
        {
            count += getTotalChildrenCount(child);
        }
        return count;
    }
}

/**
 * BK-Tree用の統計情報を表す構造体
 */
struct BKTreeStatistics
{
    size_t nodeCount; /// ノード数
    size_t maxDepth; /// 最大深度
    size_t totalInsertions; /// 総挿入回数
    double averageBranchingFactor; /// 平均分岐数
    size_t estimatedMemoryUsage; /// 推定メモリ使用量（バイト）

    /**
     * 統計情報を表示する
     */
    void display() const
    {
        writeln("=== BK-Tree統計情報 ===");
        writefln("ノード数: %d", nodeCount);
        writefln("最大深度: %d", maxDepth);
        writefln("総挿入回数: %d", totalInsertions);
        writefln("平均分岐数: %.2f", averageBranchingFactor);
        writefln("推定メモリ使用量: %.2f MB", estimatedMemoryUsage / (1024.0 * 1024.0));
        writeln("====================");
    }
}
