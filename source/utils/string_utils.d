module utils.string_utils;

/**
 * 文字列処理に関するユーティリティ関数群
 * 
 * 文字列のインターニング、変換、操作に関する機能を提供します。
 * メモリ効率と処理速度の向上を目的とした最適化された実装です。
 */

/**
 * メモリ効率の良いストリングインターニングのためのプール
 *
 * 同じ文字列の重複コピーを避けるために使用される文字列プールです。
 * 同一内容の文字列は同じメモリ領域を参照するようにして、メモリ使用量を削減します。
 */
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

/**
 * 文字列を逆順にする
 *
 * 効率的な逆順アルゴリズムを使用して文字列を反転させます。
 * サフィックス検索などで使用されます。
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
 * 文字列プールのサイズを取得する
 *
 * Returns:
 *      現在プールに保存されている文字列の数
 */
size_t getStringPoolSize()
{
    return stringPool.length;
}

/**
 * 文字列プールをクリアする
 *
 * メモリを解放するためにプールに保存されているすべての文字列を削除します。
 */
void clearStringPool()
{
    stringPool.clear();
}

/**
 * 文字列プールの統計情報を表示する
 */
void displayStringPoolStats()
{
    import std.stdio : writefln;
    
    size_t totalLength = 0;
    foreach (str; stringPool.values)
    {
        totalLength += str.length;
    }
    
    writefln("=== 文字列プール統計 ===");
    writefln("プール内文字列数: %d", stringPool.length);
    writefln("総文字数: %d", totalLength);
    writefln("平均文字数: %.2f", stringPool.length > 0 ? cast(double)totalLength / stringPool.length : 0.0);
    writefln("=====================");
}

/**
 * 文字列の最初の文字を大文字にする
 *
 * Params:
 *      s = 変換する文字列
 *
 * Returns:
 *      最初の文字が大文字になった文字列
 */
string capitalize(string s)
{
    if (s.length == 0)
        return s;
    
    import std.ascii : toUpper, toLower;
    
    char[] result = s.dup;
    result[0] = toUpper(result[0]);
    
    return cast(string) result;
}

/**
 * 文字列をすべて小文字にする
 *
 * Params:
 *      s = 変換する文字列
 *
 * Returns:
 *      すべて小文字になった文字列
 */
string toLowerString(string s)
{
    import std.ascii : toLower;
    
    char[] result = new char[s.length];
    foreach (i, char c; s)
    {
        result[i] = toLower(c);
    }
    
    return cast(string) result;
}

/**
 * 文字列をすべて大文字にする
 *
 * Params:
 *      s = 変換する文字列
 *
 * Returns:
 *      すべて大文字になった文字列
 */
string toUpperString(string s)
{
    import std.ascii : toUpper;
    
    char[] result = new char[s.length];
    foreach (i, char c; s)
    {
        result[i] = toUpper(c);
    }
    
    return cast(string) result;
}

/**
 * 文字列の前後の空白を除去する
 *
 * Params:
 *      s = トリムする文字列
 *
 * Returns:
 *      前後の空白が除去された文字列
 */
string trimString(string s)
{
    import std.ascii : isWhite;
    
    if (s.length == 0)
        return s;
    
    size_t start = 0;
    size_t end = s.length;
    
    // 先頭の空白をスキップ
    while (start < end && isWhite(s[start]))
        start++;
    
    // 末尾の空白をスキップ
    while (end > start && isWhite(s[end - 1]))
        end--;
    
    return s[start .. end];
}

/**
 * 文字列が数字のみで構成されているかチェックする
 *
 * Params:
 *      s = チェックする文字列
 *
 * Returns:
 *      数字のみの場合はtrue
 */
bool isNumericString(string s)
{
    import std.ascii : isDigit;
    
    if (s.length == 0)
        return false;
    
    foreach (char c; s)
    {
        if (!isDigit(c))
            return false;
    }
    
    return true;
}

/**
 * 文字列が英字のみで構成されているかチェックする
 *
 * Params:
 *      s = チェックする文字列
 *
 * Returns:
 *      英字のみの場合はtrue
 */
bool isAlphaString(string s)
{
    import std.ascii : isAlpha;
    
    if (s.length == 0)
        return false;
    
    foreach (char c; s)
    {
        if (!isAlpha(c))
            return false;
    }
    
    return true;
}

/**
 * 文字列が英数字のみで構成されているかチェックする
 *
 * Params:
 *      s = チェックする文字列
 *
 * Returns:
 *      英数字のみの場合はtrue
 */
bool isAlphaNumericString(string s)
{
    import std.ascii : isAlphaNum;
    
    if (s.length == 0)
        return false;
    
    foreach (char c; s)
    {
        if (!isAlphaNum(c))
            return false;
    }
    
    return true;
} 

 