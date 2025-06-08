module utils.search_utils;

import core.index_types : GramIndexType;

/**
 * 検索・インデックスに関するユーティリティ関数群
 * 
 * n-gram生成、二分探索、インデックス操作などの機能を提供します。
 * 高速な検索処理を実現するための最適化された実装です。
 */

/**
 * 配列内で指定した値以上の最初の要素のインデックスを二分探索で取得する
 *
 * ソートされた配列に対して二分探索を行い、指定した値以上の最初の要素の
 * インデックスを効率的に検索します。標準ライブラリのlowerBound相当の機能を提供します。
 *
 * Params:
 *      T = 配列の要素型
 *      arr = 検索対象のソート済み配列
 *      value = 検索する値
 *
 * Returns:
 *      指定した値以上の最初の要素のインデックス。該当する要素がない場合は配列の長さを返す
 */
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

/**
 * 配列内で指定した値より大きい最初の要素のインデックスを二分探索で取得する
 *
 * ソートされた配列に対して二分探索を行い、指定した値より大きい最初の要素の
 * インデックスを効率的に検索します。標準ライブラリのupperBound相当の機能を提供します。
 *
 * Params:
 *      T = 配列の要素型
 *      arr = 検索対象のソート済み配列
 *      value = 検索する値
 *
 * Returns:
 *      指定した値より大きい最初の要素のインデックス。該当する要素がない場合は配列の長さを返す
 */
size_t upperBound(T)(T[] arr, T value)
{
    size_t l = 0, r = arr.length;
    while (l < r)
    {
        size_t m = (l + r) / 2;
        if (arr[m] <= value)
            l = m + 1;
        else
            r = m;
    }
    return l;
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
 * 指定したn数でn-gramを生成する
 *
 * Params:
 *      word = 対象の単語
 *      n = n-gramのサイズ（デフォルト: 2）
 *
 * Returns:
 *      生成されたn-gramの配列
 */
string[] generateNGrams(string word, size_t n = 2)
{
    if (word.length < n)
        return [];

    string[] grams;
    grams.reserve(word.length - n + 1);

    for (size_t i = 0; i + n <= word.length; i++)
    {
        grams ~= word[i .. i + n];
    }

    return grams;
}

/**
 * 複数の単語から共通のn-gramを取得する
 *
 * Params:
 *      words = 単語の配列
 *      n = n-gramのサイズ（デフォルト: 2）
 *
 * Returns:
 *      すべての単語に共通するn-gramの配列
 */
string[] getCommonNGrams(string[] words, size_t n = 2)
{
    if (words.length == 0)
        return [];

    // 最初の単語のn-gramを取得
    bool[string] commonGrams;
    auto firstGrams = generateNGrams(words[0], n);
    foreach (gram; firstGrams)
    {
        commonGrams[gram] = true;
    }

    // 他の単語と比較して共通部分のみを残す
    foreach (word; words[1 .. $])
    {
        bool[string] currentGrams;
        auto grams = generateNGrams(word, n);
        foreach (gram; grams)
        {
            currentGrams[gram] = true;
        }

        // 交集合を計算
        string[] toRemove;
        foreach (gram; commonGrams.keys)
        {
            if (gram !in currentGrams)
                toRemove ~= gram;
        }

        foreach (gram; toRemove)
        {
            commonGrams.remove(gram);
        }
    }

    return commonGrams.keys;
}

/**
 * 二つの配列の交集合を取得する（ソート済み配列向け）
 *
 * Params:
 *      arr1 = 1つ目のソート済み配列
 *      arr2 = 2つ目のソート済み配列
 *
 * Returns:
 *      交集合の配列
 */
T[] intersectSorted(T)(T[] arr1, T[] arr2)
{
    T[] result;
    size_t i = 0, j = 0;

    while (i < arr1.length && j < arr2.length)
    {
        if (arr1[i] == arr2[j])
        {
            result ~= arr1[i];
            i++;
            j++;
        }
        else if (arr1[i] < arr2[j])
        {
            i++;
        }
        else
        {
            j++;
        }
    }

    return result;
}

/**
 * 二つの配列の和集合を取得する（ソート済み配列向け）
 *
 * Params:
 *      arr1 = 1つ目のソート済み配列
 *      arr2 = 2つ目のソート済み配列
 *
 * Returns:
 *      和集合の配列
 */
T[] unionSorted(T)(T[] arr1, T[] arr2)
{
    T[] result;
    size_t i = 0, j = 0;

    while (i < arr1.length && j < arr2.length)
    {
        if (arr1[i] == arr2[j])
        {
            result ~= arr1[i];
            i++;
            j++;
        }
        else if (arr1[i] < arr2[j])
        {
            result ~= arr1[i];
            i++;
        }
        else
        {
            result ~= arr2[j];
            j++;
        }
    }

    // 残りの要素を追加
    while (i < arr1.length)
    {
        result ~= arr1[i];
        i++;
    }

    while (j < arr2.length)
    {
        result ~= arr2[j];
        j++;
    }

    return result;
}

/**
 * 配列から重複を除去する（ソート済み配列向け）
 *
 * Params:
 *      arr = ソート済み配列
 *
 * Returns:
 *      重複が除去された配列
 */
T[] removeDuplicatesSorted(T)(T[] arr)
{
    if (arr.length == 0)
        return arr;

    T[] result;
    result.reserve(arr.length);
    result ~= arr[0];

    for (size_t i = 1; i < arr.length; i++)
    {
        if (arr[i] != arr[i - 1])
            result ~= arr[i];
    }

    return result;
}

/**
 * 配列内での要素の出現回数をカウントする
 *
 * Params:
 *      arr = 配列
 *      element = カウントする要素
 *
 * Returns:
 *      要素の出現回数
 */
size_t countOccurrences(T)(T[] arr, T element)
{
    size_t count = 0;
    foreach (item; arr)
    {
        if (item == element)
            count++;
    }
    return count;
}

/**
 * 範囲検索を実行する（ソート済み配列向け）
 *
 * Params:
 *      arr = ソート済み配列
 *      min = 最小値（包含）
 *      max = 最大値（包含）
 *
 * Returns:
 *      指定範囲内の要素の配列
 */
T[] rangeSearch(T)(T[] arr, T min, T max)
{
    size_t startIdx = lowerBound(arr, min);
    size_t endIdx = upperBound(arr, max);
    
    if (startIdx >= arr.length || endIdx <= startIdx)
        return [];
    
    return arr[startIdx .. endIdx];
}

/**
 * 検索結果のマージ（重複除去付き）
 *
 * Params:
 *      results = 検索結果の配列の配列
 *
 * Returns:
 *      マージされた検索結果（重複除去済み）
 */
T[] mergeSearchResults(T)(T[][] results)
{
    import std.algorithm : sort, uniq;
    import std.array : array;

    T[] merged;
    foreach (result; results)
    {
        merged ~= result;
    }

    return merged.sort().uniq().array();
}

/**
 * Jaccard係数を計算する
 *
 * 二つの集合の類似度を計算します。
 * Jaccard係数 = |A ∩ B| / |A ∪ B|
 *
 * Params:
 *      set1 = 1つ目の集合
 *      set2 = 2つ目の集合
 *
 * Returns:
 *      Jaccard係数（0.0〜1.0）
 */
double jaccardSimilarity(T)(T[] set1, T[] set2)
{
    import std.algorithm : sort, uniq;
    import std.array : array;

    // 重複を除去してユニークな集合にする
    auto uniqueSet1 = set1.sort().uniq().array();
    auto uniqueSet2 = set2.sort().uniq().array();

    // 交集合のサイズを計算
    auto intersection = intersectSorted(uniqueSet1, uniqueSet2);
    
    // 和集合のサイズを計算
    auto union_ = unionSorted(uniqueSet1, uniqueSet2);

    if (union_.length == 0)
        return 0.0;

    return cast(double)intersection.length / union_.length;
} 

 