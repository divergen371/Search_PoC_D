/**
 * データ生成モジュール
 *
 * 言語テーブルのテスト用に大量の英単語風のランダム文字列を生成し、
 * CSVファイルに出力するための機能を提供します。
 * 自然な単語に近い文字列パターンの生成をサポートしています。
 */
module data_generator;

import std.stdio;
import std.random;
import std.algorithm;
import std.array;
import std.range;
import std.conv;
import std.string;
import std.path;
import std.file;
import std.datetime.stopwatch;

/**
 * ランダム単語生成のための文字セット
 */
immutable string vowels = "aiueo";
immutable string consonants = "bcdfghjklmnpqrstvwxyz";
immutable string[] commonWordEndings = [
    "tion", "ing", "ed", "ly", "ment", "ness", "er", "or", "ist", "ism"
];

/**
 * ランダムな英単語風の文字列を生成
 *
 * 母音と子音を適切に配置して、英語らしい音韻パターンを持つ
 * ランダムな文字列を生成します。
 *
 * Params:
 *      rnd = 乱数生成器への参照
 *      minLength = 生成する単語の最小長（デフォルト3）
 *      maxLength = 生成する単語の最大長（デフォルト12）
 *
 * Returns:
 *      生成されたランダム単語
 */
string generateRandomWord(ref Random rnd, size_t minLength = 3, size_t maxLength = 12)
{
    // 長さを決定
    size_t length = uniform(minLength, maxLength + 1, rnd);

    // 単語の生成
    char[] word = new char[length];
    bool lastWasVowel = false;

    for (size_t i = 0; i < length; i++)
    {
        // 母音と子音を交互に使用する確率を高める
        bool useVowel;
        if (i == 0)
        {
            // 最初の文字は子音が多い
            useVowel = uniform(0, 4, rnd) == 0;
        }
        else
        {
            // 前の文字が母音なら子音の確率を上げる、逆も同様
            useVowel = lastWasVowel ? uniform(0, 4, rnd) == 0 : uniform(0, 3, rnd) > 0;
        }

        string charSet = useVowel ? vowels : consonants;
        word[i] = charSet[uniform(0, charSet.length, rnd)];
        lastWasVowel = useVowel;
    }

    return word.idup;
}

/**
 * より自然な単語を生成するための補助関数
 *
 * 基本的な単語に一般的な英語の接尾辞を追加することで、
 * より自然な外観の単語を生成します。
 *
 * Params:
 *      rnd = 乱数生成器への参照
 *      word = 基本となる単語
 *
 * Returns:
 *      拡張された単語（10%の確率で接尾辞が追加される）
 */
string enhanceWord(ref Random rnd, string word)
{
    // 10%の確率で語尾に一般的な接尾辞を追加
    if (uniform(0, 10, rnd) == 0 && word.length < 8)
    {
        auto ending = commonWordEndings[uniform(0, commonWordEndings.length, rnd)];
        return word ~ ending;
    }
    return word;
}

/**
 * 指定した数の単語をCSVファイルに出力
 *
 * 指定された数の一意なランダム単語を生成し、CSVファイルに書き出します。
 * 進捗表示とパフォーマンス統計も提供します。
 *
 * Params:
 *      outputPath = 出力先CSVファイルのパス
 *      wordCount = 生成する単語の数
 *      showProgress = 進捗状況を表示するかどうか（デフォルトtrue）
 */
void generateWordDataset(string outputPath, size_t wordCount, bool showProgress = true)
{
    StopWatch sw;
    sw.start();

    auto rnd = Random(unpredictableSeed);
    auto file = File(outputPath, "w");

    // ヘッダー行
    file.writeln("ID,単語,削除フラグ");

    // 重複チェック用セット
    bool[string] uniqueWords;

    // プログレスバーの更新頻度
    size_t progressStep = wordCount / 100;
    if (progressStep < 1)
        progressStep = 1;

    size_t generatedCount = 0;
    size_t id = 0;

    writefln("生成開始: %,d 単語", wordCount);

    while (generatedCount < wordCount)
    {
        // 基本的な単語を生成
        string word = generateRandomWord(rnd);

        // 自然さを向上
        word = enhanceWord(rnd, word);

        // 重複チェック
        if (word in uniqueWords)
            continue;

        // 単語を記録
        uniqueWords[word] = true;
        file.writefln("%d,%s,0", id, word);
        id++;
        generatedCount++;

        // 進捗表示
        if (showProgress && generatedCount % progressStep == 0)
        {
            double progress = cast(double) generatedCount / wordCount * 100;
            writef("\r進捗: %5.1f%% (%,d/%,d)", progress, generatedCount, wordCount);
            stdout.flush();
        }
    }

    // プログレスバー完了
    if (showProgress)
    {
        writeln("\r進捗: 100.0% 完了                     ");
    }

    file.close();
    sw.stop();

    auto fileSize = getSize(outputPath);
    writefln("生成完了: %,d 単語のデータセットを作成しました", wordCount);
    writefln("出力ファイル: %s (%,d バイト)", outputPath, fileSize);
    writefln("処理時間: %s", sw.peek);
}

/**
 * より高度なデータセット生成（ランダム削除フラグと大量データ）
 *
 * 大量のデータ生成に最適化されたバージョンです。削除フラグの
 * ランダム設定、バッファリングによる高速化、メモリ効率の向上を含みます。
 *
 * Params:
 *      outputPath = 出力先CSVファイルのパス
 *      wordCount = 生成する単語の数
 *      deletedRatio = 削除フラグを立てる単語の割合（デフォルト0.05 = 5%）
 */
void generateAdvancedDataset(string outputPath, size_t wordCount, double deletedRatio = 0.05)
{
    StopWatch sw;
    sw.start();

    auto rnd = Random(unpredictableSeed);
    auto file = File(outputPath, "w");

    // ヘッダー行
    file.writeln("ID,単語,削除フラグ");

    // 重複チェック用セット
    bool[string] uniqueWords;

    // プログレスバーの更新頻度
    size_t progressStep = wordCount / 50;
    if (progressStep < 1)
        progressStep = 1;

    // バッファリング用
    char[] buffer;
    buffer.reserve(16_384); // 16KBバッファ

    size_t generatedCount = 0;
    size_t id = 0;

    writefln("高度なデータセット生成開始: %,d 単語 (削除率: %.1f%%)",
        wordCount, deletedRatio * 100);

    while (generatedCount < wordCount)
    {
        // 基本的な単語を生成
        string word = generateRandomWord(rnd);

        // 自然さを向上
        word = enhanceWord(rnd, word);

        // 重複チェック
        if (word in uniqueWords)
            continue;

        // 削除フラグの決定
        bool isDeleted = uniform(0.0, 1.0, rnd) < deletedRatio;

        // バッファに追加
        buffer ~= to!string(id);
        buffer ~= ',';
        buffer ~= word;
        buffer ~= ',';
        buffer ~= isDeleted ? '1' : '0';
        buffer ~= '\n';

        // バッファがある程度の大きさになったら書き込む
        if (buffer.length >= 8192)
        {
            file.write(buffer);
            buffer.length = 0;
            buffer.reserve(16_384);
        }

        // 単語を記録
        uniqueWords[word] = true;
        id++;
        generatedCount++;

        // 進捗表示
        if (generatedCount % progressStep == 0)
        {
            double progress = cast(double) generatedCount / wordCount * 100;
            writef("\r進捗: %5.1f%% (%,d/%,d)", progress, generatedCount, wordCount);
            stdout.flush();
        }
    }

    // 残りのバッファを書き込む
    if (buffer.length > 0)
    {
        file.write(buffer);
    }

    // プログレスバー完了
    writeln("\r進捗: 100.0% 完了                     ");

    file.close();
    sw.stop();

    auto fileSize = getSize(outputPath);
    writefln("生成完了: %,d 単語のデータセットを作成しました", wordCount);
    writefln("出力ファイル: %s (%,d バイト)", outputPath, fileSize);
    writefln("処理時間: %s", sw.peek);
}

// void main(string[] args) {
//     string outputPath = "test_words.csv";
//     size_t wordCount = 100000; // デフォルトは10万語

//     // コマンドライン引数の処理
//     if (args.length > 1) {
//         try {
//             wordCount = to!size_t(args[1]);
//         } catch (Exception) {
//             writeln("警告: 無効な単語数指定です。デフォルトの100,000を使用します。");
//         }
//     }

//     if (args.length > 2) {
//         outputPath = args[2];
//     }

//     // データセット生成
//     writefln("大規模データセットの生成: %,d 単語", wordCount);
//     writefln("出力ファイル: %s", absolutePath(outputPath));

//     // 高度なデータセット生成を使用
//     generateAdvancedDataset(outputPath, wordCount);
// } 
