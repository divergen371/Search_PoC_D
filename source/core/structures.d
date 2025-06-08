module core.structures;

/**
 * 単語エントリの構造体
 *
 * 言語テーブルで管理される各単語の情報を格納する構造体です。
 * 単語、ID、削除フラグの3つの要素で構成され、論理削除機能をサポートします。
 */
struct WordEntry
{
    string word; /// 単語
    size_t id; /// ID
    bool isDeleted; /// 削除フラグ

    /**
     * エントリが有効（削除されていない）かを確認する
     * 
     * Returns:
     *      削除されていない場合はtrue
     */
    bool isValid() const
    {
        return !isDeleted;
    }

    /**
     * 文字列表現を取得する
     * 
     * Returns:
     *      エントリの文字列表現
     */
    string toString() const
    {
        import std.format : format;

        return format("WordEntry(id: %d, word: \"%s\", deleted: %s)", id, word, isDeleted);
    }
}

/**
 * 単語統計情報を表す構造体
 */
struct WordStatistics
{
    size_t totalWords; /// 総単語数
    size_t activeWords; /// 有効な単語数
    size_t deletedWords; /// 削除された単語数
    size_t averageLength; /// 平均文字数
    size_t minLength; /// 最短文字数
    size_t maxLength; /// 最長文字数

    /**
     * 統計情報をまとめて表示する
     */
    void display() const
    {
        import std.stdio : writefln;

        writefln("=== 単語統計情報 ===");
        writefln("総単語数: %d", totalWords);
        writefln("有効単語数: %d", activeWords);
        writefln("削除単語数: %d", deletedWords);
        writefln("平均文字数: %d", averageLength);
        writefln("最短文字数: %d", minLength);
        writefln("最長文字数: %d", maxLength);
        writefln("==================");
    }
}

/**
 * 検索モードを表す列挙型
 */
enum SearchMode
{
    Exact, /// 完全一致
    Prefix, /// 前方一致
    Suffix, /// 後方一致
    Substring, /// 部分一致
    Similarity, /// 類似検索
    AND, /// AND検索
    OR, /// OR検索
    NOT, /// NOT検索
    Length, /// 長さ検索
    IDRange /// ID範囲検索
}

/**
 * ソート順を表す列挙型
 */
enum SortOrder
{
    ID, /// ID順
    Word, /// 単語順
    Length, /// 文字数順
    Similarity /// 類似度順
}
