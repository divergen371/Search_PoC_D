module algorithms.distance;

import std.algorithm : min, max;
import std.math : abs;

/**
 * 文字列間の距離計算アルゴリズム群
 * 
 * 様々な編集距離やその他の文字列類似度メトリックを提供します。
 * 特に高速化と早期打ち切りに重点を置いた実装です。
 */

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
    size_t m = s.length;
    size_t n = t.length;

    // デバッグ用表示
    debug (verbose)
    {
        import std.stdio : writefln, writeln;
        writefln("距離計算: s='%s'(%d) と t='%s'(%d), maxDist=%d", s, m, t, n, maxDist);
    }

    // 自分自身との比較は常に距離0（最初にチェック）
    if (s == t)
    {
        debug (verbose)
        {
            import std.stdio : writeln;
            writeln("  同一文字列: 結果=0");
        }
        return 0;
    }

    // 長さの差が最大距離を超えるなら早期リターン
    // 条件を統一：文字列長に関係なく同じ条件を適用
    if (abs(cast(int) m - cast(int) n) > maxDist)
    {
        debug (verbose)
        {
            import std.stdio : writeln;
            writeln("  早期リターン: 長さの差が制限を超えています");
        }
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
    {
        import std.stdio : writefln;
        writefln("  計算結果: 距離=%d", prev[n]);
    }
    return prev[n];
}

/**
 * 標準的なLevenshtein距離を計算する（制限なし）
 *
 * 2つの文字列間の編集距離を計算します。挿入、削除、置換の3種類の操作をカウントします。
 *
 * Params:
 *      s = 1つ目の文字列
 *      t = 2つ目の文字列
 *
 * Returns:
 *      2つの文字列間のLevenshtein距離
 */
size_t levenshteinDistance(string s, string t)
{
    size_t m = s.length;
    size_t n = t.length;

    if (m == 0) return n;
    if (n == 0) return m;

    // 2行のDPテーブルのみを使用してメモリを節約
    size_t[] prev = new size_t[n + 1];
    size_t[] curr = new size_t[n + 1];

    // 初期化
    foreach (j; 0 .. n + 1)
        prev[j] = j;

    foreach (i; 1 .. m + 1)
    {
        curr[0] = i;
        foreach (j; 1 .. n + 1)
        {
            size_t cost = (s[i - 1] == t[j - 1]) ? 0 : 1;
            curr[j] = min(
                prev[j] + 1,        // 削除
                curr[j - 1] + 1,    // 挿入
                prev[j - 1] + cost  // 置換
            );
        }
        prev[] = curr[];
    }

    return prev[n];
}

/**
 * 制限付きLevenshtein距離を計算する
 *
 * Params:
 *      s = 1つ目の文字列
 *      t = 2つ目の文字列
 *      maxDist = 計算を打ち切る最大距離
 *
 * Returns:
 *      2つの文字列間のLevenshtein距離。maxDistを超える場合はmaxDist+1
 */
size_t levenshteinDistanceLimited(string s, string t, size_t maxDist)
{
    size_t m = s.length;
    size_t n = t.length;

    // 自分自身との比較は常に距離0
    if (s == t) return 0;

    // 長さの差が最大距離を超えるなら早期リターン
    if (abs(cast(int) m - cast(int) n) > maxDist)
        return maxDist + 1;

    // 空文字列の処理
    if (m == 0) return n <= maxDist ? n : maxDist + 1;
    if (n == 0) return m <= maxDist ? m : maxDist + 1;

    size_t[] prev = new size_t[n + 1];
    size_t[] curr = new size_t[n + 1];

    foreach (j; 0 .. n + 1)
        prev[j] = j;

    foreach (i; 1 .. m + 1)
    {
        curr[0] = i;
        size_t minInRow = maxDist + 1;
        
        foreach (j; 1 .. n + 1)
        {
            size_t cost = (s[i - 1] == t[j - 1]) ? 0 : 1;
            curr[j] = min(
                prev[j] + 1,        // 削除
                curr[j - 1] + 1,    // 挿入
                prev[j - 1] + cost  // 置換
            );
            
            if (curr[j] < minInRow)
                minInRow = curr[j];
        }
        
        // 行の最小値が制限を超えた場合は早期終了
        if (minInRow > maxDist)
            return maxDist + 1;
            
        prev[] = curr[];
    }

    return prev[n];
}

/**
 * Hamming距離を計算する
 *
 * 同じ長さの2つの文字列間で、対応する位置の文字が異なる箇所の数を数えます。
 *
 * Params:
 *      s = 1つ目の文字列
 *      t = 2つ目の文字列
 *
 * Returns:
 *      Hamming距離。文字列の長さが異なる場合は-1
 */
int hammingDistance(string s, string t)
{
    if (s.length != t.length)
        return -1;

    int distance = 0;
    foreach (i; 0 .. s.length)
    {
        if (s[i] != t[i])
            distance++;
    }

    return distance;
}

/**
 * 最長共通部分列（LCS）の長さを計算する
 *
 * Params:
 *      s = 1つ目の文字列
 *      t = 2つ目の文字列
 *
 * Returns:
 *      最長共通部分列の長さ
 */
size_t longestCommonSubsequence(string s, string t)
{
    size_t m = s.length;
    size_t n = t.length;

    if (m == 0 || n == 0) return 0;

    // メモリ効率のため2行のみ使用
    size_t[] prev = new size_t[n + 1];
    size_t[] curr = new size_t[n + 1];

    foreach (i; 1 .. m + 1)
    {
        foreach (j; 1 .. n + 1)
        {
            if (s[i - 1] == t[j - 1])
                curr[j] = prev[j - 1] + 1;
            else
                curr[j] = max(prev[j], curr[j - 1]);
        }
        prev[] = curr[];
    }

    return prev[n];
}

/**
 * 最長共通部分文字列の長さを計算する
 *
 * Params:
 *      s = 1つ目の文字列
 *      t = 2つ目の文字列
 *
 * Returns:
 *      最長共通部分文字列の長さ
 */
size_t longestCommonSubstring(string s, string t)
{
    size_t m = s.length;
    size_t n = t.length;

    if (m == 0 || n == 0) return 0;

    size_t[][] dp = new size_t[][](m + 1, n + 1);
    size_t maxLength = 0;

    foreach (i; 1 .. m + 1)
    {
        foreach (j; 1 .. n + 1)
        {
            if (s[i - 1] == t[j - 1])
            {
                dp[i][j] = dp[i - 1][j - 1] + 1;
                if (dp[i][j] > maxLength)
                    maxLength = dp[i][j];
            }
            else
            {
                dp[i][j] = 0;
            }
        }
    }

    return maxLength;
}

/**
 * Jaro距離を計算する
 *
 * Params:
 *      s = 1つ目の文字列
 *      t = 2つ目の文字列
 *
 * Returns:
 *      Jaro距離（0.0〜1.0、1.0が完全一致）
 */
double jaroDistance(string s, string t)
{
    if (s.length == 0 && t.length == 0) return 1.0;
    if (s.length == 0 || t.length == 0) return 0.0;
    if (s == t) return 1.0;

    size_t matchWindow = max(s.length, t.length) / 2;
    if (matchWindow > 0) matchWindow--;

    bool[] sMatches = new bool[s.length];
    bool[] tMatches = new bool[t.length];

    size_t matches = 0;
    size_t transpositions = 0;

    // マッチの検出
    foreach (i; 0 .. s.length)
    {
        size_t start = (i >= matchWindow) ? i - matchWindow : 0;
        size_t end = min(i + matchWindow + 1, t.length);

        foreach (j; start .. end)
        {
            if (tMatches[j] || s[i] != t[j]) continue;
            
            sMatches[i] = true;
            tMatches[j] = true;
            matches++;
            break;
        }
    }

    if (matches == 0) return 0.0;

    // 転置の検出
    size_t k = 0;
    foreach (i; 0 .. s.length)
    {
        if (!sMatches[i]) continue;
        
        while (!tMatches[k]) k++;
        
        if (s[i] != t[k]) transpositions++;
        k++;
    }

    return (cast(double)matches / s.length + 
            cast(double)matches / t.length + 
            cast(double)(matches - transpositions / 2) / matches) / 3.0;
}

/**
 * Jaro-Winkler距離を計算する
 *
 * Params:
 *      s = 1つ目の文字列
 *      t = 2つ目の文字列
 *      threshold = Jaroスコアの閾値（デフォルト: 0.7）
 *
 * Returns:
 *      Jaro-Winkler距離（0.0〜1.0、1.0が完全一致）
 */
double jaroWinklerDistance(string s, string t, double threshold = 0.7)
{
    double jaroScore = jaroDistance(s, t);
    
    if (jaroScore < threshold) return jaroScore;

    // 共通プレフィックスの長さを計算（最大4文字）
    size_t prefixLength = 0;
    size_t maxPrefixLength = min(min(s.length, t.length), 4);
    
    foreach (i; 0 .. maxPrefixLength)
    {
        if (s[i] == t[i])
            prefixLength++;
        else
            break;
    }

    return jaroScore + (prefixLength * 0.1 * (1.0 - jaroScore));
} 

 